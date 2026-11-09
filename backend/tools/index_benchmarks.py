"""Repeatable PostgreSQL index experiments, exclusively in a test database.

Set BENCHMARK_DATABASE_URL or TEST_DATABASE_URL, then run from the repo root:
python backend/run.py tools.index_benchmarks --output docs/evidence/indexes
"""
import argparse
from datetime import datetime, timedelta, timezone
from decimal import Decimal
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import random
import statistics
import time
from uuid import UUID, uuid4, uuid5

import psycopg
from psycopg import sql
from psycopg.conninfo import conninfo_to_dict
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from app import db
from app.purchases import TRANSACTION_SELECT

NAMESPACE = UUID('f72d93d9-6f54-460e-8f71-df3c74f5aac0')
CREATED = datetime(2026, 1, 1, tzinfo=timezone.utc)
INDEX_NAME = 'benchmark_candidate'


def ident(label, seed):
    return uuid5(NAMESPACE, f'{seed}:{label}')


def transaction_rows(size, seed):
    """The 10k data is an exact prefix of the 100k data, excluding load metadata."""
    rng = random.Random(seed)
    for i in range(size):
        user, card, merchant, category = rng.randrange(20), rng.randrange(5), rng.randrange(10), rng.randrange(6)
        cents, seconds = rng.randrange(100, 500001), rng.randrange(365 * 86400)
        source = 'simulation' if i % 5 == 0 else 'manual'
        status = 'declined' if i % 10 == 0 else 'approved'
        yield (ident(f'transaction:{i}', seed), ident(f'user:{user}', seed),
               ident(f'card:{user}:{card}', seed), ident(f'merchant:{user}:{merchant}', seed),
               Decimal(cents) / 100, CREATED + timedelta(seconds=seconds), source,
               str(ident(f'reference:{i}', seed)), 'purchase', status,
               'online' if i % 2 else 'pos', ident(f'category:{user}:{category}', seed),
               ident(f'category:{user}:{category}', seed), CREATED)


