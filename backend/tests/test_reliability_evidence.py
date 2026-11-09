"""Database-observed contention and atomicity, using real restricted logins.

Set RELIABILITY_EVIDENCE_DIR to a new folder to preserve case observations.
No notification transport is called; only the local outbox fan-out is exercised.
"""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from decimal import Decimal
import json
import os
from pathlib import Path
import re
from threading import Barrier
import time
from uuid import uuid4

import psycopg
from psycopg import sql
import pytest
from fastapi.testclient import TestClient

from app import main
from app.notifications import expand_outbox
from test_accounts_cards import account, purchase_payload, csv_text, preview_file, confirm_file
from test_audit_protection import client, restricted


TABLES = ('merchants', 'spending_transactions', 'transaction_audit_events',
          'transaction_outbox', 'notification_events', 'import_batches')


@pytest.fixture()
def case(restricted, request):
    api, runtime, owner, schema, role = restricted
    headers = account(api)
    payload = purchase_payload(api, headers)
    device = api.put('/devices/' + str(uuid4()), headers=headers,
                     json={'token': 'synthetic-reliability-token-' + uuid4().hex})
    assert device.status_code == 200, device.text
    started = datetime.now(timezone.utc).isoformat()

    def record(**observations):
        folder = os.environ.get('RELIABILITY_EVIDENCE_DIR')
        if not folder:
            return
        path = Path(folder) / (re.sub(r'[^A-Za-z0-9_-]', '_', request.node.name) + '.json')
        path.parent.mkdir(parents=True, exist_ok=True)
        assert not path.exists(), 'Use a new evidence directory; observations are never overwritten'
        with owner() as conn:
            environment = conn.execute('''SELECT version() AS version,
                current_setting('transaction_isolation') AS observer_isolation''').fetchone()
        with runtime() as conn:
            runtime_info = conn.execute('''SELECT current_user AS role,
                current_setting('transaction_isolation') AS isolation,
                (SELECT rolsuper FROM pg_roles WHERE rolname=current_user) AS superuser''').fetchone()
        assert runtime_info['superuser'] is False
        proof = {'test': request.node.name, 'status': 'passed', 'started_utc': started,
                 'finished_utc': datetime.now(timezone.utc).isoformat(),
                 'schema': schema, 'runtime': runtime_info, 'environment': environment,
                 **observations}
        path.write_text(json.dumps(proof, indent=2, default=str) + '\n', encoding='utf-8')

    return api, runtime, owner, headers, payload, role, schema, record


def state(connection):
    with connection() as conn:
        counts = {name: conn.execute(sql.SQL('SELECT count(*) AS n FROM {}').format(sql.Identifier(name))).fetchone()['n'] for name in TABLES}
        triples = conn.execute('''SELECT t.id, t.source_reference, t.kind, t.status, t.amount,
            (SELECT count(*) FROM transaction_audit_events a WHERE a.transaction_id=t.id) AS audits,
            (SELECT count(*) FROM transaction_outbox o WHERE o.transaction_id=t.id) AS outbox_events,
            (SELECT count(*) FROM notification_events n WHERE n.transaction_id=t.id) AS device_events
            FROM spending_transactions t ORDER BY t.source_reference''').fetchall()
        batches = conn.execute('SELECT id,status,rows,imported_count,duplicate_count,total_amount FROM import_batches ORDER BY id').fetchall()
        spent = conn.execute('SELECT COALESCE(sum(spending_amount),0) AS spent FROM transaction_spending').fetchone()['spent']
    return {'counts': counts, 'transactions': triples, 'imports': batches, 'spent': str(spent)}


def fan_out(runtime):
    with runtime() as conn:
        expanded = expand_outbox(conn)
    with runtime() as conn:
        assert expand_outbox(conn) == 0
    return expanded


def triple_counts(snapshot, count):
    for name in ('spending_transactions', 'transaction_audit_events', 'transaction_outbox', 'notification_events'):
        assert snapshot['counts'][name] == count
    assert all(t['audits'] == t['outbox_events'] == t['device_events'] == 1 for t in snapshot['transactions'])


def post(path, headers, body):
    with TestClient(main.app, raise_server_exceptions=False) as api:
        response = api.post(path, headers=headers, json=body)
        return {'status': response.status_code,
                'body': response.json() if response.headers.get('content-type', '').startswith('application/json') else response.text}


