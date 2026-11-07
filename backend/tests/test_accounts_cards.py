import os
import csv
import io
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


def test_biometric_login_after_access_expiry_and_absolute_expiration(client):
    headers = account(client)
    enrolled = client.post('/auth/biometric', headers=headers)
    assert enrolled.status_code == 201 and enrolled.headers['cache-control'] == 'no-store'
    credential = enrolled.json()['refresh_token']
    with db.connect() as conn:
        saved = conn.execute('SELECT token_hash, expires_at > now() AS valid, expires_at <= now() + interval \'30 days\' AS bounded FROM biometric_sessions').fetchone()
        assert saved['token_hash'] == main.digest(credential) and saved['token_hash'] != credential
        assert saved['valid'] and saved['bounded']
        conn.execute("UPDATE sessions SET expires_at = now() - interval '1 second'")
    assert client.get('/auth/me', headers=headers).status_code == 401
    assert client.get('/auth/me', headers={'Authorization': 'Bearer ' + credential}).status_code == 401
    with TestClient(main.app) as restarted:
        resumed = restarted.post('/auth/biometric/refresh', json={'refresh_token': credential})
        assert resumed.status_code == 200 and resumed.headers['cache-control'] == 'no-store'
        fresh = {'Authorization': 'Bearer ' + resumed.json()['access_token']}
        assert restarted.get('/auth/me', headers=fresh).json()['email'] == 'alice@example.com'
        assert restarted.delete('/auth/access', headers=fresh).status_code == 204
        assert restarted.get('/auth/me', headers=fresh).status_code == 401
        resumed = restarted.post('/auth/biometric/refresh', json={'refresh_token': credential})
        assert resumed.status_code == 200
        fresh = {'Authorization': 'Bearer ' + resumed.json()['access_token']}
        with db.connect() as conn:
            conn.execute("UPDATE biometric_sessions SET expires_at = now() - interval '1 second'")
        assert restarted.get('/auth/me', headers=fresh).status_code == 401
        assert restarted.post('/auth/biometric/refresh', json={'refresh_token': credential}).status_code == 401


def test_disabling_and_replacing_biometric_login_revokes_family(client):
    headers = account(client)
    first = client.post('/auth/biometric', headers=headers).json()['refresh_token']
    sibling = client.post('/auth/biometric/refresh', json={'refresh_token': first}).json()['access_token']
    assert client.delete('/auth/biometric', headers=headers).status_code == 204
    assert client.get('/auth/me', headers=headers).status_code == 200
    assert client.get('/auth/me', headers={'Authorization': 'Bearer ' + sibling}).status_code == 401
    assert client.post('/auth/biometric/refresh', json={'refresh_token': first}).status_code == 401
    second = client.post('/auth/biometric', headers=headers).json()['refresh_token']
    third = client.post('/auth/biometric', headers=headers).json()['refresh_token']
    assert client.post('/auth/biometric/refresh', json={'refresh_token': second}).status_code == 401
    assert client.post('/auth/biometric/refresh', json={'refresh_token': third}).status_code == 200
    assert client.delete('/auth/session', headers=headers).status_code == 204
    assert client.post('/auth/biometric/refresh', json={'refresh_token': third}).status_code == 401
    assert client.get('/auth/me', headers=headers).status_code == 401


def test_biometric_credentials_validation_and_user_isolation(client):
    alice, bob = account(client), account(client, 'bob@example.com')
    assert client.post('/auth/biometric').status_code == 401
    assert client.delete('/auth/biometric').status_code == 401
    for invalid in [{}, {'refresh_token': 'short'}, {'refresh_token': 'x' * 129}, {'refresh_token': 'x' * 48, 'user_id': str(uuid4())}]:
        assert client.post('/auth/biometric/refresh', json=invalid).status_code == 422
    assert client.post('/auth/biometric/refresh', json={'refresh_token': 'x' * 48}).status_code == 401
    credential = client.post('/auth/biometric', headers=alice).json()['refresh_token']
    assert client.delete('/auth/session', headers=bob).status_code == 204
    result = client.post('/auth/biometric/refresh', json={'refresh_token': credential})
    assert result.status_code == 200 and result.json()['user']['email'] == 'alice@example.com'


