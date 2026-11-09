"""Back up SpendTrail and restore only into a newly generated database.

Required: DATABASE_URL (runtime), MIGRATION_DATABASE_URL (source owner),
REHEARSAL_ADMIN_DATABASE_URL (same cluster, CREATEDB and restore privileges).
Archives/private logs stay under ignored backend/.local by default.
"""
import argparse
from datetime import datetime, timezone
from decimal import Decimal
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import time
from uuid import uuid4

import psycopg
from psycopg import sql
from psycopg.conninfo import conninfo_to_dict, make_conninfo
from psycopg.rows import dict_row
from fastapi.testclient import TestClient

from app import db, main
from app.purchases import PurchaseInput, save_purchase


def dump_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, default=str) + '\n', encoding='utf-8')


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, default=str, separators=(',', ':')).encode()).hexdigest()


def connection(url):
    return psycopg.connect(url, row_factory=dict_row, connect_timeout=10,
                           options='-c timezone=UTC -c search_path=public')


def relation_fingerprint(conn, name):
    digest, count = hashlib.sha256(), 0
    query = sql.SQL('SELECT to_jsonb(t)::text AS row FROM public.{} AS t ORDER BY (to_jsonb(t)::text) COLLATE "C"').format(sql.Identifier(name))
    for row in conn.execute(query):
        digest.update(row['row'].encode('utf-8') + b'\n')
        count += 1
    return {'rows': count, 'sha256': digest.hexdigest()}


def snapshot(conn):
    tables = conn.execute("SELECT tablename AS name FROM pg_tables WHERE schemaname='public' ORDER BY tablename").fetchall()
    views = conn.execute("SELECT viewname AS name FROM pg_views WHERE schemaname='public' ORDER BY viewname").fetchall()
    catalog_queries = {
        'columns': '''SELECT table_name,column_name,ordinal_position,data_type,udt_name,
            is_nullable,column_default,numeric_precision,numeric_scale FROM information_schema.columns
            WHERE table_schema='public' ORDER BY table_name,ordinal_position''',
        'constraints': '''SELECT c.relname,k.conname,k.contype,k.convalidated,
            pg_get_constraintdef(k.oid) AS definition FROM pg_constraint k JOIN pg_class c ON c.oid=k.conrelid
            JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' ORDER BY c.relname,k.conname''',
        'indexes': "SELECT tablename,indexname,indexdef FROM pg_indexes WHERE schemaname='public' ORDER BY tablename,indexname",
        'triggers': '''SELECT c.relname,t.tgname,t.tgenabled,pg_get_triggerdef(t.oid) AS definition
            FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='public' AND NOT t.tgisinternal ORDER BY c.relname,t.tgname''',
        'functions': '''SELECT p.proname,p.prosecdef,p.proconfig,pg_get_userbyid(p.proowner) AS owner,
            pg_get_functiondef(p.oid) AS definition FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='public' AND p.prokind='f' ORDER BY p.proname,p.oid::regprocedure::text''',
        'relation_owners': '''SELECT c.relname,c.relkind,pg_get_userbyid(c.relowner) AS owner
            FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='public' AND c.relkind IN ('r','v','S') ORDER BY c.relname''',
        'relation_acl': '''SELECT c.relname,pg_get_userbyid(a.grantor) AS grantor,
            CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END AS grantee,
            a.privilege_type,a.is_grantable FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl,acldefault(CASE WHEN c.relkind='S' THEN 'S'::"char" ELSE 'r'::"char" END,c.relowner))) a
            WHERE n.nspname='public' AND c.relkind IN ('r','v','S')
            ORDER BY c.relname,grantor,grantee,a.privilege_type,a.is_grantable''',
        'function_acl': '''SELECT p.proname,pg_get_userbyid(a.grantor) AS grantor,
            CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END AS grantee,
            a.privilege_type,a.is_grantable FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a
            WHERE n.nspname='public' ORDER BY p.proname,grantor,grantee,a.privilege_type,a.is_grantable''',
        'schema_acl': '''SELECT pg_get_userbyid(n.nspowner) AS owner,pg_get_userbyid(a.grantor) AS grantor,
            CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END AS grantee,
            a.privilege_type,a.is_grantable FROM pg_namespace n
            CROSS JOIN LATERAL aclexplode(COALESCE(n.nspacl,acldefault('n',n.nspowner))) a
            WHERE n.nspname='public' ORDER BY owner,grantor,grantee,a.privilege_type,a.is_grantable''',
        'view_definitions': "SELECT viewname,definition FROM pg_views WHERE schemaname='public' ORDER BY viewname",
    }
    catalog = {key: conn.execute(query).fetchall() for key, query in catalog_queries.items()}
    totals = conn.execute('''SELECT count(*) AS transactions,
        COALESCE(sum(spending_amount),0) AS spent,
        COALESCE(sum(CASE WHEN kind='purchase' AND status='approved' THEN amount ELSE 0 END),0) AS purchases,
        COALESCE(sum(CASE WHEN kind='refund' AND status='approved' THEN amount ELSE 0 END),0) AS refunds
        FROM transaction_spending''').fetchone()
    months = conn.execute('''SELECT month,sum(spent) AS spent,sum(purchases) AS purchases,
        sum(refunds) AS refunds,sum(transaction_count) AS transactions
        FROM monthly_category_spending GROUP BY month ORDER BY month''').fetchall()
    return {
        'tables': {r['name']: relation_fingerprint(conn, r['name']) for r in tables},
        'views': {r['name']: relation_fingerprint(conn, r['name']) for r in views},
        'catalog': {key: {'objects': len(rows), 'sha256': fingerprint(rows)} for key, rows in catalog.items()},
        'totals': totals, 'monthly_totals': months,
        'migrations': [r['version'] for r in conn.execute('SELECT version FROM schema_migrations ORDER BY version').fetchall()],
    }


