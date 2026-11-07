import os
from pathlib import Path
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


def test_categories_are_owned_validated_and_case_insensitive(client):
    alice, bob = account(client), account(client, 'bob@example.com')
    categories = client.get('/categories', headers=alice).json()
    assert {c['name'] for c in categories} == set(main.DEFAULT_CATEGORIES)
    assert {c['id'] for c in categories}.isdisjoint(c['id'] for c in client.get('/categories', headers=bob).json())
    created = client.post('/categories', headers=alice, json={'name': '  Health  '})
    assert created.status_code == 201
    assert created.json()['name'] == 'Health'
    assert client.post('/categories', headers=alice, json={'name': 'health'}).status_code == 409
    assert client.post('/categories', headers=bob, json={'name': 'Health'}).status_code == 201
    for body in [{'name': ' '}, {'name': 'x' * 51}, {'name': 'Health', 'user_id': str(uuid4())}]:
        assert client.post('/categories', headers=alice, json=body).status_code == 422
    assert client.get('/categories').status_code == 401
    assert client.post('/categories', json={'name': 'Health'}).status_code == 401


def test_categorization_persists_and_preserves_creation_retry(client):
    alice, bob = account(client), account(client, 'bob@example.com')
    categories = client.get('/categories', headers=alice).json()
    first, second = categories[:2]
    purchase = {**purchase_payload(client, alice), 'category_id': first['id']}
    saved = client.post('/transactions', headers=alice, json=purchase).json()
    assert saved['category_id'] == first['id'] and saved['category'] == first['name']
    path = '/transactions/' + saved['id']
    assert client.patch(path + '/category', headers=bob, json={'category_id': None}).status_code == 404
    foreign = client.get('/categories', headers=bob).json()[0]['id']
    assert client.patch(path + '/category', headers=alice, json={'category_id': foreign}).status_code == 404
    assert client.post('/transactions', headers=alice, json={**purchase, 'source_reference': str(uuid4()), 'category_id': foreign}).status_code == 404
    assert client.patch(path + '/category', headers=alice, json={}).status_code == 422
    changed = client.patch(path + '/category', headers=alice, json={'category_id': second['id']})
    assert changed.status_code == 200 and changed.json()['category'] == second['name']
    # A retry of the original creation request must not undo recategorization.
    replay = client.post('/transactions', headers=alice, json=purchase)
    assert replay.status_code == 200 and replay.json() == changed.json()
    assert client.post('/transactions', headers=alice, json={**purchase, 'category_id': second['id']}).status_code == 409
    login = client.post('/auth/login', json={'email': 'alice@example.com', 'password': PASSWORD})
    fresh = {'Authorization': 'Bearer ' + login.json()['access_token']}
    assert client.get(path, headers=fresh).json()['category_id'] == second['id']
    assert client.delete('/cards/' + purchase['card_id'], headers=alice).status_code == 204
    assert client.patch(path + '/category', headers=fresh, json={'category_id': None}).json()['category'] is None
    assert client.get('/transactions', headers=fresh, params={'uncategorized': True}).json()[0]['id'] == saved['id']
    with db.connect() as conn:
        for table in ('spending_transactions', 'transaction_audit_events', 'transaction_outbox'):
            assert conn.execute(sql.SQL('SELECT count(*) AS n FROM {}').format(sql.Identifier(table))).fetchone()['n'] == 1


