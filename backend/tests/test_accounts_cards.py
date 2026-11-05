import os
from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4

import psycopg
import pytest
from fastapi.testclient import TestClient
from psycopg import sql
from psycopg.rows import dict_row

from app import db, main


@pytest.fixture()
def client(monkeypatch):
    url = os.environ.get('TEST_DATABASE_URL')
    if not url:
        pytest.fail('Set TEST_DATABASE_URL to a PostgreSQL test database')
    schema = 'test_' + uuid4().hex
    with psycopg.connect(url) as conn:
        conn.execute(sql.SQL('CREATE SCHEMA {}').format(sql.Identifier(schema)))

    def connect():
        return psycopg.connect(url, options=f'-csearch_path={schema}', row_factory=dict_row)

    monkeypatch.setattr(db, 'connect', connect)
    monkeypatch.setattr(main, 'connect', connect)
    try:
        db.migrate()
        db.migrate()  # A second run must be harmless.
        with TestClient(main.app) as api:
            yield api
    finally:
        with psycopg.connect(url) as conn:
            conn.execute(sql.SQL('DROP SCHEMA {} CASCADE').format(sql.Identifier(schema)))


PASSWORD = 'synthetic-passphrase-123'
CARD = {'label': 'Daily spending', 'network': 'visa', 'last4': '4242', 'expiry_month': 12, 'expiry_year': 2099}


def account(client, email='alice@example.com'):
    response = client.post('/auth/register', json={'email': email, 'password': PASSWORD, 'name': 'Alice'})
    assert response.status_code == 201, response.text
    data = response.json()
    assert 'password_hash' not in data['user']
    return {'Authorization': 'Bearer ' + data['access_token']}


def test_restart_login_and_persistence(client):
    headers = account(client)
    response = client.post('/cards', headers=headers, json=CARD)
    assert response.status_code == 201
    card = response.json()
    # Fresh app/client; no shared session memory or local card cache.
    with TestClient(main.app) as restarted:
        login = restarted.post('/auth/login', json={'email': 'ALICE@example.com', 'password': PASSWORD})
        assert login.status_code == 200
        new_headers = {'Authorization': 'Bearer ' + login.json()['access_token']}
        assert restarted.get('/cards', headers=new_headers).json() == [card]
        assert restarted.get('/auth/me', headers=new_headers).json()['email'] == 'alice@example.com'
    with db.connect() as conn:
        stored = conn.execute('SELECT password_hash FROM users').fetchone()['password_hash']
        assert stored != PASSWORD and stored.startswith('$argon2')
        assert conn.execute('SELECT token_hash FROM sessions').fetchone()['token_hash'] != headers['Authorization'][7:]


def test_user_isolation_update_and_archive(client):
    alice, bob = account(client), account(client, 'bob@example.com')
    card = client.post('/cards', headers=alice, json=CARD).json()
    path = '/cards/' + card['id']
    assert client.get('/cards', headers=bob).json() == []
    assert client.patch(path, headers=bob, json={**CARD, 'label': 'Stolen'}).status_code == 404
    assert client.delete(path, headers=bob).status_code == 404
    assert client.patch(path, headers=alice, json={**CARD, 'label': 'Updated'}).json()['label'] == 'Updated'
    assert client.delete(path, headers=alice).status_code == 204
    assert client.get('/cards', headers=alice).json() == []
    with db.connect() as conn:
        assert conn.execute('SELECT archived FROM card_profiles').fetchone()['archived']


def test_authentication_expiry_and_revocation(client):
    assert client.get('/cards').status_code == 401
    headers = account(client)
    assert client.post('/auth/login', json={'email': 'alice@example.com', 'password': 'wrong-password'}).status_code == 401
    assert client.delete('/auth/session', headers=headers).status_code == 204
    assert client.get('/cards', headers=headers).status_code == 401
    headers = {'Authorization': 'Bearer ' + client.post('/auth/login', json={'email': 'alice@example.com', 'password': PASSWORD}).json()['access_token']}
    with db.connect() as conn:
        conn.execute("UPDATE sessions SET expires_at = now() - interval '1 second'")
    assert client.get('/cards', headers=headers).status_code == 401


def test_validation_duplicates_and_no_credentials(client):
    headers = account(client)
    assert client.post('/auth/register', json={'email': 'ALICE@example.com', 'password': PASSWORD, 'name': 'Another'}).status_code == 409
    for invalid in [{'last4': '4242424242424242'}, {'cvv': '123'}, {'user_id': str(uuid4())}, {'label': ' '}, {'expiry_year': 2026, 'expiry_month': 1}]:
        assert client.post('/cards', headers=headers, json={**CARD, **invalid}).status_code == 422
    assert client.post('/cards', headers=headers, json=CARD).status_code == 201
    assert client.post('/cards', headers=headers, json=CARD).status_code == 409
    assert len(client.get('/cards', headers=headers).json()) == 1


def test_concurrent_duplicate_cards_commit_once(client):
    headers = account(client)
    def create(_):
        with TestClient(main.app) as request_client:
            return request_client.post('/cards', headers=headers, json=CARD).status_code
    with ThreadPoolExecutor(max_workers=2) as executor:
        assert sorted(executor.map(create, range(2))) == [201, 409]
    assert len(client.get('/cards', headers=headers).json()) == 1


