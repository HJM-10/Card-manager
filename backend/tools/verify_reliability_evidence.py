"""Check saved reliability observations without connecting to a database."""
import argparse
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET


def junit(path, expected):
    root = ET.parse(path).getroot()
    suites = list(root.iter('testsuite'))
    assert sum(int(s.get('tests', 0)) for s in suites) == expected
    for field in ('failures', 'errors', 'skipped'):
        assert sum(int(s.get(field, 0)) for s in suites) == 0
    return {'tests': expected, 'failures': 0, 'errors': 0, 'skipped': 0,
            'seconds': sum(float(s.get('time', 0)) for s in suites)}


def assert_triples(snapshot, count):
    assert len(snapshot['transactions']) == count
    for table in ('spending_transactions', 'transaction_audit_events', 'transaction_outbox', 'notification_events'):
        assert snapshot['counts'][table] == count
    assert all(t['audits'] == t['outbox_events'] == t['device_events'] == 1 for t in snapshot['transactions'])


def verify(folder):
    primary = junit(folder / 'junit.xml', 23)
    cases = [json.loads(p.read_text(encoding='utf-8')) for p in sorted((folder / 'cases').glob('*.json'))]
    assert len(cases) == len({c['test'] for c in cases}) == 23
    race_prefixes = ('test_eight_simultaneous_matching_purchases_commit_once',
                     'test_conflicting_simultaneous_payloads_commit_one_winner',
                     'test_competing_api_refunds_cannot_exceed_purchase',
                     'test_direct_sql_duplicate_constraint_commits_once',
                     'test_direct_sql_competing_refunds_obey_database_trigger')
    expected = {f'{prefix}[{i}]' for prefix in race_prefixes for i in (1, 2, 3)}
    expected.update({
        'test_matching_refund_retries_create_one_refund_event',
        'test_failed_purchase_rolls_back_every_write_then_retries[transaction_audit_events]',
        'test_failed_purchase_rolls_back_every_write_then_retries[transaction_outbox]',
        'test_csv_second_row_failure_rolls_back_first_row_and_batch',
        'test_failed_refund_preserves_purchase_and_refund_capacity',
        'test_uncommitted_transaction_is_invisible_and_is_discarded[rollback]',
        'test_uncommitted_transaction_is_invisible_and_is_discarded[disconnect]',
        'test_commit_exposes_transaction_audit_and_outbox_together',
    })
    assert {c['test'] for c in cases} == expected
    races, workers, failures, discards = 0, 0, 0, 0
    for case in cases:
        name = case['test']
        assert case['status'] == 'passed'
        assert case['runtime']['superuser'] is False
        assert case['runtime']['isolation'] == 'read committed'
        if 'lock_observation' in case:
            observation = case['lock_observation']
            rows = observation['observed_blocked']
            assert len(rows) == len({r['pid'] for r in rows}) == observation['workers']
            assert all(r['wait_event_type'] == 'Lock' and r['blockers'] for r in rows)
            blockers = {r['pid']: r['blockers'] for r in rows}

            def reaches_gate(pid, visited):
                if pid == observation['gate_pid']:
                    return True
                if pid in visited:
                    return False
                return any(reaches_gate(parent, visited | {pid}) for parent in blockers.get(pid, []))

            assert all(reaches_gate(row['pid'], set()) for row in rows)
            assert len(case['responses']) == observation['workers']
            races += 1
            workers += observation['workers']
            if name.startswith('test_eight_'):
                assert sorted(r['status'] for r in case['responses']) == [200] * 7 + [201]
                assert len({r['body']['id'] for r in case['responses']}) == 1
                assert_triples(case['committed'], 1)
            elif name.startswith('test_conflicting_'):
                assert sorted(r['status'] for r in case['responses']) == [201, 409]
                assert_triples(case['committed'], 1)
            elif name.startswith('test_direct_sql_duplicate_'):
                assert sum(r['outcome'] == 'committed' for r in case['responses']) == 1
                assert sum(r.get('sqlstate') == '23505' for r in case['responses']) == 3
                assert all(r['constraint'] == 'spending_transactions_card_id_source_source_reference_key'
                           for r in case['responses'] if r['outcome'] == 'rejected')
                assert_triples(case['committed'], 2)
            else:
                assert_triples(case['committed'], 2)
                assert case['committed']['spent'] == '450.05'
                if name.startswith('test_direct_sql_competing_'):
                    assert sorted(r['outcome'] for r in case['responses']) == ['committed', 'rejected']
                    assert next(r for r in case['responses'] if r['outcome'] == 'rejected')['sqlstate'] == '23514'
                elif name.startswith('test_matching_refund_'):
                    assert sorted(r['status'] for r in case['responses']) == [200] * 3 + [201]
                    assert len({r['body']['id'] for r in case['responses']}) == 1
                else:
                    assert sorted(r['status'] for r in case['responses']) == [201, 409]
        elif 'failed_response' in case:
            assert case['failed_response']['status'] == 500
            assert case['before'] == case['after_failure']
            assert len(case['transient_notices']) == 1
            notice = case['transient_notices'][0]
            assert notice['transaction_visible'] is True
            assert notice['audit_visible'] == ('transaction_audit_events' not in name)
            failures += 1
            if name.startswith('test_csv_'):
                assert notice['batch_transactions'] == notice['batch_audits'] == 2
                assert notice['batch_outbox'] == 1
                assert case['after_failure']['imports'][0]['status'] == 'preview'
                assert case['committed']['imports'][0]['status'] == 'confirmed'
                assert_triples(case['committed'], 2)
            elif name.startswith('test_failed_refund_'):
                assert_triples(case['committed'], 2)
                assert case['committed']['spent'] == '450.05'
            else:
                assert case['recovery_statuses'] == [201, 200]
                assert_triples(case['committed'], 1)
        elif 'after_discard' in case:
            assert case['before'] == case['other_connection_before_end'] == case['after_discard']
            assert all(n == 1 for n in case['inside_uncommitted_counts'].values())
            discards += 1
        else:
            for table in ('spending_transactions', 'transaction_audit_events', 'transaction_outbox'):
                assert case['after_commit_before_fanout']['counts'][table] == case['before']['counts'][table] + 1
            assert_triples(case['after_fanout'], 2)
    assert (races, workers, failures, discards) == (16, 58, 4, 2)
    backend = Path(__file__).resolve().parents[1]
    files = [backend / 'tests' / n for n in ('test_reliability_evidence.py', 'test_audit_protection.py', 'test_accounts_cards.py')]
    files += [backend / 'app' / n for n in ('main.py', 'purchases.py', 'csv_imports.py', 'notifications.py', 'db_access.py')]
    files += sorted((backend / 'migrations').glob('*.sql'))
    proof = {'status': 'passed', 'focused_suite': primary, 'observed_races': races,
             'database_observed_waiting_workers': workers, 'injected_failure_rollbacks': failures,
             'explicit_rollback_or_disconnect_cases': discards, 'commit_visibility_cases': 1,
             'case_schemas': [c['schema'] for c in cases],
             'case_roles': [c['runtime']['role'] for c in cases],
             'source_sha256': {str(p.relative_to(backend)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
    full = folder / 'full-backend-junit.xml'
    if full.exists():
        proof['full_backend_suite'] = junit(full, 104)
    (folder / 'verification.json').write_text(json.dumps(proof, indent=2) + '\n', encoding='utf-8')
    return proof


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('folder', type=Path)
    args = parser.parse_args()
    proof = verify(args.folder)
    print(f'PASS: 23 cases; {proof["observed_races"]} observed races, '
          f'{proof["database_observed_waiting_workers"]} waiting workers, '
          '4 fault rollbacks, 2 discarded transactions and committed-only visibility.')


if __name__ == '__main__':
    main()