def test_history_combines_literal_search_card_category_dates_and_pagination(client):
    alice, bob = account(client), account(client, 'bob@example.com')
    purchase = purchase_payload(client, alice)
    category = client.get('/categories', headers=alice).json()[0]['id']
    other_card = client.post('/cards', headers=alice, json={**CARD, 'last4': '5678'}).json()['id']
    rows = []
    for merchant, occurred_at, card_id, category_id in [
        ('Market 100%_special', '2026-11-04T23:59:59+05:00', purchase['card_id'], category),
        ('Market 100%_special', '2026-11-05T00:00:00+05:00', purchase['card_id'], category),
        ('MARKET 100%_special', '2026-11-05T23:59:59+05:00', purchase['card_id'], category),
        ('Market 100%_special', '2026-11-06T00:00:00+05:00', purchase['card_id'], category),
        ('Another store', '2026-11-05T12:00:00+05:00', other_card, None),
    ]:
        result = client.post('/transactions', headers=alice, json={**purchase, 'source_reference': str(uuid4()), 'merchant': merchant, 'occurred_at': occurred_at, 'card_id': card_id, 'category_id': category_id})
        assert result.status_code == 201, result.text
        rows.append(result.json())
    filters = {'search': '  market 100%_  ', 'card_id': purchase['card_id'], 'category_id': category,
               'occurred_from': '2026-11-05T00:00:00+05:00', 'occurred_before': '2026-11-06T00:00:00+05:00'}
    assert client.get('/transactions', headers=alice, params=filters).json() == [rows[2], rows[1]]
    assert client.get('/transactions', headers=alice, params={**filters, 'limit': 1, 'offset': 1}).json() == [rows[1]]
    assert client.get('/transactions', headers=alice, params={'card_id': other_card, 'uncategorized': True}).json() == [rows[4]]
    assert client.get('/transactions', headers=alice, params={'search': "' OR true --"}).json() == []
    assert client.get('/transactions', headers=bob, params=filters).json() == []
    assert client.delete('/cards/' + purchase['card_id'], headers=alice).status_code == 204
    assert len(client.get('/cards', headers=alice).json()) == 1
    assert len(client.get('/cards?include_archived=true', headers=alice).json()) == 2
    assert client.get('/transactions', headers=alice, params=filters).json() == [rows[2], rows[1]]
    for invalid in [
        {'card_id': 'invalid'}, {'category_id': 'invalid'}, {'search': 'x' * 101},
        {'occurred_from': '2026-11-05T00:00:00'},
        {'occurred_from': filters['occurred_before'], 'occurred_before': filters['occurred_from']},
        {'category_id': category, 'uncategorized': True},
    ]:
        assert client.get('/transactions', headers=alice, params=invalid).status_code == 422


def test_database_trigger_blocks_cross_user_category_assignment(client):
    alice, bob = account(client), account(client, 'bob@example.com')
    purchase = client.post('/transactions', headers=alice, json=purchase_payload(client, alice)).json()
    foreign = client.get('/categories', headers=bob).json()[0]['id']
    for column in ('category_id', 'recorded_category_id'):
        with pytest.raises(psycopg.errors.CheckViolation):
            with db.connect() as conn:
                conn.execute(sql.SQL('UPDATE spending_transactions SET {} = %s WHERE id = %s').format(sql.Identifier(column)), (foreign, purchase['id']))
    assert client.get('/transactions/' + purchase['id'], headers=alice).json()['category_id'] is None


def test_category_migration_keeps_existing_user_and_purchase_data(client):
    # Exercise upgrading a populated pre-category schema, not only fresh setup.
    schema = 'upgrade_' + uuid4().hex
    url = os.environ['TEST_DATABASE_URL']
    migrations = Path(db.__file__).resolve().parents[1] / 'migrations'
    with psycopg.connect(url) as conn:
        conn.execute(sql.SQL('CREATE SCHEMA {}').format(sql.Identifier(schema)))
    try:
        with psycopg.connect(url, options=f'-csearch_path={schema}', row_factory=dict_row) as conn:
            for name in ('001_accounts_cards.sql', '002_manual_purchases.sql'):
                conn.execute((migrations / name).read_text())
            user_id, card_id, merchant_id, transaction_id = [uuid4() for _ in range(4)]
            conn.execute("INSERT INTO users (id, email, name, password_hash) VALUES (%s, 'upgrade@example.com', 'Upgrade', 'test-hash')", (user_id,))
            conn.execute("INSERT INTO card_profiles (id, user_id, label, network, last4, expiry_month, expiry_year) VALUES (%s, %s, 'Card', 'visa', '4242', 12, 2099)", (card_id, user_id))
            conn.execute("INSERT INTO merchants (id, user_id, name) VALUES (%s, %s, 'Market')", (merchant_id, user_id))
            conn.execute("INSERT INTO spending_transactions (id, user_id, card_id, merchant_id, amount, occurred_at, source, source_reference, kind, status, channel) VALUES (%s, %s, %s, %s, 1250.05, '2026-11-05T10:30:00+05:00', 'manual', 'upgrade', 'purchase', 'approved', 'pos')", (transaction_id, user_id, card_id, merchant_id))
            conn.execute((migrations / '003_categories_history.sql').read_text())
            saved = conn.execute('SELECT id, amount, category_id, recorded_category_id FROM spending_transactions').fetchone()
            assert str(saved['amount']) == '1250.05' and saved['id'] == transaction_id
            assert saved['category_id'] is None and saved['recorded_category_id'] is None
            assert conn.execute('SELECT count(*) AS n FROM categories WHERE user_id = %s', (user_id,)).fetchone()['n'] == 6
            assert conn.execute('SELECT count(*) AS n FROM transaction_audit_events').fetchone()['n'] == 1
    finally:
        with psycopg.connect(url) as conn:
            conn.execute(sql.SQL('DROP SCHEMA {} CASCADE').format(sql.Identifier(schema)))
