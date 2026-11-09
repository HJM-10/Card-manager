from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import os
import sys
from uuid import uuid4

import psycopg
from psycopg import sql
from psycopg.conninfo import conninfo_to_dict, make_conninfo
from psycopg.rows import dict_row
import pytest
from fastapi.testclient import TestClient

from app import db, db_access, main
from app.db_access import grant_runtime_access
from app.notification_worker import run_once
from test_accounts_cards import (
    client, account, purchase_payload, csv_text, CSV_ROW, preview_file, confirm_file,
)
from test_notifications import Sender


@pytest.fixture()
def restricted(client, monkeypatch):
    owner = db.connect
    role, password = 'runtime_' + uuid4().hex, uuid4().hex
    with owner() as conn:
        schema = conn.execute('SELECT current_schema() AS name').fetchone()['name']
        settings = conninfo_to_dict(conn.info.dsn)
        conn.execute(sql.SQL('CREATE ROLE {} LOGIN PASSWORD {}').format(sql.Identifier(role), sql.Literal(password)))
        grant_runtime_access(conn, role, schema)
        grant_runtime_access(conn, role, schema)  # Idempotent grants.
    settings.update(user=role, password=password)

    def runtime():
        return psycopg.connect(**settings, row_factory=dict_row)

    monkeypatch.setattr(main, 'connect', runtime)
    monkeypatch.setattr(db, 'connect', runtime)
    try:
        yield client, runtime, owner, schema, role
    finally:
        with owner() as conn:
            conn.execute(sql.SQL('DROP OWNED BY {}').format(sql.Identifier(role)))
            conn.execute(sql.SQL('DROP ROLE {}').format(sql.Identifier(role)))


def saved_purchase(restricted):
    api, runtime, owner, schema, role = restricted
    headers = account(api)
    payload = purchase_payload(api, headers)
    response = api.post('/transactions', headers=headers, json=payload)
    assert response.status_code == 201, response.text
    return headers, payload, response.json()


@pytest.mark.parametrize('statement', [
    'INSERT INTO transaction_audit_events SELECT * FROM transaction_audit_events',
    'UPDATE transaction_audit_events SET created_at = now()',
    'DELETE FROM transaction_audit_events',
    'TRUNCATE transaction_audit_events',
    'TRUNCATE spending_transactions CASCADE',
    'ALTER TABLE transaction_audit_events DISABLE TRIGGER ALL',
    'ALTER TABLE spending_transactions DISABLE TRIGGER spending_transaction_created',
    'DROP TABLE transaction_audit_events',
    'ALTER FUNCTION record_transaction_created() SECURITY INVOKER',
    'SELECT record_transaction_created()',
    'SET session_replication_role = replica',
    'CREATE TABLE audit_replacement (id int)',
    'DELETE FROM spending_transactions',
    'INSERT INTO transaction_outbox SELECT * FROM transaction_outbox',
    'DELETE FROM schema_migrations',
])
def test_runtime_cannot_tamper(restricted, statement):
    saved_purchase(restricted)
    _, runtime, owner, _, _ = restricted
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        with runtime() as conn:
            conn.execute(statement)
    with owner() as conn:
        assert conn.execute('SELECT count(*) AS n FROM transaction_audit_events').fetchone()['n'] == 1


