from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal
from uuid import uuid4

import psycopg
import pytest
from fastapi.testclient import TestClient

from app import db, main
from test_accounts_cards import client, account, purchase_payload


def setup_purchase(client, status='approved'):
    headers = account(client)
    payload = {**purchase_payload(client, headers), 'status': status}
    result = client.post('/simulations/purchases', headers=headers, json=payload)
    assert result.status_code == 201, result.text
    return headers, payload, result.json()


def refund_body(amount='250.05'):
    return {'amount': amount, 'occurred_at': '2026-11-06T10:30:00+05:00', 'source_reference': str(uuid4())}


def test_simulation_retry_status_filters_and_isolation(client):
    headers, payload, saved = setup_purchase(client, 'declined')
    replay = client.post('/simulations/purchases', headers=headers, json=payload)
    assert replay.status_code == 200 and replay.json() == saved
    assert client.post('/simulations/purchases', headers=headers, json={**payload, 'status': 'approved'}).status_code == 409
    assert client.get('/transactions?status=declined&kind=purchase', headers=headers).json() == [saved]
    assert client.get('/transactions?status=approved', headers=headers).json() == []
    assert client.get('/transactions?status=unknown', headers=headers).status_code == 422
    bob = account(client, 'bob@example.com')
    assert client.post('/simulations/purchases', headers=bob, json=payload).status_code == 404
    path = '/transactions/' + saved['id'] + '/refunds'
    assert client.post(path, headers=bob, json=refund_body()).status_code == 404
    assert client.post(path, headers=headers, json=refund_body()).status_code == 422
    with db.connect() as conn:
        assert conn.execute('SELECT sum(spending_amount) AS total FROM transaction_spending').fetchone()['total'] == 0


def test_partial_refunds_exact_total_retry_and_archived_card(client):
    headers, payload, saved = setup_purchase(client)
    path = '/transactions/' + saved['id'] + '/refunds'
    body = refund_body()
    refund = client.post(path, headers=headers, json=body)
    assert refund.status_code == 201, refund.text
    assert refund.json()['original_purchase_id'] == saved['id']
    assert refund.json()['amount'] == '250.05'
    assert client.post(path, headers=headers, json=body).json() == refund.json()
    assert client.post(path, headers=headers, json={**body, 'amount': '250.06'}).status_code == 409
    assert client.post(path, headers=headers, json=refund_body('1000.01')).status_code == 409
    assert client.delete('/cards/' + payload['card_id'], headers=headers).status_code == 204
    assert client.post(path, headers=headers, json=refund_body('1000.00')).status_code == 201
    assert client.post(path, headers=headers, json=refund_body('0.01')).status_code == 409
    assert client.post('/transactions/' + refund.json()['id'] + '/refunds', headers=headers, json=refund_body()).status_code == 422
    with db.connect() as conn:
        assert conn.execute('SELECT sum(spending_amount) AS total FROM transaction_spending').fetchone()['total'] == Decimal('0.00')
        for table in ('spending_transactions', 'transaction_audit_events', 'transaction_outbox'):
            assert conn.execute(f'SELECT count(*) AS n FROM {table}').fetchone()['n'] == 3


def test_concurrent_refunds_cannot_exceed_purchase(client):
    headers, _, saved = setup_purchase(client)
    path = '/transactions/' + saved['id'] + '/refunds'
    def create(_):
        with TestClient(main.app) as api:
            return api.post(path, headers=headers, json=refund_body('800.00')).status_code
    with ThreadPoolExecutor(max_workers=2) as executor:
        assert sorted(executor.map(create, range(2))) == [201, 409]
    body = refund_body('450.05')
    def retry(_):
        with TestClient(main.app) as api:
            return api.post(path, headers=headers, json=body).status_code
    with ThreadPoolExecutor(max_workers=2) as executor:
        assert sorted(executor.map(retry, range(2))) == [200, 201]
    with db.connect() as conn:
        assert conn.execute('SELECT sum(spending_amount) AS total FROM transaction_spending').fetchone()['total'] == 0
        assert conn.execute('SELECT count(*) AS n FROM transaction_outbox').fetchone()['n'] == 3