def tool_environment(url):
    settings = conninfo_to_dict(url)
    password = settings.pop('password', None)
    env = dict(os.environ)
    # No password/URL in the process arguments or public evidence.
    env['PGDATABASE'] = settings['dbname']
    for key, variable in {'host': 'PGHOST', 'hostaddr': 'PGHOSTADDR', 'port': 'PGPORT',
                          'user': 'PGUSER', 'sslmode': 'PGSSLMODE', 'sslrootcert': 'PGSSLROOTCERT',
                          'sslcert': 'PGSSLCERT', 'sslkey': 'PGSSLKEY', 'options': 'PGOPTIONS',
                          'service': 'PGSERVICE', 'passfile': 'PGPASSFILE'}.items():
        if key in settings:
            env[variable] = settings[key]
    if password is not None:
        env['PGPASSWORD'] = password
    env['PGCONNECT_TIMEOUT'] = '10'
    return env


def run_tool(executable, arguments, url, private_log):
    started = time.perf_counter()
    result = subprocess.run([str(executable), *map(str, arguments)], env=tool_environment(url),
                            capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=180)
    private_log.write_text(result.stdout + result.stderr, encoding='utf-8')
    if result.returncode:
        raise RuntimeError(f'{Path(executable).name} failed; inspect private log {private_log.name}')
    return {'exit_code': result.returncode, 'wall_seconds': time.perf_counter() - started,
            'stdout_characters': len(result.stdout), 'stderr_characters': len(result.stderr)}