def test_concurrent_biometric_refresh_and_logout_cannot_restore_revoked_session(client):
    headers = account(client)
    credential = client.post('/auth/biometric', headers=headers).json()['refresh_token']
    def operation(action):
        with TestClient(main.app) as api:
            if action == 'refresh':
                return api.post('/auth/biometric/refresh', json={'refresh_token': credential})
            return api.delete('/auth/session', headers=headers)
    with ThreadPoolExecutor(max_workers=2) as executor:
        refreshed, logged_out = executor.map(operation, ['refresh', 'logout'])
    assert refreshed.status_code in (200, 401)
    assert logged_out.status_code == 204
    assert client.post('/auth/biometric/refresh', json={'refresh_token': credential}).status_code == 401
    if refreshed.status_code == 200:
        assert client.get('/auth/me', headers={'Authorization': 'Bearer ' + refreshed.json()['access_token']}).status_code == 401


def test_concurrent_biometric_replacement_and_logout_cannot_restore_revoked_session(client):
    headers = account(client)
    client.post('/auth/biometric', headers=headers).raise_for_status()
    def operation(action):
        with TestClient(main.app) as api:
            if action == 'enable':
                return api.post('/auth/biometric', headers=headers)
            return api.delete('/auth/session', headers=headers)
    with ThreadPoolExecutor(max_workers=2) as executor:
        enrolled, logged_out = executor.map(operation, ['enable', 'logout'])
    assert enrolled.status_code in (201, 401)
    assert logged_out.status_code == 204
    if enrolled.status_code == 201:
        assert client.post('/auth/biometric/refresh', json={'refresh_token': enrolled.json()['refresh_token']}).status_code == 401
    assert client.get('/auth/me', headers=headers).status_code == 401


def csv_text(rows, category=True):
    output = io.StringIO(newline='')
    writer = csv.writer(output)
    writer.writerow(['reference', 'merchant', 'amount', 'occurred_at', 'channel'] + (['category'] if category else []))
    writer.writerows(rows)
    return output.getvalue()


def import_setup(client):
    headers = account(client)
    card_id = client.post('/cards', headers=headers, json=CARD).json()['id']
    return headers, card_id


def preview_file(client, headers, card_id, text, name='purchases.csv'):
    return client.post('/imports/preview', headers=headers, json={'card_id': card_id, 'file_name': name, 'csv_text': text})


def confirm_file(client, headers, preview):
    return client.post('/imports/' + preview['id'] + '/confirm', headers=headers, json={'preview_token': preview['preview_token']})


CSV_ROW = ['receipt-1', 'Bookshop', '1599.00', '2026-11-07T14:30:00+05:00', 'pos', 'Shopping']


def test_csv_preview_confirmation_receipt_and_repeat_import(client):
    headers, card_id = import_setup(client)
    text = csv_text([CSV_ROW, ['receipt-2', 'Pharmacy', '850.50', '2026-11-07T13:15:00+05:00', 'pos', 'Other']])
    result = preview_file(client, headers, card_id, text)
    assert result.status_code == 200, result.text
    preview = result.json()
    assert preview['ready_count'] == 2 and preview['error_count'] == 0 and preview['total_amount'] == '2449.50'
    assert client.get('/transactions', headers=headers).json() == []
    with db.connect() as conn:
        assert conn.execute('SELECT count(*) AS n FROM transaction_outbox').fetchone()['n'] == 0
    confirmed = confirm_file(client, headers, preview)
    assert confirmed.status_code == 200, confirmed.text
    receipt = confirmed.json()
    assert receipt['status'] == 'confirmed' and receipt['imported_count'] == 2 and receipt['total_amount'] == '2449.50'
    assert confirm_file(client, headers, preview).json() == receipt
    assert preview_file(client, headers, card_id, '\ufeff' + text.replace('\r\n', '\n'), name='renamed.csv').json() == receipt
    assert client.get('/imports/' + preview['id'], headers=headers).json() == receipt
    login = client.post('/auth/login', json={'email': 'alice@example.com', 'password': PASSWORD})
    fresh = {'Authorization': 'Bearer ' + login.json()['access_token']}
    history = client.get('/transactions', headers=fresh).json()
    assert len(history) == 2 and history[0]['source'] == 'csv' and history[0]['category'] == 'Shopping'
    with db.connect() as conn:
        for table in ('spending_transactions', 'transaction_audit_events', 'transaction_outbox'):
            assert conn.execute(sql.SQL('SELECT count(*) AS n FROM {}').format(sql.Identifier(table))).fetchone()['n'] == 2


