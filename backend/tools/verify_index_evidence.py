"""Offline verification of benchmark samples, results and independent reruns."""
import argparse
import hashlib
import json
from pathlib import Path
import statistics

from .index_benchmarks import INDEX_NAME, transaction_rows


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def verify_bundle(root):
    manifest = read(root / 'run.json')
    assert manifest['status'] == 'complete'
    results, plan_count = {}, 0
    for size in manifest['sizes']:
        folder = root / str(size)
        metadata = read(folder / 'metadata.json')
        correctness = metadata['correctness']
        assert correctness['transactions'] == correctness['transaction_audit_events'] == correctness['transaction_outbox'] == size
        assert correctness['import_batches'] == size // 10
        assert correctness['expected_spent'] == correctness['observed_spent']
        digest = hashlib.sha256()
        for row in transaction_rows(size, manifest['seed']):
            digest.update(json.dumps(row, default=str, separators=(',', ':')).encode() + b'\n')
        assert digest.hexdigest() == correctness['transaction_sha256']
        workloads = read(folder / 'workloads.json')
        baseline = read(folder / 'baseline.json')
        existing = {i['name']: i for i in baseline['indexes']}
        assert INDEX_NAME not in existing
        summary = read(folder / 'summary.json')
        raw_times = {}
        stable_results = {}
        phases = [p for p in folder.glob('*.json') if p.stem not in ('metadata', 'summary', 'workloads')]
        assert len(phases) == 10
        for path in phases:
            phase = read(path)
            candidates = [i for i in phase['indexes'] if i['name'] == INDEX_NAME]
            indexed = phase['name'] in ('history_btree', 'json_gin') or '_round' in phase['name']
            assert len(candidates) == int(indexed)
            assert {i['name']: i for i in phase['indexes'] if i['name'] != INDEX_NAME} == existing
            if candidates:
                method = 'gin' if phase['name'] == 'json_gin' else ('hash' if 'hash' in phase['name'] else 'btree')
                assert f'USING {method} ' in candidates[0]['definition']
                assert candidates[0]['bytes'] > 0
            group = phase['name'].split('_round')[0]
            for name, result in phase['queries'].items():
                assert name in workloads
                if name in stable_results:
                    assert stable_results[name] == result['result']
                stable_results[name] = result['result']
                plans = read(folder / 'plans' / f'{phase["name"]}--{name}.json')
                assert len(plans) == metadata['repeats_per_phase']
                assert [p['Execution Time'] for p in plans] == result['execution_ms']
                assert [p['Planning Time'] for p in plans] == result['planning_ms']
                assert [p['Plan'].get('Shared Hit Blocks', 0) for p in plans] == result['shared_hits']
                assert [p['Plan'].get('Shared Read Blocks', 0) for p in plans] == result['shared_reads']
                assert all(p['Execution Time'] >= 0 and p['Plan']['Actual Loops'] == 1 for p in plans)
                raw_times.setdefault((group, name), []).extend(result['execution_ms'])
                plan_count += len(plans)
        assert len(summary) == len(raw_times)
        for row in summary:
            samples = raw_times[(row['phase'], row['query'])]
            assert row['samples'] == len(samples)
            assert row['median_ms'] == statistics.median(samples)
            assert row['min_ms'] == min(samples)
        results[size] = {'transaction_sha256': correctness['transaction_sha256'],
                         'totals': correctness['observed_spent'], 'query_results': stable_results,
                         'workloads': workloads}
    return results, plan_count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundles', type=Path, nargs='+')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    first, total = None, 0
    for root in args.bundles:
        results, plans = verify_bundle(root)
        if first is None:
            first = results
        else:
            assert results == first, 'Independent runs differ in data, totals, SQL, parameters or query results'
        total += plans
    if args.output:
        tools = Path(__file__).resolve().parent
        migrations = tools.parent / 'migrations'
        proof = {'bundles': [str(p) for p in args.bundles], 'raw_plan_samples': total,
                 'independent_data_sql_parameters_and_results_identical': True,
                 'candidate_isolation_and_existing_indexes_verified': True,
                 'raw_plan_times_buffers_and_reported_medians_verified': True,
                 'benchmark_source_sha256': hashlib.sha256((tools / 'index_benchmarks.py').read_bytes()).hexdigest(),
                 'migration_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(migrations.glob('*.sql'))}}
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(proof, indent=2) + '\n', encoding='utf-8')
    print(f'PASS: {len(args.bundles)} bundles, {total} raw measured plans; data, results, candidate isolation and summaries verified.')


if __name__ == '__main__':
    main()
