# Database index evaluation

Completed on 9 November 2026. Two independent runs each recreated and evaluated
10,000 and 100,000 transactions in fresh schemas in the dedicated test database.
The application database and its indexes were not changed.

## Method and reproducibility

The runner is [index_benchmarks.py](../backend/tools/index_benchmarks.py).
It applies the actual migrations through 009, keeps every application index,
constraint and transaction audit/outbox trigger enabled, and loads seed
`20261109`. Each dataset has 20 users, five cards per user, ten merchants and
six categories per user. Amounts and dates are deterministic pseudorandom
values. Dates cover 2026; sources are 80% manual and 20% simulation, with
10% of all transactions declined. All are purchases; refund performance is
outside this workload. UUIDs and creation timestamps are fixed by the generator.
The 10,000 transactions are a prefix of the 100,000-row generator.

Each size also has one pending import preview per ten transactions, with ten
JSON row objects per preview. These previews are independent of the recorded
manual/simulated purchases and use the app's existing `import_batches.rows`
JSONB structure. One percent of previews has an error row. Every preview has
ready rows. The JSON containment searches model possible diagnostic searches;
the current API retrieves previews by ID and does not execute these searches.

The environment was Windows 11, Python 3.13.12 and PostgreSQL 15.17, with 16
logical CPUs. Shared buffers were 128 MiB, work memory 4 MiB, random page cost
4 and sequential page cost 1. Full captured settings, CPU identifier, database
version, table sizes and dataset fingerprints are included in each bundle.

Before measuring, the runner vacuumed/analyzed the data once. Each query has
three warmups followed by eleven measured `EXPLAIN (ANALYZE, BUFFERS, SETTINGS,
FORMAT JSON)` executions per phase. B-tree/hash comparison uses two rounds in
opposite orders, yielding 22 samples per candidate/query per dataset/run.
Only one candidate exists at a time. The baseline is measured before adding
the candidates and again after dropping them. No scan methods are forced and
no operating-system or database caches are flushed. Automatic prepared
statements are disabled for these planner experiments.

The reported time is server execution time, excluding planning, network,
Flutter rendering and user interaction. Planning times, p95, min, buffer hits
and reads are preserved separately. Buffer totals come from the root plan;
child totals are not added again. The measured queries had warm-cache reads,
with median shared reads of zero. Background activity and CPU scheduling were
not controlled; small timing differences are not reliable product gains.

## Measured findings

These medians are from the first complete run, in milliseconds. Every sample
and the second independent run remain available, including slower outcomes.

| Query / candidate | 10,000: baseline → candidate | 100,000: baseline → candidate |
| --- | ---: | ---: |
| Joined monthly history / card-date B-tree | 0.123 → 0.238 | 1.089 → 0.995 |
| Joined yearly history / card-date B-tree | 0.202 → 0.272 | 2.987 → 2.556 |
| Reference-only equality hit / standalone B-tree | 0.941 → 0.0380 | 19.609 → 0.0165 |
| Reference-only equality hit / standalone hash | 0.941 → 0.0240 | 19.609 → 0.0160 |
| JSON reference containment / GIN | 4.939 → 0.045 | 37.874 → 0.049 |
| JSON rare error containment / GIN | 3.719 → 0.080 | 18.347 → 0.290 |
| JSON ready containment, all previews / GIN | 2.992 → 2.883 | 8.911 → 21.745 |

### Card and date history

The candidate was exactly B-tree `(card_id, occurred_at DESC)`. The month/year
queries use the API's real transaction/merchant/category joins, owner and card
filters, inclusive/exclusive timestamp bounds, descending timestamp/ID order,
limit 25 and offset zero. Combined all-card history is a control.

The planner did not use this candidate for these queries in either independent
run. Monthly queries combined the existing owner/date history index and
card/source/reference uniqueness index through bitmap scans. Yearly queries
used the existing `(user_id, card_id, id)` uniqueness index. All-card history
continued to use `spending_transactions_user_history`.

At 100,000 rows the initial monthly baseline had 105 buffer hits; the candidate
phase also had 105, and the after-drop phase still had 105. The respective
medians were 1.089, 0.995 and 0.692 ms. An after-drop result faster than the
candidate illustrates the measurement drift. The repeat run measured 0.593,
0.569 and 0.589 ms, again with the same existing scan choices. These results
do not establish a benefit from adding the candidate to the current app.

### B-tree versus hash

Candidates indexed only `source_reference`, one at a time. Hit and missing-key
queries filter by reference alone; a separate control reproduces the app's
owner/card/source/reference lookup with its joins. The mandatory composite
unique index `(card_id, source, source_reference)` was retained throughout,
along with the owner history, category history, foreign-key/unique and primary
key indexes. Every phase records the full definitions and byte sizes.