def test_csv_duplicates_inside_file_reordered_files_and_recategorization(client):
    headers, card_id = import_setup(client)
    first = preview_file(client, headers, card_id, csv_text([CSV_ROW, CSV_ROW])).json()
    assert first['ready_count'] == 1 and first['duplicate_count'] == 1
    receipt = confirm_file(client, headers, first).json()
    assert receipt['imported_count'] == 1 and receipt['duplicate_count'] == 1
    saved = client.get('/transactions', headers=headers).json()[0]
    assert client.patch('/transactions/' + saved['id'] + '/category', headers=headers, json={'category_id': None}).status_code == 200
    other = ['receipt-2', 'Coffee', '550.00', '2026-11-06T09:00:00+05:00', 'online', 'Food']
    preview = preview_file(client, headers, card_id, csv_text([other, CSV_ROW]), name='different.csv').json()
    assert preview['ready_count'] == 1 and preview['duplicate_count'] == 1 and preview['error_count'] == 0
    assert confirm_file(client, headers, preview).json()['imported_count'] == 1
    assert len(client.get('/transactions', headers=headers).json()) == 2


def test_csv_row_errors_and_reference_conflicts_block_entire_batch(client):
    headers, card_id = import_setup(client)
    bad = ['receipt-2', '', '0.00', '2026-11-07T10:00:00', 'cash', 'Missing category']
    preview = preview_file(client, headers, card_id, csv_text([CSV_ROW, bad])).json()
    assert preview['ready_count'] == 1 and preview['error_count'] == 1 and not preview['can_confirm']
    assert confirm_file(client, headers, preview).status_code == 422
    assert client.get('/transactions', headers=headers).json() == []
    conflicting = [*CSV_ROW]
    conflicting[2] = '1600.00'
    preview = preview_file(client, headers, card_id, csv_text([CSV_ROW, conflicting])).json()
    assert preview['error_count'] == 1 and not preview['can_confirm']
    first = preview_file(client, headers, card_id, csv_text([CSV_ROW])).json()
    assert confirm_file(client, headers, first).status_code == 200
    preview = preview_file(client, headers, card_id, csv_text([conflicting])).json()
    assert preview['error_count'] == 1 and confirm_file(client, headers, preview).status_code == 422
    assert len(client.get('/transactions', headers=headers).json()) == 1


def test_csv_formats_limits_utf8_quoting_and_headers(client):
    headers, card_id = import_setup(client)
    row = [*CSV_ROW]
    row[1] = 'Café, Books & More'
    row[5] = 'shopping'
    preview = preview_file(client, headers, card_id, '\ufeff' + csv_text([row])).json()
    assert preview['ready_count'] == 1 and preview['rows'][0]['merchant'] == 'Café, Books & More'
    assert preview_file(client, headers, card_id, csv_text([CSV_ROW[:5]], category=False)).json()['rows'][0]['category_id'] is None
    for text in [
        '', 'reference,reference\n1,2', 'merchant,amount\nShop,10.00',
        csv_text([CSV_ROW]).replace('channel,category', 'channel,cvv'),
        'reference,merchant,amount,occurred_at,channel\n1,"unclosed',
        csv_text([CSV_ROW] * 501), csv_text([CSV_ROW]).replace('Bookshop', 'Book\x00shop'),
    ]:
        assert preview_file(client, headers, card_id, text).status_code == 422
    assert preview_file(client, headers, card_id, 'é' * 150000).status_code == 413
    assert preview_file(client, headers, card_id, csv_text([CSV_ROW]), name='purchases.txt').status_code == 422
    assert preview_file(client, headers, card_id, csv_text([CSV_ROW]), name='../purchases.csv').status_code == 422


def test_csv_ownership_archival_stale_preview_and_confirmation_recheck(client):
    alice, card_id = import_setup(client)
    bob = account(client, 'bob@example.com')
    text = csv_text([CSV_ROW])
    assert preview_file(client, bob, card_id, text).status_code == 404
    assert client.post('/imports/preview', json={'card_id': card_id, 'file_name': 'p.csv', 'csv_text': text}).status_code == 401
    preview = preview_file(client, alice, card_id, text).json()
    assert client.get('/imports/' + preview['id'], headers=bob).status_code == 404
    assert confirm_file(client, bob, preview).status_code == 404
    latest = preview_file(client, alice, card_id, text).json()
    assert latest['id'] == preview['id'] and latest['preview_token'] != preview['preview_token']
    assert confirm_file(client, alice, preview).status_code == 409
    assert client.delete('/cards/' + card_id, headers=alice).status_code == 204
    assert confirm_file(client, alice, latest).status_code == 404
    assert client.get('/transactions', headers=alice).json() == []