def preview_rows(size, seed):
    """Ten-row pending previews; independent of the manual/simulated purchases."""
    rng = random.Random(seed + 1)
    for batch in range(size // 10):
        user, card = rng.randrange(20), rng.randrange(5)
        rows = []
        for row in range(10):
            invalid = batch % 100 == 0 and row == 0
            rows.append({'row': row + 2, 'reference': f'preview-{batch}-{row}',
                         'merchant': '' if invalid else f'Synthetic Merchant {row}',
                         'amount': '100.00', 'occurred_at': CREATED.isoformat(),
                         'channel': 'pos', 'category': '', 'category_id': None,
                         'state': 'error' if invalid else 'ready',
                         'message': 'Merchant must contain 1–100 characters' if invalid else 'Ready to import'})
        yield (ident(f'batch:{batch}', seed), ident(f'user:{user}', seed), ident(f'card:{user}:{card}', seed),
               f'synthetic-{batch}.csv', hashlib.sha256(f'{seed}:batch:{batch}'.encode()).hexdigest(),
               ident(f'token:{batch}', seed), Jsonb(rows), CREATED)


def seed_database(conn, size, seed):
    migrations = Path(db.__file__).resolve().parents[1] / 'migrations'
    for path in sorted(migrations.glob('*.sql')):
        conn.execute(path.read_text(encoding='utf-8'))
    for user in range(20):
        uid = ident(f'user:{user}', seed)
        conn.execute("INSERT INTO users (id,email,name,password_hash,created_at) VALUES (%s,%s,%s,'benchmark-only-not-a-login',%s)",
                     (uid, f'benchmark-{user}@example.invalid', f'Synthetic User {user}', CREATED))
        for card in range(5):
            conn.execute('''INSERT INTO card_profiles
                (id,user_id,label,network,last4,expiry_month,expiry_year,created_at)
                VALUES (%s,%s,%s,'visa',%s,12,2099,%s)''',
                (ident(f'card:{user}:{card}', seed), uid, f'Card {card}', f'{card:04}', CREATED))
        for merchant in range(10):
            conn.execute('INSERT INTO merchants (id,user_id,name) VALUES (%s,%s,%s)',
                         (ident(f'merchant:{user}:{merchant}', seed), uid, f'Synthetic Merchant {merchant}'))
        # Migration 003 ran on an empty schema, so there are no starter rows.
        for category in range(6):
            conn.execute('INSERT INTO categories (id,user_id,name) VALUES (%s,%s,%s)',
                         (ident(f'category:{user}:{category}', seed), uid, f'Category {category}'))
    fingerprint = hashlib.sha256()
    expected_cents = 0
    with conn.cursor().copy('''COPY spending_transactions
        (id,user_id,card_id,merchant_id,amount,occurred_at,source,source_reference,
         kind,status,channel,category_id,recorded_category_id,created_at) FROM STDIN''') as copy:
        for row in transaction_rows(size, seed):
            copy.write_row(row)
            fingerprint.update(json.dumps(row, default=str, separators=(',', ':')).encode() + b'\n')
            if row[9] == 'approved':
                expected_cents += int(row[4] * 100)
    with conn.cursor().copy('''COPY import_batches
        (id,user_id,card_id,file_name,file_hash,preview_token,rows,created_at) FROM STDIN''') as copy:
        for row in preview_rows(size, seed):
            copy.write_row(row)
    actual = conn.execute('''SELECT count(*) AS transactions,
        COALESCE(sum(spending_amount),0) AS spent FROM transaction_spending''').fetchone()
    assert actual['transactions'] == size
    assert actual['spent'] == Decimal(expected_cents) / 100
    counts = {}
    for table in ('transaction_audit_events', 'transaction_outbox', 'import_batches'):
        counts[table] = conn.execute(sql.SQL('SELECT count(*) AS n FROM {}').format(sql.Identifier(table))).fetchone()['n']
    assert counts['transaction_audit_events'] == counts['transaction_outbox'] == size
    assert counts['import_batches'] == size // 10
    return dict(transaction_sha256=fingerprint.hexdigest(), transactions=size,
                expected_spent=str(Decimal(expected_cents) / 100), observed_spent=str(actual['spent']), **counts)


def workloads(size, seed):
    first = next(transaction_rows(1, seed))
    uid, card = first[1:3]
    history = TRANSACTION_SELECT + ''' WHERE t.user_id = %s AND t.card_id = %s
        AND t.occurred_at >= %s AND t.occurred_at < %s
        ORDER BY t.occurred_at DESC, t.id DESC LIMIT 25 OFFSET 0'''
    return {
        'history_month': (history, (uid, card, '2026-06-01T00:00:00Z', '2026-07-01T00:00:00Z')),
        'history_year': (history, (uid, card, CREATED, '2027-01-01T00:00:00Z')),
        'history_all_cards_control': (TRANSACTION_SELECT + ''' WHERE t.user_id = %s
            ORDER BY t.occurred_at DESC, t.id DESC LIMIT 25 OFFSET 0''', (uid,)),
        'reference_hit': ('SELECT id, card_id, amount FROM spending_transactions WHERE source_reference = %s', (first[7],)),
        'reference_miss': ('SELECT id, card_id, amount FROM spending_transactions WHERE source_reference = %s', (str(ident('missing', seed)),)),
        'reference_api_control': (TRANSACTION_SELECT + ''' WHERE t.user_id = %s AND t.card_id = %s
            AND t.source = %s AND t.source_reference = %s''', (uid, card, first[6], first[7])),
        'json_reference': ('SELECT count(*) AS n FROM import_batches WHERE rows @> %s',
                           (Jsonb([{'reference': f'preview-{size // 20}-0'}]),)),
        'json_rare_error': ('SELECT count(*) AS n FROM import_batches WHERE rows @> %s', (Jsonb([{'state': 'error'}]),)),
        'json_common_ready_control': ('SELECT count(*) AS n FROM import_batches WHERE rows @> %s', (Jsonb([{'state': 'ready'}]),)),
    }


def dump(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, default=str) + '\n', encoding='utf-8')


def indexes(conn):
    return conn.execute('''SELECT c.relname AS name, pg_get_indexdef(c.oid) AS definition,
        pg_relation_size(c.oid) AS bytes FROM pg_class c
        JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname=current_schema() AND c.relkind='i' ORDER BY c.relname''').fetchall()


def plan_nodes(node):
    yield node
    for child in node.get('Plans', []):
        yield from plan_nodes(child)