def contended(case, operations, *, original_id=None):
    _, runtime, owner, _, payload, role, _, _ = case
    barrier = Barrier(len(operations) + 1, timeout=15)
    gate = runtime()
    blocked = []
    with owner() as observer:
        observer.autocommit = True
        with ThreadPoolExecutor(max_workers=len(operations)) as pool:
            try:
                if original_id:
                    gate.execute('SELECT id FROM spending_transactions WHERE id=%s FOR UPDATE', (original_id,))
                else:
                    gate.execute('SELECT id FROM card_profiles WHERE id=%s FOR UPDATE', (payload['card_id'],))
                gate_pid = gate.info.backend_pid

                def execute(operation):
                    barrier.wait()
                    return operation()

                futures = [pool.submit(execute, operation) for operation in operations]
                barrier.wait()
                deadline = time.monotonic() + 12
                while time.monotonic() < deadline:
                    observer.execute('SELECT pg_stat_clear_snapshot()')
                    blocked = observer.execute('''SELECT pid, wait_event_type, wait_event,
                        pg_blocking_pids(pid) AS blockers FROM pg_stat_activity
                        WHERE usename=%s AND wait_event_type='Lock'
                          AND cardinality(pg_blocking_pids(pid)) > 0 ORDER BY pid''', (role,)).fetchall()
                    if len(blocked) == len(operations):
                        break
                    time.sleep(.02)
            finally:
                # Release even if an observer/assertion fails; workers cannot be
                # stranded behind the evidence harness's own lock.
                gate.rollback()
                gate.close()
            responses = [future.result(timeout=30) for future in futures]
    assert len(blocked) == len(operations), f'Did not observe all {len(operations)} workers blocked: {blocked}'
    return responses, {'gate_pid': gate_pid, 'workers': len(operations), 'observed_blocked': blocked,
                       'gate': 'original_purchase' if original_id else 'card_profile'}


def purchase(case):
    api, _, _, headers, payload, _, _, _ = case
    saved = api.post('/transactions', headers=headers, json=payload)
    assert saved.status_code == 201, saved.text
    return saved.json()


def refund_body(reference=None):
    return {'amount': '800.00', 'occurred_at': '2026-11-06T10:30:00+05:00',
            'source_reference': reference or str(uuid4())}


@pytest.mark.parametrize('round_number', [1, 2, 3])
def test_eight_simultaneous_matching_purchases_commit_once(case, round_number):
    _, runtime, _, headers, payload, _, _, record = case
    responses, locks = contended(case, [lambda: post('/transactions', headers, payload)] * 8)
    assert sorted(r['status'] for r in responses) == [200] * 7 + [201]
    assert len({r['body']['id'] for r in responses}) == 1
    assert all(r['body'] == responses[0]['body'] for r in responses)
    assert fan_out(runtime) == 1
    final = state(runtime)
    triple_counts(final, 1)
    record(round=round_number, responses=responses, lock_observation=locks, committed=final)


@pytest.mark.parametrize('round_number', [1, 2, 3])
def test_conflicting_simultaneous_payloads_commit_one_winner(case, round_number):
    _, runtime, _, headers, payload, _, _, record = case
    bodies = [payload, {**payload, 'amount': '1251.05'}]
    responses, locks = contended(case, [lambda body=body: post('/transactions', headers, body) for body in bodies])
    assert sorted(r['status'] for r in responses) == [201, 409]
    winner = next(r['body'] for r in responses if r['status'] == 201)
    assert fan_out(runtime) == 1
    final = state(runtime)
    triple_counts(final, 1)
    assert final['transactions'][0]['amount'] == Decimal(winner['amount'])
    record(round=round_number, submitted_amounts=[b['amount'] for b in bodies],
           responses=responses, lock_observation=locks, committed=final)


@pytest.mark.parametrize('round_number', [1, 2, 3])
def test_competing_api_refunds_cannot_exceed_purchase(case, round_number):
    _, runtime, _, headers, _, _, _, record = case
    original = purchase(case)
    path = '/transactions/' + original['id'] + '/refunds'
    bodies = [refund_body(), refund_body()]
    responses, locks = contended(case, [lambda body=body: post(path, headers, body) for body in bodies])
    assert sorted(r['status'] for r in responses) == [201, 409]
    assert fan_out(runtime) == 2
    final = state(runtime)
    triple_counts(final, 2)
    assert Decimal(final['spent']) == Decimal('450.05')
    record(round=round_number, original_amount=original['amount'], requested_refunds=['800.00', '800.00'],
           responses=responses, lock_observation=locks, committed=final)