def test_runtime_workflows_and_concurrent_retry(restricted):
    api, runtime, owner, _, _ = restricted
    headers, payload, saved = saved_purchase(restricted)
    device_id = str(uuid4())
    assert api.put('/devices/' + device_id, headers=headers, json={'token': 'synthetic-device-token-' + uuid4().hex}).status_code == 200
    category = api.get('/categories', headers=headers).json()[0]['id']
    assert api.patch('/transactions/' + saved['id'] + '/category', headers=headers, json={'category_id': category}).status_code == 200
    assert api.put('/budgets/2026-11/' + category, headers=headers, json={'amount': '5000.00'}).status_code == 200
    preview = preview_file(api, headers, payload['card_id'], csv_text([CSV_ROW])).json()
    assert confirm_file(api, headers, preview).status_code == 200
    simulated = api.post('/simulations/purchases', headers=headers, json={**payload, 'source_reference': str(uuid4()), 'status': 'declined'})
    assert simulated.status_code == 201, simulated.text
    refund = api.post('/transactions/' + saved['id'] + '/refunds', headers=headers, json={
        'amount': '250.00', 'occurred_at': '2026-11-06T10:30:00+05:00', 'source_reference': str(uuid4())})
    assert refund.status_code == 201, refund.text
    assert api.get('/reports/monthly?month=2026-11', headers=headers).status_code == 200
    assert api.get('/transactions', headers=headers).status_code == 200
    retry = {**payload, 'source_reference': str(uuid4())}

    def create(_):
        with TestClient(main.app) as request_client:
            return request_client.post('/transactions', headers=headers, json=retry).status_code

    with ThreadPoolExecutor(max_workers=2) as pool:
        assert sorted(pool.map(create, range(2))) == [200, 201]
    with owner() as conn:
        for table in ('spending_transactions', 'transaction_audit_events', 'transaction_outbox'):
            assert conn.execute(sql.SQL('SELECT count(*) AS n FROM {}').format(sql.Identifier(table))).fetchone()['n'] == 5
    sender = Sender()
    for _ in range(8):
        run_once(sender, connection=runtime)
    assert sender.calls
    assert api.get('/notifications', headers=headers).status_code == 200


def test_runtime_outbox_failure_rolls_back_audit_and_purchase(restricted):
    api, runtime, owner, _, _ = restricted
    headers = account(api)
    payload = purchase_payload(api, headers)
    with owner() as conn:
        conn.execute('ALTER TABLE transaction_outbox ADD CONSTRAINT test_failure CHECK (false)')
    with TestClient(main.app, raise_server_exceptions=False) as request_client:
        assert request_client.post('/transactions', headers=headers, json=payload).status_code == 500
    with owner() as conn:
        for table in ('merchants', 'spending_transactions', 'transaction_audit_events', 'transaction_outbox'):
            assert conn.execute(sql.SQL('SELECT count(*) AS n FROM {}').format(sql.Identifier(table))).fetchone()['n'] == 0
        conn.execute('ALTER TABLE transaction_outbox DROP CONSTRAINT test_failure')
    assert api.post('/transactions', headers=headers, json=payload).status_code == 201


def test_trigger_ignores_caller_search_path_and_temp_shadow_tables(restricted):
    _, runtime, owner, schema, _ = restricted
    _, payload, saved = saved_purchase(restricted)
    with runtime() as conn:
        conn.execute('CREATE TEMP TABLE transaction_audit_events (transaction_id uuid)')
        conn.execute('CREATE TEMP TABLE transaction_outbox (transaction_id uuid)')
        conn.execute(sql.SQL('SET LOCAL search_path = pg_temp, {}, pg_catalog').format(sql.Identifier(schema)))
        new_id = uuid4()
        conn.execute('''INSERT INTO spending_transactions
            (id, user_id, card_id, merchant_id, amount, occurred_at, source,
             source_reference, kind, status, channel)
            SELECT %s, user_id, card_id, merchant_id, amount, occurred_at, source,
                   %s, kind, status, channel FROM spending_transactions WHERE id = %s''',
            (new_id, str(uuid4()), saved['id']))
        assert conn.execute('SELECT count(*) AS n FROM pg_temp.transaction_audit_events').fetchone()['n'] == 0
        assert conn.execute('SELECT count(*) AS n FROM pg_temp.transaction_outbox').fetchone()['n'] == 0
    with owner() as conn:
        assert conn.execute('SELECT count(*) AS n FROM transaction_audit_events').fetchone()['n'] == 2
        assert conn.execute('SELECT count(*) AS n FROM transaction_outbox').fetchone()['n'] == 2


