"""Run the Flutter HTTP acceptance test against a disposable restricted API."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import sys
import time
from uuid import uuid4

import httpx
import psycopg
from psycopg import sql
from psycopg.conninfo import conninfo_to_dict, make_conninfo
from psycopg.rows import dict_row

from app import db
from app.db_access import grant_runtime_access


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--port', type=int, default=8011)
    args = parser.parse_args()
    url = os.environ.get('TEST_DATABASE_URL')
    if not url:
        parser.error('Set TEST_DATABASE_URL to a dedicated test administrator connection')
    test_settings = conninfo_to_dict(url)
    app_settings = conninfo_to_dict(os.environ['DATABASE_URL'])
    if test_settings.get('dbname') == app_settings.get('dbname'):
        parser.error('Use a separate test database')
    if args.output.exists() and any(args.output.iterdir()):
        parser.error('Use a new evidence directory')
    # Refuse a port already owned by another API before creating test data.
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', args.port))
    backend = Path(__file__).resolve().parents[1]
    args.output.mkdir(parents=True, exist_ok=True)
    schema, role = 'acceptance_' + uuid4().hex, 'acceptance_' + uuid4().hex
    password = secrets.token_urlsafe(32)
    proof = {'started_utc': datetime.now(timezone.utc).isoformat(), 'schema': schema,
             'restricted_role': role, 'url': f'http://127.0.0.1:{args.port}'}
    options = f'-c search_path={schema}'
    server = None
    log = None
    try:
        with psycopg.connect(url, options=options, row_factory=dict_row) as conn:
            conn.execute(sql.SQL('CREATE SCHEMA {}').format(sql.Identifier(schema)))
            for path in sorted((backend / 'migrations').glob('*.sql')):
                conn.execute(path.read_text(encoding='utf-8'))
            conn.execute(sql.SQL('CREATE ROLE {} LOGIN PASSWORD {}').format(sql.Identifier(role), sql.Literal(password)))
            grant_runtime_access(conn, role, schema)
        runtime_url = make_conninfo(url, user=role, password=password, options=options)
        env = dict(os.environ, DATABASE_URL=runtime_url)
        private_log = backend / '.local' / 'release-acceptance-api.log'
        private_log.parent.mkdir(parents=True, exist_ok=True)
        log = private_log.open('w', encoding='utf-8')
        server = subprocess.Popen([sys.executable, str(backend / 'run.py'), 'uvicorn', 'app.main:app',
                                   '--host', '127.0.0.1', '--port', str(args.port)], env=env,
                                  stdout=log, stderr=log, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            if server.poll() is not None:
                raise RuntimeError('Acceptance API failed to start; inspect private log')
            try:
                if httpx.get(proof['url'] + '/health', timeout=1).status_code == 200:
                    break
            except httpx.HTTPError:
                pass
            time.sleep(.1)
        else:
            raise RuntimeError('Acceptance API did not become ready')
        flutter = shutil.which('flutter')
        if not flutter:
            raise RuntimeError('Flutter is not on PATH')
        started = time.perf_counter()
        result = subprocess.run([flutter, 'test', '--no-pub', '--machine',
                                 '--dart-define=LIVE_API_URL=' + proof['url'], 'test/purchase_live_test.dart'],
                                cwd=backend.parent, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=180)
        (args.output / 'flutter-live.jsonl').write_text(result.stdout, encoding='utf-8')
        (backend / '.local' / 'release-live-test.err.log').write_text(result.stderr, encoding='utf-8')
        assert result.returncode == 0, 'Flutter live acceptance failed; inspect saved test output'
        events = [json.loads(line) for line in result.stdout.splitlines() if line.startswith('{')]
        done = [e for e in events if e.get('type') == 'done']
        assert done and done[-1]['success'] is True
        assert not any(e.get('type') == 'testDone' and (e.get('result') != 'success' or e.get('skipped')) for e in events)
        proof['flutter_test'] = {'passed': True, 'wall_seconds': time.perf_counter() - started, 'skipped': 0}
        with psycopg.connect(runtime_url, row_factory=dict_row) as conn:
            counts = {table: conn.execute(sql.SQL('SELECT count(*) AS n FROM {}').format(sql.Identifier(table))).fetchone()['n']
                      for table in ('users', 'spending_transactions', 'transaction_audit_events', 'transaction_outbox')}
            assert counts['spending_transactions'] == counts['transaction_audit_events'] == counts['transaction_outbox'] > 0
            proof['committed_counts'] = counts
    finally:
        if server is not None:
            server.terminate()
            try:
                server.wait(timeout=10)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=5)
        if log is not None:
            log.close()
        with psycopg.connect(url) as conn:
            if conn.execute('SELECT 1 FROM pg_roles WHERE rolname=%s', (role,)).fetchone():
                conn.execute(sql.SQL('DROP OWNED BY {}').format(sql.Identifier(role)))
                conn.execute(sql.SQL('DROP ROLE {}').format(sql.Identifier(role)))
            conn.execute(sql.SQL('DROP SCHEMA IF EXISTS {} CASCADE').format(sql.Identifier(schema)))
    proof.update(status='passed', cleanup='schema and role removed; isolated API stopped',
                 finished_utc=datetime.now(timezone.utc).isoformat(), application_database_changed=False)
    (args.output / 'verification.json').write_text(json.dumps(proof, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(proof, indent=2))


if __name__ == '__main__':
    main()