def direct_insert(runtime, original, reference, *, refund=False):
    try:
        with runtime() as conn:
            transaction_id = uuid4()
            conn.execute('''INSERT INTO spending_transactions
                (id,user_id,card_id,merchant_id,amount,occurred_at,source,source_reference,
                 kind,status,channel,original_purchase_id)
                SELECT %s,user_id,card_id,merchant_id,%s,%s,%s,%s,%s,'approved',channel,%s
                FROM spending_transactions WHERE id=%s''',
                (transaction_id, '800.00' if refund else '1250.05', '2026-11-06T05:30:00Z',
                 'simulation' if refund else 'manual', reference, 'refund' if refund else 'purchase',
                 original['id'] if refund else None, original['id']))
        return {'outcome': 'committed', 'id': str(transaction_id)}
    except (psycopg.errors.UniqueViolation, psycopg.errors.CheckViolation) as error:
        return {'outcome': 'rejected', 'sqlstate': error.sqlstate,
                'constraint': error.diag.constraint_name, 'message': error.diag.message_primary}


@pytest.mark.parametrize('round_number', [1, 2, 3])
def test_direct_sql_duplicate_constraint_commits_once(case, round_number):
    _, runtime, _, _, _, _, _, record = case
    original = purchase(case)
    reference = str(uuid4())
    responses, locks = contended(case, [lambda: direct_insert(runtime, original, reference)] * 4)
    assert [r['outcome'] for r in responses].count('committed') == 1
    assert [r.get('sqlstate') for r in responses].count('23505') == 3
    assert fan_out(runtime) == 2
    final = state(runtime)
    triple_counts(final, 2)  # Fixture original plus one new direct purchase.
    record(round=round_number, responses=responses, lock_observation=locks, committed=final)


@pytest.mark.parametrize('round_number', [1, 2, 3])
def test_direct_sql_competing_refunds_obey_database_trigger(case, round_number):
    _, runtime, _, _, _, _, _, record = case
    original = purchase(case)
    responses, locks = contended(case,
        [lambda: direct_insert(runtime, original, str(uuid4()), refund=True)] * 2, original_id=original['id'])
    assert sorted(r['outcome'] for r in responses) == ['committed', 'rejected']
    assert next(r for r in responses if r['outcome'] == 'rejected')['sqlstate'] == '23514'
    assert fan_out(runtime) == 2
    final = state(runtime)
    triple_counts(final, 2)
    assert Decimal(final['spent']) == Decimal('450.05')
    record(round=round_number, original_amount=original['amount'], requested_refunds=['800.00', '800.00'],
           responses=responses, lock_observation=locks, committed=final)


def test_matching_refund_retries_create_one_refund_event(case):
    _, runtime, _, headers, _, _, _, record = case
    original = purchase(case)
    body = refund_body()
    path = '/transactions/' + original['id'] + '/refunds'
    responses, locks = contended(case, [lambda: post(path, headers, body)] * 4)
    assert sorted(r['status'] for r in responses) == [200] * 3 + [201]
    assert len({r['body']['id'] for r in responses}) == 1
    assert fan_out(runtime) == 2
    final = state(runtime)
    triple_counts(final, 2)
    assert Decimal(final['spent']) == Decimal('450.05')
    record(responses=responses, lock_observation=locks, committed=final)