def test_provisioning_rejects_owner(restricted):
    _, _, owner, schema, _ = restricted
    with owner() as conn:
        role = conn.execute('SELECT current_user AS name').fetchone()['name']
        with pytest.raises(ValueError):
            grant_runtime_access(conn, role, schema)


def test_runtime_cannot_assume_migration_owner(restricted):
    _, runtime, owner, _, _ = restricted
    with owner() as conn:
        owner_role = conn.execute('SELECT current_user AS name').fetchone()['name']
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        with runtime() as conn:
            conn.execute(sql.SQL('SET ROLE {}').format(sql.Identifier(owner_role)))


def test_provisioning_rejects_inherited_role(restricted):
    _, _, owner, schema, role = restricted
    other = 'inherited_' + uuid4().hex
    with owner() as conn:
        conn.execute(sql.SQL('CREATE ROLE {}').format(sql.Identifier(other)))
        conn.execute(sql.SQL('GRANT {} TO {}').format(sql.Identifier(other), sql.Identifier(role)))
        try:
            with pytest.raises(ValueError, match='inherit or assume'):
                grant_runtime_access(conn, role, schema)
        finally:
            conn.execute(sql.SQL('REVOKE {} FROM {}').format(sql.Identifier(other), sql.Identifier(role)))
            conn.execute(sql.SQL('DROP ROLE {}').format(sql.Identifier(other)))


def test_upgrade_preserves_existing_audit_and_outbox(restricted):
    _, runtime, owner, _, _ = restricted
    saved_purchase(restricted)
    migration = Path(db.__file__).resolve().parents[1] / 'migrations' / '009_audit_protection.sql'
    with owner() as conn:
        before = conn.execute('SELECT * FROM transaction_audit_events').fetchall()
        outbox = conn.execute('SELECT * FROM transaction_outbox').fetchall()
        conn.execute(migration.read_text())
        assert conn.execute('SELECT * FROM transaction_audit_events').fetchall() == before
        assert conn.execute('SELECT * FROM transaction_outbox').fetchall() == outbox
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        with runtime() as conn:
            conn.execute('DELETE FROM transaction_audit_events')


@pytest.mark.parametrize('separate_admin', [False, True])
def test_provisioning_saves_working_credentials_without_printing_them(client, monkeypatch, capsys, separate_admin):
    role = 'provision_' + uuid4().hex
    with db.connect() as conn:
        schema = conn.execute('SELECT current_schema() AS name').fetchone()['name']
    owner_url = make_conninfo(os.environ['TEST_DATABASE_URL'], options=f'-csearch_path={schema}')
    monkeypatch.setenv('MIGRATION_DATABASE_URL', owner_url)
    if separate_admin:
        monkeypatch.setenv('PROVISION_DATABASE_URL', owner_url)
    else:
        monkeypatch.delenv('PROVISION_DATABASE_URL', raising=False)
    monkeypatch.setattr(sys, 'argv', ['db_access', '--configure-local', '--role', role, '--schema', schema])
    stored = {}
    monkeypatch.setattr(db_access, 'set_key', lambda path, key, value: stored.update({key: value}))
    try:
        for _ in range(2):
            db_access.main()
            assert stored['MIGRATION_DATABASE_URL'] == owner_url
            settings = conninfo_to_dict(stored['DATABASE_URL'])
            assert settings['user'] == role
            assert settings['password'] not in capsys.readouterr().out
            with psycopg.connect(stored['DATABASE_URL']) as conn:
                assert conn.execute('SELECT current_user').fetchone()[0] == role
                assert not conn.execute("SELECT has_table_privilege(current_user, 'transaction_audit_events', 'UPDATE')").fetchone()[0]
    finally:
        with db.connect() as conn:
            if conn.execute('SELECT 1 FROM pg_roles WHERE rolname = %s', (role,)).fetchone():
                conn.execute(sql.SQL('DROP OWNED BY {}').format(sql.Identifier(role)))
            conn.execute(sql.SQL('DROP ROLE IF EXISTS {}').format(sql.Identifier(role)))
