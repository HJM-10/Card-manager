from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4

from fastapi.testclient import TestClient
import pytest

from app import db, main
from app.notifications import claim_event, expand_outbox
from app.notification_worker import DeliveryError, process_claim, run_once, retry_after_seconds
from test_accounts_cards import client, account, purchase_payload


class Sender:
    def __init__(self, error=None):
        self.calls = []
        self.error = error

    def send(self, token, event):
        self.calls.append((token, event['id']))
        if self.error:
            raise self.error
        return 'projects/test/messages/' + str(event['id'])


def setup(client):
    headers = account(client)
    device = str(uuid4())
    token = 'synthetic-device-token-' + uuid4().hex
    assert client.put('/devices/' + device, headers=headers, json={'token': token}).status_code == 200
    purchase = purchase_payload(client, headers)
    saved = client.post('/transactions', headers=headers, json=purchase)
    assert saved.status_code == 201
    return headers, device, token, purchase, saved.json()


def force_due():
    with db.connect() as conn:
        conn.execute("UPDATE notification_events SET next_attempt_at = now() - interval '1 second', lease_until = now() - interval '1 second'")


def test_committed_events_fan_out_once_and_receipt_is_distinct_from_acceptance(client):
    headers, device, _, purchase, saved = setup(client)
    assert client.post('/transactions', headers=headers, json=purchase).status_code == 200
    sender = Sender()
    assert run_once(sender, connection=db.connect)
    run_once(sender, connection=db.connect)
    events = client.get('/notifications', headers=headers).json()
    assert len(events) == 1 and len(sender.calls) == 1
    event = events[0]
    assert event['transaction_id'] == saved['id'] and event['device_id'] == device
    assert event['status'] == 'accepted' and event['accepted_at'] is not None
    assert event['received_at'] is None and event['opened_at'] is None
    path = '/notifications/' + event['id'] + '/observations'
    assert client.post(path, headers=headers, json={'action': 'opened'}).status_code == 204
    first = client.get('/notifications/' + event['id'], headers=headers).json()
    client.post(path, headers=headers, json={'action': 'opened'})
    assert client.get('/notifications/' + event['id'], headers=headers).json()['opened_at'] == first['opened_at']
    assert first['received_at'] is not None
    bob = account(client, 'bob@example.com')
    assert client.get('/notifications/' + event['id'], headers=bob).status_code == 404
    assert client.post(path, headers=bob, json={'action': 'received'}).status_code == 404
    assert client.get('/notifications', headers=bob).json() == []


def test_transient_failures_back_off_and_stop_after_five_attempts(client):
    headers, _, _, _, _ = setup(client)
    sender = Sender(DeliveryError('fcm_http_429', retry_after=120))
    for attempt in range(1, 6):
        run_once(sender, connection=db.connect)
        with db.connect() as conn:
            event = conn.execute('SELECT *, extract(epoch FROM next_attempt_at - now()) AS delay FROM notification_events').fetchone()
        assert event['attempts'] == attempt
        assert event['status'] == ('pending' if attempt < 5 else 'failed')
        assert event['delay'] > 110
        if attempt < 5:
            assert not run_once(sender, connection=db.connect)
        force_due()
    assert not run_once(sender, connection=db.connect)
    assert len(sender.calls) == 5
    assert client.get('/notifications', headers=headers).json()[0]['last_error'] == 'fcm_http_429'
    assert retry_after_seconds('120') == 120 and retry_after_seconds('bad') == 0


def test_interrupted_worker_recovers_same_event_and_exhausted_lease_is_terminal(client):
    setup(client)
    sender = Sender(RuntimeError('Simulated worker interruption after send'))
    with pytest.raises(RuntimeError):
        run_once(sender, connection=db.connect)
    assert not run_once(Sender(), connection=db.connect)
    force_due()
    accepted = Sender()
    run_once(accepted, connection=db.connect)
    assert sender.calls[0][1] == accepted.calls[0][1]
    with db.connect() as conn:
        event = conn.execute('SELECT * FROM notification_events').fetchone()
        assert event['attempts'] == 2 and event['status'] == 'accepted'
        conn.execute("UPDATE notification_events SET status = 'processing', attempts = 5, lease_id = %s, lease_until = now() - interval '1 second'", (uuid4(),))
    run_once(accepted, connection=db.connect)
    with db.connect() as conn:
        event = conn.execute('SELECT * FROM notification_events').fetchone()
        assert event['status'] == 'failed' and event['last_error'] == 'delivery_uncertain'


def test_disabled_devices_and_account_switch_cancel_old_pending_delivery(client):
    alice, device, token, _, _ = setup(client)
    with db.connect() as conn:
        expand_outbox(conn)
    bob = account(client, 'bob@example.com')
    assert client.put('/devices/' + device, headers=bob, json={'token': token}).status_code == 404
    bob_device = str(uuid4())
    assert client.put('/devices/' + bob_device, headers=bob, json={'token': token}).status_code == 200
    assert client.get('/devices/' + device, headers=alice).json()['enabled'] is False
    assert client.get('/notifications', headers=alice).json()[0]['status'] == 'cancelled'
    sender = Sender()
    run_once(sender, connection=db.connect)
    assert sender.calls == []
    assert client.delete('/devices/' + device, headers=bob).status_code == 404
    assert client.delete('/devices/' + bob_device, headers=bob).status_code == 204