def digest_result(conn, query, params):
    rows = conn.execute(query, params, prepare=False).fetchall()
    return {'rows': len(rows), 'sha256': hashlib.sha256(json.dumps(rows, default=str, sort_keys=True).encode()).hexdigest(),
            'count': rows[0]['n'] if rows and 'n' in rows[0] else None}


def measure(conn, output, name, selected, queries, repeats, warmups, expected):
    phase = {'name': name, 'indexes': indexes(conn), 'queries': {}}
    for key in selected:
        query, params = queries[key]
        result = digest_result(conn, query, params)
        if key in expected:
            assert result == expected[key], f'Result changed: {name}/{key}'
        else:
            expected[key] = result
        command = 'EXPLAIN (ANALYZE, BUFFERS, SETTINGS, FORMAT JSON) ' + query
        for _ in range(warmups):
            conn.execute(command, params, prepare=False).fetchone()
        plans = [conn.execute(command, params, prepare=False).fetchone()['QUERY PLAN'][0] for _ in range(repeats)]
        dump(output / 'plans' / f'{name}--{key}.json', plans)
        nodes = list(plan_nodes(plans[0]['Plan']))
        phase['queries'][key] = {
            'result': result,
            'execution_ms': [p['Execution Time'] for p in plans],
            'planning_ms': [p['Planning Time'] for p in plans],
            'shared_hits': [p['Plan'].get('Shared Hit Blocks', 0) for p in plans],
            'shared_reads': [p['Plan'].get('Shared Read Blocks', 0) for p in plans],
            'scan_nodes_first_sample': [{k: n[k] for k in ('Node Type', 'Relation Name', 'Index Name', 'Actual Rows', 'Rows Removed by Filter') if k in n}
                                        for n in nodes if 'Scan' in n['Node Type']],
        }
    dump(output / f'{name}.json', phase)
    return phase


def summarize(phases):
    grouped = {}
    for phase in phases:
        group = phase['name'].split('_round')[0]
        for name, result in phase['queries'].items():
            entry = grouped.setdefault((group, name), {'execution_ms': [], 'planning_ms': [], 'shared_hits': [], 'shared_reads': [],
                                                       'scans': result['scan_nodes_first_sample'], 'result': result['result']})
            for metric in ('execution_ms', 'planning_ms', 'shared_hits', 'shared_reads'):
                entry[metric].extend(result[metric])
    summary = []
    for (phase, name), entry in grouped.items():
        times = sorted(entry['execution_ms'])
        summary.append({'phase': phase, 'query': name, 'samples': len(times),
                        'median_ms': statistics.median(times), 'min_ms': min(times),
                        'p95_ms': times[math.ceil(len(times) * .95) - 1],
                        'median_planning_ms': statistics.median(entry['planning_ms']),
                        'median_shared_hits': statistics.median(entry['shared_hits']),
                        'median_shared_reads': statistics.median(entry['shared_reads']),
                        'scans': entry['scans'], 'result': entry['result']})
    return summary


