"""Verify saved restoration evidence and, optionally, its private dump archive."""
import argparse
from decimal import Decimal
import hashlib
import json
from pathlib import Path


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, default=str, separators=(',', ':')).encode()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('folder', type=Path)
    parser.add_argument('--archive', type=Path)
    args = parser.parse_args()
    read = lambda name: json.loads((args.folder / name).read_text(encoding='utf-8'))
    proof = read('rehearsal.json')
    before = read('source_snapshot.json')
    restored = read('restored_snapshot.json')
    after_smoke = read('after_smoke_snapshot.json')
    live = read('live_after_snapshot.json')
    assert proof['status'] == 'passed'
    assert before == restored == after_smoke
    assert fingerprint(before) == proof['source_snapshot_sha256'] == proof['restored_snapshot_sha256']
    assert (before == live) == proof['live_after_matches_exported_snapshot']
    assert proof['source_database_written_by_runner'] is False
    assert proof['application_configuration_changed'] is False
    assert proof['data_catalog_and_acl_match'] is True
    assert proof['restored_smoke_changes_removed'] is True
    assert proof['restored_database'].startswith('spendtrail_restore_')
    for phase in ('dump', 'restore'):
        assert proof[phase]['exit_code'] == 0 and proof[phase]['wall_seconds'] > 0
    for group in ('tables', 'views', 'catalog'):
        assert before[group]
        for entry in before[group].values():
            assert len(entry['sha256']) == 64
            int(entry['sha256'], 16)
    tables = before['tables']
    assert tables['spending_transactions']['rows'] == before['totals']['transactions']
    assert tables['transaction_audit_events']['rows'] == tables['transaction_outbox']['rows'] == before['totals']['transactions']
    assert sum(Decimal(row['spent']) for row in before['monthly_totals']) == Decimal(before['totals']['spent'])
    backend = Path(__file__).resolve().parents[1]
    assert before['migrations'] == [p.name for p in sorted((backend / 'migrations').glob('*.sql'))]
    runner = backend / 'tools' / 'backup_rehearsal.py'
    runner_bytes = runner.read_bytes()
    # Git on Windows can change LF to CRLF without changing the tested source.
    assert proof['runner_sha256'] in {
        hashlib.sha256(runner_bytes).hexdigest(),
        hashlib.sha256(runner_bytes.replace(b'\r\n', b'\n')).hexdigest(),
    }
    checks = proof['restored_checks']
    assert checks['runtime_superuser'] is False
    assert checks['audit_operations_denied'] == ['insert', 'update', 'delete', 'truncate', 'disable_creation_trigger']
    api = checks['api']
    assert all(api[key] == 200 for key in ('health', 'authenticated_profile', 'history', 'monthly_report'))
    assert Decimal(api['expected_spent']) == Decimal(api['reported_spent'])
    smoke = checks['write_smoke']
    assert smoke['created'] is True and smoke['retry_created'] is False
    assert smoke['audit_rows'] == smoke['outbox_rows'] == 1
    assert smoke['transaction_rolled_back'] is True
    assert checks['migration_rerun'] == 'passed'
    assert checks['notification_transport_started'] is False
    archive_verified = False
    if args.archive:
        assert args.archive.name == proof['archive_name']
        assert args.archive.stat().st_size == proof['archive_bytes']
        assert hashlib.sha256(args.archive.read_bytes()).hexdigest() == proof['archive_sha256']
        archive_verified = True
    verification = {'status': 'passed', 'tables_verified': len(tables), 'views_verified': len(before['views']),
                    'catalog_groups_verified': len(before['catalog']), 'archive_bytes_and_sha256_verified': archive_verified,
                    'source_restored_and_after_smoke_snapshots_identical': True,
                    'live_source_matches_snapshot': proof['live_after_matches_exported_snapshot'],
                    'runtime_audit_restrictions_verified': True, 'api_and_rolled_back_write_smoke_verified': True,
                    'transactions': before['totals']['transactions'], 'spent': before['totals']['spent']}
    (args.folder / 'verification.json').write_text(json.dumps(verification, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(verification, indent=2))


if __name__ == '__main__':
    main()