def test_token_rotation_unregistering_and_logout_do_not_leave_active_targets(client):
    headers, device, token, purchase, _ = setup(client)
    rotated = token + '-rotated'
    assert client.put('/devices/' + device, headers=headers, json={'token': rotated}).status_code == 200
    sender = Sender(DeliveryError('unregistered', retryable=False, invalid_token=True))
    run_once(sender, connection=db.connect)
    assert sender.calls[0][0] == rotated
    assert client.get('/devices/' + device, headers=headers).json()['enabled'] is False
    assert client.get('/notifications', headers=headers).json()[0]['status'] == 'failed'
    assert client.put('/devices/' + device, headers=headers, json={'token': token + '-new'}).status_code == 200
    client.post('/transactions', headers=headers, json={**purchase, 'source_reference': str(uuid4())})
    with db.connect() as conn:
        expand_outbox(conn)
    assert client.delete('/auth/session', headers=headers).status_code == 204
    with db.connect() as conn:
        assert conn.execute('SELECT enabled FROM device_registrations').fetchone()['enabled'] is False
        assert conn.execute("SELECT count(*) AS n FROM notification_events WHERE status IN ('pending', 'processing')").fetchone()['n'] == 0


def test_no_historical_alerts_and_parallel_workers_claim_one_delivery(client):
    headers = account(client)
    purchase = purchase_payload(client, headers)
    client.post('/transactions', headers=headers, json=purchase)
    device = str(uuid4())
    token = 'synthetic-device-' + uuid4().hex
    client.put('/devices/' + device, headers=headers, json={'token': token})
    run_once(Sender(), connection=db.connect)
    assert client.get('/notifications', headers=headers).json() == []
    client.delete('/devices/' + device, headers=headers)
    client.post('/transactions', headers=headers, json={**purchase, 'source_reference': str(uuid4())})
    client.put('/devices/' + device, headers=headers, json={'token': token})
    run_once(Sender(), connection=db.connect)
    assert client.get('/notifications', headers=headers).json() == []
    client.post('/transactions', headers=headers, json={**purchase, 'source_reference': str(uuid4())})
    with db.connect() as conn:
        expand_outbox(conn)
    def claim(_):
        with db.connect() as conn:
            return claim_event(conn)
    with ThreadPoolExecutor(max_workers=2) as executor:
        claims = list(executor.map(claim, range(2)))
    assert sum(c is not None for c in claims) == 1
    sender = Sender()
    process_claim(next(c for c in claims if c), sender, connection=db.connect)
    assert len(sender.calls) == 1


def test_concurrent_logout_and_registration_cannot_restore_device(client):
    headers, device, token, _, _ = setup(client)
    def action(register):
        with TestClient(main.app) as api:
            if register:
                return api.put('/devices/' + device, headers=headers, json={'token': token}).status_code
            return api.delete('/auth/session', headers=headers).status_code
    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(action, [True, False]))
    assert results[0] in (200, 401) and results[1] == 204
    with db.connect() as conn:
        assert conn.execute('SELECT enabled FROM device_registrations').fetchone()['enabled'] is False


def test_registration_and_event_inputs_require_valid_owned_session(client):
    headers, device, token, _, _ = setup(client)
    assert client.put('/devices/' + device, json={'token': token}).status_code == 401
    for body in [{'token': 'short'}, {'token': token, 'platform': 'ios'}, {'token': token, 'user_id': str(uuid4())}]:
        assert client.put('/devices/' + device, headers=headers, json=body).status_code == 422
    assert client.get('/notifications?limit=101', headers=headers).status_code == 422
    assert client.get('/notifications/' + str(uuid4()), headers=headers).status_code == 404
    assert client.delete('/auth/access', headers=headers).status_code == 204
    with db.connect() as conn:
        assert conn.execute('SELECT enabled FROM device_registrations').fetchone()['enabled'] is False


def test_disabling_biometric_family_pauses_only_revoked_access_devices(client):
    headers, device, _, _, _ = setup(client)
    credential = client.post('/auth/biometric', headers=headers).json()['refresh_token']
    derived = client.post('/auth/biometric/refresh', json={'refresh_token': credential}).json()['access_token']
    second_headers = {'Authorization': 'Bearer ' + derived}
    second_device = str(uuid4())
    assert client.put('/devices/' + second_device, headers=second_headers, json={'token': 'synthetic-derived-device-' + uuid4().hex}).status_code == 200
    assert client.delete('/auth/biometric', headers=headers).status_code == 204
    assert client.get('/devices/' + device, headers=headers).json()['enabled'] is True
    assert client.get('/devices/' + second_device, headers=headers).json()['enabled'] is False
    assert client.get('/auth/me', headers=second_headers).status_code == 401