def restored_checks(runtime_url, owner_url):
    runtime = lambda: connection(runtime_url)
    checks = {}
    with runtime() as conn:
        checks['runtime_role'] = conn.execute('SELECT current_user AS name').fetchone()['name']
        checks['runtime_superuser'] = conn.execute('SELECT rolsuper FROM pg_roles WHERE rolname=current_user').fetchone()['rolsuper']
    assert checks['runtime_superuser'] is False
    denied = []
    for name, statement in (
        ('insert', 'INSERT INTO transaction_audit_events (transaction_id) VALUES (gen_random_uuid())'),
        ('update', 'UPDATE transaction_audit_events SET created_at=now()'),
        ('delete', 'DELETE FROM transaction_audit_events'),
        ('truncate', 'TRUNCATE transaction_audit_events'),
        ('disable_creation_trigger', 'ALTER TABLE spending_transactions DISABLE TRIGGER spending_transaction_created'),
    ):
        try:
            with runtime() as conn:
                conn.execute(statement)
                raise AssertionError(f'Restored runtime unexpectedly allowed {name}; write rolled back')
        except psycopg.errors.InsufficientPrivilege:
            denied.append(name)
    checks['audit_operations_denied'] = denied

    # Exercise actual API reads on the copy using a temporary restored-only
    # access session. Its secret is never serialized and the row is removed.
    token = secrets.token_urlsafe(32)
    token_hash = main.digest(token)
    with runtime() as conn:
        selected = conn.execute('''SELECT t.user_id,date_trunc('month',max(t.occurred_at) AT TIME ZONE 'Asia/Karachi')::date AS month,
            count(*) AS transactions FROM spending_transactions t GROUP BY t.user_id
            ORDER BY count(*) DESC,t.user_id LIMIT 1''').fetchone()
        if selected is None:
            raise ValueError('Rehearsal API checks require a populated demo database')
        conn.execute("INSERT INTO sessions (token_hash,user_id,expires_at) VALUES (%s,%s,now()+interval '1 hour')", (token_hash, selected['user_id']))
        expected = conn.execute('''SELECT COALESCE(sum(CASE WHEN status='declined' THEN 0
            WHEN kind='refund' THEN -amount ELSE amount END),0) AS spent
            FROM spending_transactions WHERE user_id=%s
            AND date_trunc('month',occurred_at AT TIME ZONE 'Asia/Karachi')::date=%s''',
            (selected['user_id'], selected['month'])).fetchone()['spent']
    previous_connect = main.connect
    main.connect = runtime
    try:
        with TestClient(main.app) as api:
            headers = {'Authorization': 'Bearer ' + token}
            health = api.get('/health')
            me = api.get('/auth/me', headers=headers)
            history = api.get('/transactions?limit=100', headers=headers)
            month = selected['month'].strftime('%Y-%m')
            report = api.get('/reports/monthly', headers=headers, params={'month': month})
            assert health.status_code == me.status_code == history.status_code == report.status_code == 200
            assert len(history.json()) == min(selected['transactions'], 100)
            assert Decimal(report.json()['spent']) == expected
            checks['api'] = {'health': 200, 'authenticated_profile': 200, 'history': 200,
                             'history_rows': len(history.json()), 'monthly_report': 200,
                             'month': month, 'expected_spent': str(expected),
                             'reported_spent': report.json()['spent'], 'transport': 'in-process FastAPI TestClient'}
    finally:
        main.connect = previous_connect
        with runtime() as conn:
            conn.execute('DELETE FROM sessions WHERE token_hash=%s', (token_hash,))

    # Exercise the real domain write helper and creation trigger, then roll back
    # the smoke transaction so the retained restored copy matches the backup.
    conn = runtime()
    try:
        card = conn.execute('SELECT id,user_id FROM card_profiles WHERE NOT archived ORDER BY id LIMIT 1').fetchone()
        if card is None:
            raise ValueError('Rehearsal write check requires an active fictional card')
        body = PurchaseInput(card_id=card['id'], merchant='Restore smoke ' + uuid4().hex,
                             amount='12.34', occurred_at='2026-11-09T12:00:00+05:00',
                             channel='pos', source_reference=uuid4())
        saved, created = save_purchase(conn, card['user_id'], body)
        retry, retry_created = save_purchase(conn, card['user_id'], body)
        assert created is True and retry_created is False and saved['id'] == retry['id']
        audit = conn.execute('SELECT count(*) AS n FROM transaction_audit_events WHERE transaction_id=%s', (saved['id'],)).fetchone()['n']
        outbox = conn.execute('SELECT count(*) AS n FROM transaction_outbox WHERE transaction_id=%s', (saved['id'],)).fetchone()['n']
        assert audit == outbox == 1
        checks['write_smoke'] = {'created': True, 'retry_created': False, 'audit_rows': audit,
                                 'outbox_rows': outbox, 'amount': '12.34', 'transaction_rolled_back': True}
    finally:
        conn.rollback()
        conn.close()
    old_migration_connect = db.migration_connect
    db.migration_connect = lambda: connection(owner_url)
    try:
        db.migrate()
        checks['migration_rerun'] = 'passed'
    finally:
        db.migration_connect = old_migration_connect
    checks['notification_transport_started'] = False
    return checks