def test_csv_concurrent_batches_commit_one_purchase_event_and_recheck_conflicts(client):
    headers, card_id = import_setup(client)
    first = preview_file(client, headers, card_id, csv_text([CSV_ROW])).json()
    second = preview_file(client, headers, card_id, csv_text([CSV_ROW]).replace('Shopping', 'shopping')).json()
    def confirm(preview):
        with TestClient(main.app) as api:
            response = confirm_file(api, headers, preview)
            assert response.status_code == 200, response.text
            return response.json()
    with ThreadPoolExecutor(max_workers=2) as executor:
        receipts = list(executor.map(confirm, [first, second]))
    assert sorted(r['imported_count'] for r in receipts) == [0, 1]
    with db.connect() as conn:
        for table in ('spending_transactions', 'transaction_audit_events', 'transaction_outbox'):
            assert conn.execute(sql.SQL('SELECT count(*) AS n FROM {}').format(sql.Identifier(table))).fetchone()['n'] == 1
    # A reference can change after preview due to a separately committed import.
    other = ['new-receipt', 'Market', '100.00', '2026-11-07T10:00:00+05:00', 'pos', 'Groceries']
    original = ['future-ref', 'Cafe', '500.00', '2026-11-07T11:00:00+05:00', 'pos', 'Food']
    waiting = preview_file(client, headers, card_id, csv_text([other, original])).json()
    changed = [*original]
    changed[2] = '501.00'
    intervening = preview_file(client, headers, card_id, csv_text([changed])).json()
    assert confirm_file(client, headers, intervening).status_code == 200
    assert confirm_file(client, headers, waiting).status_code == 409
    assert len(client.get('/transactions', headers=headers).json()) == 2


def test_csv_failure_rolls_back_all_rows_audit_outbox_and_batch(client):
    headers, card_id = import_setup(client)
    second = [*CSV_ROW]
    second[0], second[1] = 'receipt-2', 'Pharmacy'
    preview = preview_file(client, headers, card_id, csv_text([CSV_ROW, second])).json()
    with db.connect() as conn:
        conn.execute('''CREATE FUNCTION fail_second_import_event() RETURNS trigger LANGUAGE plpgsql AS $$
            BEGIN IF (SELECT count(*) FROM transaction_outbox) >= 1 THEN RAISE EXCEPTION 'simulated event failure'; END IF; RETURN NEW; END; $$''')
        conn.execute('CREATE TRIGGER fail_import_event BEFORE INSERT ON transaction_outbox FOR EACH ROW EXECUTE FUNCTION fail_second_import_event()')
    with TestClient(main.app, raise_server_exceptions=False) as api:
        assert confirm_file(api, headers, preview).status_code == 500
    with db.connect() as conn:
        for table in ('merchants', 'spending_transactions', 'transaction_audit_events', 'transaction_outbox'):
            assert conn.execute(sql.SQL('SELECT count(*) AS n FROM {}').format(sql.Identifier(table))).fetchone()['n'] == 0
        assert conn.execute('SELECT status FROM import_batches WHERE id = %s', (preview['id'],)).fetchone()['status'] == 'preview'
        conn.execute('DROP TRIGGER fail_import_event ON transaction_outbox')
    assert confirm_file(client, headers, preview).json()['imported_count'] == 2


def test_csv_database_batch_ownership_is_enforced(client):
    alice, card_id = import_setup(client)
    preview = preview_file(client, alice, card_id, csv_text([CSV_ROW])).json()
    assert confirm_file(client, alice, preview).status_code == 200
    bob = account(client, 'bob@example.com')
    bob_card = client.post('/cards', headers=bob, json=CARD).json()['id']
    foreign_batch = preview_file(client, bob, bob_card, csv_text([CSV_ROW])).json()
    with pytest.raises(psycopg.errors.ForeignKeyViolation):
        with db.connect() as conn:
            conn.execute('UPDATE spending_transactions SET import_batch_id = %s', (foreign_batch['id'],))
    assert len(client.get('/transactions', headers=alice).json()) == 1


def test_csv_maximum_500_rows_import_exactly_once(client):
    headers, card_id = import_setup(client)
    rows = [[f'receipt-{i}', 'Market', '1.00', '2026-11-07T10:00:00+05:00', 'pos', 'Groceries'] for i in range(500)]
    preview = preview_file(client, headers, card_id, csv_text(rows)).json()
    assert preview['ready_count'] == 500 and preview['total_amount'] == '500.00'
    receipt = confirm_file(client, headers, preview)
    assert receipt.status_code == 200, receipt.text
    assert receipt.json()['imported_count'] == 500 and receipt.json()['total_amount'] == '500.00'
    assert confirm_file(client, headers, preview).json() == receipt.json()