def test_refund_validation_atomic_rollback_and_immutable_fields(client):
    headers, _, saved = setup_purchase(client)
    path = '/transactions/' + saved['id'] + '/refunds'
    for invalid in [{'amount': '0.00'}, {'amount': '1.001'}, {'amount': 2}, {'occurred_at': '2026-11-04T00:00:00Z'}, {'occurred_at': '2026-11-06'}, {'status': 'declined'}]:
        assert client.post(path, headers=headers, json={**refund_body(), **invalid}).status_code == 422
    with pytest.raises(psycopg.errors.CheckViolation):
        with db.connect() as conn:
            conn.execute('UPDATE spending_transactions SET amount = 2 WHERE id = %s', (saved['id'],))
    with db.connect() as conn:
        conn.execute('ALTER TABLE transaction_outbox ADD CHECK (false) NOT VALID')
    with TestClient(main.app, raise_server_exceptions=False) as api:
        assert api.post(path, headers=headers, json=refund_body()).status_code == 500
    with db.connect() as conn:
        for table in ('spending_transactions', 'transaction_audit_events', 'transaction_outbox'):
            assert conn.execute(f'SELECT count(*) AS n FROM {table}').fetchone()['n'] == 1


def test_database_refund_constraints(client):
    headers, _, saved = setup_purchase(client)
    path = '/transactions/' + saved['id'] + '/refunds'
    refund = client.post(path, headers=headers, json=refund_body('1000.00')).json()
    # Direct writes must obey the same ceiling, independently of API checks.
    with pytest.raises(psycopg.errors.CheckViolation):
        with db.connect() as conn:
            conn.execute('''INSERT INTO spending_transactions
                (id, user_id, card_id, merchant_id, amount, occurred_at, source, source_reference, kind, status, channel, original_purchase_id)
                SELECT %s, user_id, card_id, merchant_id, 250.06, occurred_at, source, %s, kind, status, channel, original_purchase_id
                FROM spending_transactions WHERE id = %s''', (uuid4(), str(uuid4()), refund['id']))


def test_direct_concurrent_refunds_obey_database_ceiling(client):
    _, _, saved = setup_purchase(client)
    def insert(_):
        try:
            with db.connect() as conn:
                conn.execute('''INSERT INTO spending_transactions
                    (id, user_id, card_id, merchant_id, amount, occurred_at, source, source_reference, kind, status, channel, original_purchase_id)
                    SELECT %s, user_id, card_id, merchant_id, 800.00, occurred_at, 'simulation', %s, 'refund', 'approved', channel, id
                    FROM spending_transactions WHERE id = %s''', (uuid4(), str(uuid4()), saved['id']))
            return 'committed'
        except psycopg.errors.CheckViolation:
            return 'rejected'
    with ThreadPoolExecutor(max_workers=2) as executor:
        assert sorted(executor.map(insert, range(2))) == ['committed', 'rejected']
    with db.connect() as conn:
        assert conn.execute('SELECT sum(spending_amount) AS total FROM transaction_spending').fetchone()['total'] == Decimal('450.05')


def test_fixed_month_boundary_and_signed_spending_examples(client):
    headers, payload, saved = setup_purchase(client)
    # PKR 1250.05 + 300.00 - 250.05 = 1300.00 in November; decline contributes zero.
    for amount, status, timestamp in [
        ('300.00', 'approved', '2026-11-30T23:59:59+05:00'),
        ('900.00', 'declined', '2026-11-10T12:00:00+05:00'),
        ('50.00', 'approved', '2026-12-01T00:00:00+05:00'),
    ]:
        assert client.post('/simulations/purchases', headers=headers, json={**payload, 'amount': amount, 'status': status, 'occurred_at': timestamp, 'source_reference': str(uuid4())}).status_code == 201
    assert client.post('/transactions/' + saved['id'] + '/refunds', headers=headers, json=refund_body()).status_code == 201
    with db.connect() as conn:
        total = conn.execute("SELECT sum(spending_amount) AS amount FROM transaction_spending WHERE occurred_at >= '2026-11-01T00:00:00+05:00' AND occurred_at < '2026-12-01T00:00:00+05:00'").fetchone()['amount']
        assert total == Decimal('1300.00')