def main_cli():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--backup-directory', type=Path, default=Path(__file__).resolve().parents[1] / '.local' / 'backups')
    parser.add_argument('--pg-bin', type=Path)
    args = parser.parse_args()
    required = ('DATABASE_URL', 'MIGRATION_DATABASE_URL', 'REHEARSAL_ADMIN_DATABASE_URL')
    if any(not os.environ.get(key) for key in required):
        parser.error('Set DATABASE_URL, MIGRATION_DATABASE_URL and REHEARSAL_ADMIN_DATABASE_URL')
    runtime_url, source_url, admin_url = [os.environ[key] for key in required]
    source_settings, runtime_settings, admin_settings = [conninfo_to_dict(url) for url in (source_url, runtime_url, admin_url)]
    endpoint = lambda s: (s.get('host', 'localhost'), s.get('port', '5432'))
    if endpoint(source_settings) != endpoint(admin_settings) or endpoint(source_settings) != endpoint(runtime_settings):
        parser.error('All connections must target the same PostgreSQL cluster')
    if source_settings.get('dbname') != runtime_settings.get('dbname'):
        parser.error('Runtime and migration URLs must target the same source database')
    if args.output.exists() and any(args.output.iterdir()):
        parser.error('Choose a new evidence directory; existing evidence is never overwritten')
    executables = {}
    for name in ('pg_dump', 'pg_restore'):
        executable = args.pg_bin / (name + ('.exe' if os.name == 'nt' else '')) if args.pg_bin else shutil.which(name)
        if not executable or not Path(executable).exists():
            parser.error('Locate PostgreSQL tools using --pg-bin')
        executables[name] = Path(executable)
    args.output.mkdir(parents=True, exist_ok=True)
    args.backup_directory.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')
    target_name = 'spendtrail_restore_' + stamp.replace('-', '_') + '_' + uuid4().hex[:8]
    assert target_name != source_settings['dbname']
    archive = args.backup_directory / (target_name + '.dump')
    proof = {'status': 'running', 'started_utc': datetime.now(timezone.utc).isoformat(),
             'restored_database': target_name, 'restored_database_retained': True,
             'archive_name': archive.name, 'archive_format': 'PostgreSQL custom',
             'source_snapshot_method': 'pg_export_snapshot / pg_dump --snapshot; repeatable read read only',
             'tools': {name: subprocess.check_output([str(path), '--version'], text=True).strip() for name, path in executables.items()}}
    dump_json(args.output / 'rehearsal.json', proof)
    print('Capturing a consistent source snapshot and custom-format archive...', flush=True)
    with connection(source_url) as source:
        source.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY')
        exported = source.execute('SELECT pg_export_snapshot() AS id').fetchone()['id']
        source_info = source.execute('''SELECT current_setting('server_version') AS server_version,
            pg_get_userbyid(datdba) AS owner,
            pg_encoding_to_char(encoding) AS encoding,datcollate,datctype
            FROM pg_database WHERE datname=current_database()''').fetchone()
        before = snapshot(source)
        dump_json(args.output / 'source_snapshot.json', before)
        proof['dump'] = run_tool(executables['pg_dump'], ['--format=custom', '--no-password', '--snapshot=' + exported,
                                 '--file=' + str(archive)], source_url, args.backup_directory / (target_name + '.dump.log'))
    proof['archive_bytes'] = archive.stat().st_size
    proof['archive_sha256'] = hashlib.sha256(archive.read_bytes()).hexdigest()
    target_admin = make_conninfo(admin_url, dbname=target_name)
    target_owner = make_conninfo(source_url, dbname=target_name)
    target_runtime = make_conninfo(runtime_url, dbname=target_name)
    # Never restore into an operator-supplied database: always create a fresh,
    # generated name and refuse any collision before pg_restore is called.
    with psycopg.connect(admin_url, autocommit=True, row_factory=dict_row) as admin:
        assert not admin.execute('SELECT 1 FROM pg_database WHERE datname=%s', (target_name,)).fetchone()
        admin.execute(sql.SQL('CREATE DATABASE {} WITH TEMPLATE template0 OWNER {} ENCODING {} LC_COLLATE {} LC_CTYPE {}').format(
            sql.Identifier(target_name), sql.Identifier(source_info['owner']), sql.Literal(source_info['encoding']),
            sql.Literal(source_info['datcollate']), sql.Literal(source_info['datctype'])))
        admin.execute(sql.SQL('REVOKE CONNECT ON DATABASE {} FROM PUBLIC').format(sql.Identifier(target_name)))
        admin.execute(sql.SQL('GRANT CONNECT ON DATABASE {} TO {}, {}').format(sql.Identifier(target_name),
            sql.Identifier(source_info['owner']), sql.Identifier(runtime_settings['user'])))
    print('Restoring the archive into the newly created isolated database...', flush=True)
    proof['restore'] = run_tool(executables['pg_restore'], ['--dbname=' + target_name,
                               '--exit-on-error', '--single-transaction', '--no-password', archive],
                               target_admin, args.backup_directory / (target_name + '.restore.log'))
    with connection(target_owner) as restored:
        restored.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY')
        after_restore = snapshot(restored)
    dump_json(args.output / 'restored_snapshot.json', after_restore)
    assert after_restore == before, 'Restored data/catalog does not match the exported source snapshot'
    print('All row counts, data fingerprints, views, catalog definitions and privileges match.', flush=True)
    proof['restored_checks'] = restored_checks(target_runtime, target_owner)
    with connection(target_owner) as restored:
        restored.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY')
        after_smoke = snapshot(restored)
    assert after_smoke == before, 'Smoke checks left changes in the restored copy'
    dump_json(args.output / 'after_smoke_snapshot.json', after_smoke)
    with connection(source_url) as source:
        source.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY')
        live_after = snapshot(source)
    dump_json(args.output / 'live_after_snapshot.json', live_after)
    proof.update(status='passed', finished_utc=datetime.now(timezone.utc).isoformat(),
                 source_database_written_by_runner=False, application_configuration_changed=False,
                 data_catalog_and_acl_match=True, restored_smoke_changes_removed=True,
                 live_after_matches_exported_snapshot=(live_after == before),
                 source_snapshot_sha256=fingerprint(before), restored_snapshot_sha256=fingerprint(after_restore),
                 source_database_properties=source_info,
                 runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    dump_json(args.output / 'rehearsal.json', proof)
    print(json.dumps({'status': 'passed', 'database': target_name, 'archive_bytes': proof['archive_bytes'],
                      'tables_verified': len(before['tables']), 'views_verified': len(before['views']),
                      'transactions': before['totals']['transactions'], 'spent': str(before['totals']['spent']),
                      'live_source_matches': proof['live_after_matches_exported_snapshot']}, indent=2), flush=True)


if __name__ == '__main__':
    main_cli()