def run_size(url, size, seed, output, repeats, warmups, keep):
    started_utc = datetime.now(timezone.utc).isoformat()
    schema = f'bench_{size}_{uuid4().hex}'
    output.mkdir(parents=True, exist_ok=False)
    with psycopg.connect(url, autocommit=True, row_factory=dict_row) as conn:
        conn.prepare_threshold = None
        conn.execute(sql.SQL('CREATE SCHEMA {}').format(sql.Identifier(schema)))
        try:
            conn.execute(sql.SQL('SET search_path TO {}').format(sql.Identifier(schema)))
            conn.execute("SET timezone TO 'UTC'")
            conn.execute("SET statement_timeout TO '120s'")
            start = time.perf_counter()
            with conn.transaction():
                correctness = seed_database(conn, size, seed)
            seed_seconds = time.perf_counter() - start
            # Stabilize visibility maps/statistics once. Never disable scans,
            # constraints or audit triggers, and never flush shared/OS caches.
            for table in ('users', 'card_profiles', 'merchants', 'categories', 'spending_transactions', 'import_batches', 'transaction_audit_events', 'transaction_outbox'):
                conn.execute(sql.SQL('VACUUM (ANALYZE) {}').format(sql.Identifier(table)))
            settings = conn.execute('''SELECT name, setting, unit FROM pg_settings WHERE name IN
                ('shared_buffers','effective_cache_size','work_mem','maintenance_work_mem','random_page_cost',
                 'seq_page_cost','jit','max_parallel_workers_per_gather','default_statistics_target',
                 'track_io_timing','server_version','block_size') ORDER BY name''').fetchall()
            queries = workloads(size, seed)
            dump(output / 'workloads.json', {key: {'sql': q, 'parameters': [p.obj if isinstance(p, Jsonb) else p for p in params]}
                                               for key, (q, params) in queries.items()})
            (output / 'workloads.sql').write_text('\n\n'.join(f'-- {key}\n{q};' for key, (q, _) in queries.items()) + '\n', encoding='utf-8')
            history = [k for k in queries if k.startswith('history_')]
            reference = [k for k in queries if k.startswith('reference_')]
            json_queries = [k for k in queries if k.startswith('json_')]
            phases, expected = [], {}

            def phase(name, selection, definition=None):
                conn.execute(sql.SQL('DROP INDEX IF EXISTS {}').format(sql.Identifier(INDEX_NAME)))
                build_start = time.perf_counter()
                if definition:
                    conn.execute(sql.SQL('CREATE INDEX {} ').format(sql.Identifier(INDEX_NAME)) + sql.SQL(definition))
                build_ms = (time.perf_counter() - build_start) * 1000 if definition else None
                result = measure(conn, output, name, selection, queries, repeats, warmups, expected)
                result['index_build_wall_ms'] = build_ms
                dump(output / f'{name}.json', result)
                phases.append(result)
                print(f'{size}: {name} complete', flush=True)

            phase('baseline', list(queries))
            phase('history_btree', history, 'ON spending_transactions USING btree (card_id, occurred_at DESC)')
            phase('history_after_drop', history)
            # Counterbalance candidate order. One candidate exists at any time;
            # all production indexes, including the uniqueness index, remain.
            for round_number, methods in ((1, ('btree', 'hash')), (2, ('hash', 'btree'))):
                for method in methods:
                    phase(f'reference_{method}_round{round_number}', reference,
                          f'ON spending_transactions USING {method} (source_reference)')
            phase('reference_after_drop', reference)
            phase('json_gin', json_queries, 'ON import_batches USING gin (rows jsonb_path_ops)')
            phase('json_after_drop', json_queries)
            with conn.transaction():
                # Count and exact monetary total must still match after all DDL.
                final = conn.execute('SELECT count(*) AS n, sum(spending_amount) AS spent FROM transaction_spending').fetchone()
                assert final['n'] == size and final['spent'] == Decimal(correctness['expected_spent'])
            metadata = {'size': size, 'seed': seed, 'schema': schema, 'schema_retained': keep,
                        'started_utc': started_utc, 'seed_wall_seconds': seed_seconds,
                        'repeats_per_phase': repeats, 'warmups_per_query_per_phase': warmups,
                        'correctness': correctness, 'settings': settings,
                        'version': conn.execute('SELECT version() AS value').fetchone()['value'],
                        'table_sizes': conn.execute('''SELECT relname, pg_relation_size(relid) AS heap_bytes,
                            pg_total_relation_size(relid) AS total_bytes FROM pg_stat_user_tables
                            WHERE schemaname=current_schema() ORDER BY relname''').fetchall()}
            summary = summarize(phases)
            dump(output / 'metadata.json', metadata)
            dump(output / 'summary.json', summary)
            return metadata, phases, summary
        finally:
            if not keep:
                # Only remove the exact fresh schema created by this invocation.
                assert schema.startswith(f'bench_{size}_') and len(schema.rsplit('_', 1)[1]) == 32
                conn.execute(sql.SQL('DROP SCHEMA {} CASCADE').format(sql.Identifier(schema)))