def inject_fault(case, table, merchant=None):
    _, runtime, owner, _, _, _, schema, _ = case
    notices = []
    with owner() as conn:
        conn.execute(sql.SQL('''CREATE FUNCTION {schema}.reliability_fault() RETURNS trigger
            LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $body$
            DECLARE batch_id uuid;
            BEGIN
                IF {merchant} IS NOT NULL AND NOT EXISTS (
                    SELECT 1 FROM {schema}.spending_transactions t
                    JOIN {schema}.merchants m ON m.id=t.merchant_id
                    WHERE t.id=NEW.transaction_id AND m.name={merchant}) THEN
                    RETURN NEW;
                END IF;
                SELECT import_batch_id INTO batch_id FROM {schema}.spending_transactions
                    WHERE id=NEW.transaction_id;
                RAISE NOTICE 'reliability_evidence:%', json_build_object(
                    'transaction_visible', EXISTS(SELECT 1 FROM {schema}.spending_transactions WHERE id=NEW.transaction_id),
                    'audit_visible', EXISTS(SELECT 1 FROM {schema}.transaction_audit_events WHERE transaction_id=NEW.transaction_id),
                    'batch_transactions', (SELECT count(*) FROM {schema}.spending_transactions WHERE import_batch_id=batch_id),
                    'batch_audits', (SELECT count(*) FROM {schema}.transaction_audit_events a JOIN {schema}.spending_transactions t ON t.id=a.transaction_id WHERE t.import_batch_id=batch_id),
                    'batch_outbox', (SELECT count(*) FROM {schema}.transaction_outbox o JOIN {schema}.spending_transactions t ON t.id=o.transaction_id WHERE t.import_batch_id=batch_id));
                RAISE EXCEPTION 'Injected reliability failure' USING ERRCODE='23514';
            END; $body$''').format(schema=sql.Identifier(schema), merchant=sql.Literal(merchant)))
        conn.execute(sql.SQL('CREATE TRIGGER reliability_fault BEFORE INSERT ON {} FOR EACH ROW EXECUTE FUNCTION reliability_fault()').format(sql.Identifier(table)))

    def capture_notice(diagnostic):
        prefix = 'reliability_evidence:'
        if diagnostic.message_primary.startswith(prefix):
            notices.append(json.loads(diagnostic.message_primary[len(prefix):]))

    original_connect = main.connect

    def observed_connect():
        conn = runtime()
        conn.add_notice_handler(capture_notice)
        return conn

    main.connect = observed_connect

    def remove():
        main.connect = original_connect
        with owner() as conn:
            conn.execute(sql.SQL('DROP TRIGGER reliability_fault ON {}').format(sql.Identifier(table)))
            conn.execute('DROP FUNCTION reliability_fault()')

    return notices, remove


@pytest.mark.parametrize('table', ['transaction_audit_events', 'transaction_outbox'])
def test_failed_purchase_rolls_back_every_write_then_retries(case, table):
    _, runtime, _, headers, payload, _, _, record = case
    body = {**payload, 'merchant': 'Rollback purchase merchant'}
    before = state(runtime)
    notices, remove = inject_fault(case, table)
    try:
        failed = post('/transactions', headers, body)
        after_failure = state(runtime)
        assert failed['status'] == 500
        assert after_failure == before
        assert len(notices) == 1 and notices[0]['transaction_visible'] is True
        assert notices[0]['audit_visible'] == (table == 'transaction_outbox')
    finally:
        remove()
    saved = post('/transactions', headers, body)
    retry = post('/transactions', headers, body)
    assert [saved['status'], retry['status']] == [201, 200]
    assert saved['body'] == retry['body']
    assert fan_out(runtime) == 1
    final = state(runtime)
    triple_counts(final, 1)
    record(fault_table=table, before=before, failed_response=failed, transient_notices=notices,
           after_failure=after_failure, recovery_statuses=[201, 200], committed=final)


def test_csv_second_row_failure_rolls_back_first_row_and_batch(case):
    api, runtime, _, headers, payload, _, _, record = case
    rows = [[f'reliability-{i}', f'Rollback CSV {i}', '100.00', '2026-11-06T10:30:00+05:00', 'pos', ''] for i in (1, 2)]
    preview = preview_file(api, headers, payload['card_id'], csv_text(rows)).json()
    assert preview['ready_count'] == 2
    before = state(runtime)
    notices, remove = inject_fault(case, 'transaction_outbox', 'Rollback CSV 2')
    try:
        failed = post('/imports/' + preview['id'] + '/confirm', headers, {'preview_token': preview['preview_token']})
        after_failure = state(runtime)
        assert failed['status'] == 500 and after_failure == before
        assert notices == [{'transaction_visible': True, 'audit_visible': True,
                            'batch_transactions': 2, 'batch_audits': 2, 'batch_outbox': 1}]
        assert after_failure['imports'][0]['status'] == 'preview'
    finally:
        remove()
    saved = confirm_file(api, headers, preview)
    retry = confirm_file(api, headers, preview)
    assert saved.status_code == retry.status_code == 200
    assert saved.json() == retry.json() and saved.json()['imported_count'] == 2
    assert fan_out(runtime) == 2
    final = state(runtime)
    triple_counts(final, 2)
    assert final['imports'][0]['status'] == 'confirmed'
    assert Decimal(final['spent']) == Decimal('200.00')
    record(before=before, failed_response=failed, transient_notices=notices,
           after_failure=after_failure, recovery_receipt=saved.json(), committed=final)