def test_database_constraints_and_rollback(client):
    account(client)
    with pytest.raises(psycopg.errors.CheckViolation):
        with db.connect() as conn:
            user_id = conn.execute('SELECT id FROM users').fetchone()['id']
            conn.execute("INSERT INTO card_profiles (id,user_id,label,network,last4,expiry_month,expiry_year) VALUES (%s,%s,'Valid','visa','1234',12,2099)", (uuid4(), user_id))
            conn.execute("INSERT INTO card_profiles (id,user_id,label,network,last4,expiry_month,expiry_year) VALUES (%s,%s,'Invalid','visa','invalid',12,2099)", (uuid4(), user_id))
    with db.connect() as conn:
        assert conn.execute('SELECT count(*) AS n FROM card_profiles').fetchone()['n'] == 0


def purchase_payload(client, headers):
    card = client.post('/cards', headers=headers, json=CARD)
    assert card.status_code == 201, card.text
    return {
        'card_id': card.json()['id'],
        'merchant': 'Corner Market',
        'amount': '1250.05',
        'occurred_at': '2026-11-05T10:30:00+05:00',
        'channel': 'pos',
        'source_reference': str(uuid4()),
    }


def test_manual_purchase_history_and_archived_card(client):
    alice = account(client)
    bob = account(client, 'bob@example.com')
    purchase = purchase_payload(client, alice)
    assert client.post('/transactions', headers=bob, json=purchase).status_code == 404
    response = client.post('/transactions', headers=alice, json=purchase)
    assert response.status_code == 201, response.text
    saved = response.json()
    assert (saved['amount'], saved['currency'], saved['kind'], saved['status']) == ('1250.05', 'PKR', 'purchase', 'approved')
    path = '/transactions/' + saved['id']
    assert client.get(path, headers=bob).status_code == 404
    assert client.get('/transactions', headers=bob).json() == []
    assert client.get('/transactions').status_code == 401

    older = {**purchase, 'source_reference': str(uuid4()), 'occurred_at': '2026-10-31T23:59:00+05:00'}
    response = client.post('/transactions', headers=alice, json=older)
    assert response.status_code == 201, response.text
    assert client.get('/transactions?limit=1', headers=alice).json() == [saved]
    assert client.get('/transactions?limit=1&offset=1', headers=alice).json() == [response.json()]

    assert client.delete('/cards/' + purchase['card_id'], headers=alice).status_code == 204
    login = client.post('/auth/login', json={'email': 'alice@example.com', 'password': PASSWORD})
    assert login.status_code == 200
    new_session = {'Authorization': 'Bearer ' + login.json()['access_token']}
    assert client.get(path, headers=new_session).json() == saved
    retry = client.post('/transactions', headers=new_session, json=purchase)
    assert retry.status_code == 200
    assert retry.json() == saved
    new_purchase = {**purchase, 'source_reference': str(uuid4())}
    assert client.post('/transactions', headers=new_session, json=new_purchase).status_code == 404


def test_purchase_validation_and_concurrent_retries(client):
    headers = account(client)
    purchase = purchase_payload(client, headers)
    for invalid in [
        {'amount': '12.001'}, {'amount': '0.00'}, {'amount': 12.50},
        {'occurred_at': '2026-11-05T10:30:00'}, {'channel': 'bank_feed'},
        {'merchant': ' '}, {'status': 'declined'},
    ]:
        assert client.post('/transactions', headers=headers, json={**purchase, **invalid}).status_code == 422

    def create(_):
        with TestClient(main.app) as request_client:
            response = request_client.post('/transactions', headers=headers, json=purchase)
            return response.status_code, response.json()

    with ThreadPoolExecutor(max_workers=2) as executor:
        first, second = executor.map(create, range(2))
    assert sorted([first[0], second[0]]) == [200, 201]
    assert first[1] == second[1]
    changed = {**purchase, 'amount': '1250.06'}
    assert client.post('/transactions', headers=headers, json=changed).status_code == 409
    with db.connect() as conn:
        for table in ('spending_transactions', 'transaction_audit_events', 'transaction_outbox'):
            count = conn.execute(sql.SQL('SELECT count(*) AS n FROM {}').format(sql.Identifier(table))).fetchone()
            assert count['n'] == 1


def test_outbox_failure_rolls_back_purchase_and_audit(client):
    headers = account(client)
    purchase = purchase_payload(client, headers)
    with db.connect() as conn:
        conn.execute('ALTER TABLE transaction_outbox ADD CHECK (false)')
    with TestClient(main.app, raise_server_exceptions=False) as request_client:
        assert request_client.post('/transactions', headers=headers, json=purchase).status_code == 500
    with db.connect() as conn:
        for table in ('merchants', 'spending_transactions', 'transaction_audit_events', 'transaction_outbox'):
            count = conn.execute(sql.SQL('SELECT count(*) AS n FROM {}').format(sql.Identifier(table))).fetchone()
            assert count['n'] == 0