def write_report(output, runs, seed, repeats, warmups):
    lines = ['# PostgreSQL index experiment results', '',
             f'Seed: `{seed}`. {repeats} measured executions per query/phase after {warmups} warmups.', '',
             'Times below are PostgreSQL EXPLAIN execution times in milliseconds, excluding planning, client transport and rendering. '
             'These are warm-cache measurements; caches were not flushed and background activity was not controlled. '
             'Raw JSON plans preserve every measured sample. B-tree/hash medians pool two counterbalanced rounds.', '',
             'The baseline keeps all application indexes. Only one experimental candidate exists at a time. '
             'All constraints and audit/outbox triggers remain enabled. Pending ten-row import previews number one tenth '
             'of the transaction count; JSON diagnostics are an experimental workload, not an existing API endpoint.', '']
    for metadata, phases, summary in runs:
        lines += [f'## {metadata["size"]:,} transactions', '',
                  f'Correctness: {metadata["correctness"]["transactions"]:,} transactions and the same number of audit/outbox rows; '
                  f'PKR {metadata["correctness"]["observed_spent"]} approved spending. '
                  f'{metadata["correctness"]["import_batches"]:,} pending import previews. '
                  'Every workload returned identical results across its index variants.', '',
                  '| Phase | Query | Samples | Median ms | p95 ms | Hits / reads (median) | Scan / index in first sample |',
                  '| --- | --- | ---: | ---: | ---: | ---: | --- |']
        for row in summary:
            scans = '; '.join(n['Node Type'] + (' / ' + n['Index Name'] if 'Index Name' in n else ' / ' + n.get('Relation Name', '')) for n in row['scans'])
            lines.append(f'| {row["phase"]} | {row["query"]} | {row["samples"]} | {row["median_ms"]:.4f} | {row["p95_ms"]:.4f} | '
                         f'{row["median_shared_hits"]:g} / {row["median_shared_reads"]:g} | {scans} |')
        lines += ['', '| Candidate phase | Index bytes | Build wall ms |', '| --- | ---: | ---: |']
        for phase in phases:
            candidate = next((i for i in phase['indexes'] if i['name'] == INDEX_NAME), None)
            if candidate:
                lines.append(f'| {phase["name"]} | {candidate["bytes"]} | {phase["index_build_wall_ms"]:.3f} |')
        lines += ['', f'Environment, data fingerprint and table sizes: `{metadata["size"]}/metadata.json`. '
                  f'Existing index definitions/sizes: `{metadata["size"]}/baseline.json`. '
                  f'Exact SQL/parameters: `{metadata["size"]}/workloads.json`.', '']
    (output / 'RESULTS.md').write_text('\n'.join(lines), encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--sizes', type=int, nargs='+', default=[10000, 100000], choices=[10000, 100000])
    parser.add_argument('--seed', type=int, default=20261109)
    parser.add_argument('--repeats', type=int, default=11)
    parser.add_argument('--warmups', type=int, default=3)
    parser.add_argument('--keep-schemas', action='store_true')
    args = parser.parse_args()
    if args.repeats < 3 or args.warmups < 1 or len(set(args.sizes)) != len(args.sizes):
        parser.error('Use at least 3 repeats, 1 warmup and distinct sizes')
    url = os.environ.get('BENCHMARK_DATABASE_URL') or os.environ.get('TEST_DATABASE_URL')
    if not url:
        parser.error('Set BENCHMARK_DATABASE_URL or TEST_DATABASE_URL to a dedicated test database')
    app_url = os.environ.get('DATABASE_URL')
    if app_url:
        target, app = conninfo_to_dict(url), conninfo_to_dict(app_url)
        # Even different logins must not accidentally target application data.
        if all(target.get(k, default) == app.get(k, default) for k, default in (('host', 'localhost'), ('port', '5432'), ('dbname', ''))):
            parser.error('The benchmark database must differ from the application database')
    if args.output.exists() and any(args.output.iterdir()):
        parser.error('Choose a new or empty output directory; existing experiment evidence is never overwritten')
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = {'status': 'running', 'seed': args.seed, 'sizes': args.sizes,
                'python': platform.python_version(), 'os': platform.platform(),
                'processor': platform.processor(), 'logical_cpu_count': os.cpu_count(),
                'started_utc': datetime.now(timezone.utc).isoformat()}
    dump(args.output / 'run.json', manifest)
    runs = [run_size(url, size, args.seed, args.output / str(size), args.repeats, args.warmups, args.keep_schemas) for size in args.sizes]
    write_report(args.output, runs, args.seed, args.repeats, args.warmups)
    manifest.update(status='complete', finished_utc=datetime.now(timezone.utc).isoformat())
    dump(args.output / 'run.json', manifest)
    print(f'Completed. Results: {args.output / "RESULTS.md"}', flush=True)


if __name__ == '__main__':
    main()