def test_failed_refund_preserves_purchase_and_refund_capacity(case):
    _, runtime, _, headers, _, _, _, record = case
    original = purchase(case)
    fan_out(runtime)
    before = state(runtime)
    body = refund_body()
    path = '/transactions/' + original['id'] + '/refunds'
    notices, remove = inject_fault(case, 'transaction_outbox')
    try:
        failed = post(path, headers, body)
        after_failure = state(runtime)
        assert failed['status'] == 500 and after_failure == before
        assert notices[0]['transaction_visible'] and notices[0]['audit_visible']
    finally:
        remove()
    saved = post(path, headers, body)
    assert saved['status'] == 201
    assert fan_out(runtime) == 1
    final = state(runtime)
    triple_counts(final, 2)
    assert Decimal(final['spent']) == Decimal('450.05')
    record(before=before, failed_response=failed, transient_notices=notices,
           after_failure=after_failure, recovery_status=201, committed=final)


@pytest.mark.parametrize('mode', ['rollback', 'disconnect'])
def test_uncommitted_transaction_is_invisible_and_is_discarded(case, mode):
    _, runtime, _, _, _, _, _, record = case
    original = purchase(case)
    fan_out(runtime)
    before = state(runtime)
    transaction_id = uuid4()
    conn = runtime()
    try:
        conn.execute('''INSERT INTO spending_transactions
            (id,user_id,card_id,merchant_id,amount,occurred_at,source,source_reference,kind,status,channel)
            SELECT %s,user_id,card_id,merchant_id,amount,occurred_at,source,%s,kind,status,channel
            FROM spending_transactions WHERE id=%s''', (transaction_id, str(uuid4()), original['id']))
        inside = {table: conn.execute(sql.SQL('SELECT count(*) AS n FROM {} WHERE {}=%s').format(
            sql.Identifier(table), sql.Identifier('id' if table == 'spending_transactions' else 'transaction_id')),
            (transaction_id,)).fetchone()['n'] for table in ('spending_transactions', 'transaction_audit_events', 'transaction_outbox')}
        assert all(n == 1 for n in inside.values())
        outside = state(runtime)
        assert outside == before
        assert fan_out(runtime) == 0
        if mode == 'rollback':
            conn.rollback()
    finally:
        conn.close()  # Closing an uncommitted connection must discard its work.
    after = state(runtime)
    assert after == before
    record(mode=mode, before=before, inside_uncommitted_counts=inside,
           other_connection_before_end=outside, after_discard=after)


def test_commit_exposes_transaction_audit_and_outbox_together(case):
    _, runtime, _, _, _, _, _, record = case
    original = purchase(case)
    fan_out(runtime)
    before = state(runtime)
    conn = runtime()
    try:
        transaction_id = uuid4()
        conn.execute('''INSERT INTO spending_transactions
            (id,user_id,card_id,merchant_id,amount,occurred_at,source,source_reference,kind,status,channel)
            SELECT %s,user_id,card_id,merchant_id,amount,occurred_at,source,%s,kind,status,channel
            FROM spending_transactions WHERE id=%s''', (transaction_id, str(uuid4()), original['id']))
        assert state(runtime) == before
        assert fan_out(runtime) == 0
        conn.commit()
    finally:
        conn.close()
    after_commit = state(runtime)
    for table in ('spending_transactions', 'transaction_audit_events', 'transaction_outbox'):
        assert after_commit['counts'][table] == before['counts'][table] + 1
    assert after_commit['counts']['notification_events'] == before['counts']['notification_events']
    assert fan_out(runtime) == 1
    final = state(runtime)
    triple_counts(final, 2)
    record(before=before, after_commit_before_fanout=after_commit, after_fanout=final)