Reference-only baseline queries chose sequential scans. At 100,000 rows, the
hit query's buffer activity fell from 2,858 hits to four with B-tree and two
with hash. Both candidates were selected in their respective phases. Hash used
less space in these datasets and its median was lower in both runs, but the
first run's 100,000-row hit difference was only 0.0005 ms; the repeat medians
were 0.0335 ms for B-tree and 0.0100 ms for hash. This is not a universal winner
claim or evidence about writes, ranges, ordering or another data distribution.

The actual API control already used the composite unique index in the baseline:
0.109 ms at 100,000 rows versus 0.0705 ms with standalone B-tree and 0.0630 ms
with hash. After removing the candidates it measured 0.034 ms. The repeat run
measured 0.050, 0.0535, 0.0350 and 0.044 ms respectively. There is no demonstrated
need to add a redundant standalone reference index to the current application.
The uniqueness constraint was never removed or replaced.

### GIN and JSON containment

The candidate was `USING gin (rows jsonb_path_ops)`. Queries used `rows @>` with
arrays containing an exact reference, `state=error`, or `state=ready`.
They matched one preview, 1% of previews, and all previews respectively. Actual
counts were checked and stayed identical in every phase and independent run.

Selective queries changed from sequential scans to bitmap index/heap scans.
At 100,000 transactions (10,000 JSON previews), exact-reference buffer hits
fell from 715 to five and rare-error hits to 104. The repeat exact-reference
medians were 23.802 ms without GIN and 0.024 ms with GIN.

The common-ready control also selected GIN, but scanned all 10,000 previews:
722 buffer hits versus 715 for the baseline and 21.745 versus 8.911 ms in the
first run. The repeat measured 15.885 versus 13.202 ms, with an after-drop
baseline of 15.282 ms. GIN did not help this nonselective workload. No GIN
index was added to the application database because the current API has no
corresponding containment search.

### Candidate storage

These are actual `pg_relation_size` bytes. Full application-index sizes,
candidate build wall times and table sizes are also saved.

| Candidate | 10,000 transactions | 100,000 transactions |
| --- | ---: | ---: |
| Card/date B-tree | 425,984 | 4,087,808 |
| Reference B-tree | 606,208 | 5,931,008 |
| Reference hash | 540,672 | 4,210,688 |
| Import-preview GIN | 622,592 | 6,275,072 |

## Evidence and verification

- [First run: full measured tables](evidence/indexes-20261109/RESULTS.md).
- [Independent repeat: full measured tables](evidence/indexes-20261109-repeat/RESULTS.md).
- [Machine-readable evidence verification](evidence/INDEX_VERIFICATION.json)
  and [application data / schema cleanup check](evidence/BENCHMARK_SAFETY_CHECK.json).
- Each size folder contains `workloads.sql`, parameter values in `workloads.json`,
  environment/correctness `metadata.json`, per-phase index inventories and
  timings, `summary.json`, and every raw JSON plan under `plans/`.

Across both runs, **1,584 measured plans** were independently checked against
the reported timing arrays and medians. The verifier also regenerated both
dataset fingerprints, checked exact transaction/audit/outbox counts and
approved spending totals, checked identical query results across index variants
and independent runs, and checked one candidate at a time while all existing
indexes stayed unchanged. Dataset spending was PKR 22,668,085.05 at 10,000 rows
and PKR 224,933,124.15 at 100,000 rows. Seed, SQL and parameters matched across
runs. Fresh benchmark schemas were removed after measurement.
The final safety check confirmed all four created schemas were gone and the
application still had nine transactions, nine audit records and PKR 18,998.55
in net spending, matching its prior verified checkpoint.

## Repeat the experiments

Use a dedicated PostgreSQL test database whose login can create schemas. The
runner requires `BENCHMARK_DATABASE_URL` or `TEST_DATABASE_URL`; it never falls
back to the application's `DATABASE_URL`. It refuses the same application
connection target, creates uniquely named schemas and removes only the schemas
it created. `--keep-schemas` retains them for inspection. Existing nonempty
output folders are refused so evidence is not overwritten.

From the repository root with the backend dependencies installed:

```powershell
$env:BENCHMARK_DATABASE_URL='postgresql://TEST_USER:PASSWORD@localhost:5432/spendtrail_test'
python backend/run.py tools.index_benchmarks --output docs/evidence/my-index-run
python backend/run.py tools.index_benchmarks --output docs/evidence/my-index-repeat
python backend/run.py tools.verify_index_evidence docs/evidence/my-index-run docs/evidence/my-index-repeat
```

The local machine used the documented pgAdmin embedded Python executable and
loaded the test URL from ignored `backend/.local/test.env`. Credentials and
database connection URLs are absent from the evidence artifacts.

The five index-evaluation roadmap items are complete. The next work is the
separate concurrency/rollback evidence package, then a backup restoration
rehearsal and final device/accessibility/release delivery checks.
