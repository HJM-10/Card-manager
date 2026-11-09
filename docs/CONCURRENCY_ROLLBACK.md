# Concurrency, rollback and committed-event evidence

Completed on 9 November 2026 against PostgreSQL 15.17. All application writes
in the focused tests used real restricted database logins at READ COMMITTED.
The test administrator created isolated schemas/roles, injected faults and
observed locks. It did not perform the application writes under test.

## Observed contention

The new [reliability tests](../backend/tests/test_reliability_evidence.py)
coordinate independent worker threads with a barrier. A separate connection
holds a card-row lock (or the original purchase lock for direct SQL refunds).
An administrator observes `pg_stat_activity`, `wait_event_type=Lock` and
`pg_blocking_pids()` until **all workers are waiting**. Only then is the held
lock released and each request allowed to complete. Every observation stores
the gate PID, worker PIDs, wait events and blocker relationships. Offline
verification checks that every blocker chain leads back to the gate.

Sixteen races covered **58 database-observed waiting workers**. Five scenarios
were repeated three times in fresh schemas; matching refund retries add one
four-worker race. Each worker has its own database connections. HTTP scenarios
use the actual FastAPI routes through independent in-process test clients;
they are not network or phone load tests. Direct SQL scenarios bypass the API
to separately exercise database constraints/triggers.

| Scenario | Workers per race | Races | Observed result per race |
| --- | ---: | ---: | --- |
| Identical manual purchase requests | 8 | 3 | One 201, seven 200 responses; identical returned transaction |
| Same purchase reference, conflicting amounts | 2 | 3 | One 201 and one 409; stored amount matches the winner |
| Two different PKR 800 refunds against PKR 1,250.05 | 2 | 3 | One 201 and one 409; net spending remains PKR 450.05 |
| Direct SQL purchases sharing one card/source/reference | 4 | 3 | One commit; three unique-constraint rejections, SQLSTATE 23505 |
| Direct SQL refunds competing for the same purchase | 2 | 3 | One commit; one trigger rejection, SQLSTATE 23514; PKR 450.05 remains |
| Matching refund retries | 4 | 1 | One 201, three 200 responses; one refund and one creation event |

After each successful write, the tests expand the committed outbox using the
real fan-out function, then expand it again and verify no additional work.
Each transaction has **one audit row, one outbox row and one notification event
for the single enabled test device**. The tests inspect both aggregate counts
and counts joined to each transaction. Original purchases used as fixtures
are counted separately from the one new purchase/refund under test.

The synthetic device is never passed to FCM. This verifies event creation and
idempotent fan-out; it does not claim exactly-once external push delivery.

Representative raw observations:

- [Eight matching purchases](evidence/reliability-20261109/cases/test_eight_simultaneous_matching_purchases_commit_once_1_.json).
- [Native duplicate constraint](evidence/reliability-20261109/cases/test_direct_sql_duplicate_constraint_commits_once_1_.json).
- [Database refund ceiling](evidence/reliability-20261109/cases/test_direct_sql_competing_refunds_obey_database_trigger_1_.json).

## Fault injection and rollback

Administrator-installed triggers in the disposable schemas raise a deliberate
SQLSTATE 23514 failure during audit/outbox insertion. Immediately before
raising the exception, each trigger emits a diagnostic notice describing rows
visible **inside that still-uncommitted transaction**. The application
connection captures that notice; the HTTP request returns 500. A separate
connection then verifies that the entire recorded state matches the snapshot
before the failed request, including merchants, purchases, audit/outbox rows,
notification events and import state.

| Fault | Transient state observed before failure | Committed state after failure | Recovery |
| --- | --- | --- | --- |
| Purchase audit insert | Transaction visible; audit absent | No new merchant, transaction, audit or outbox | Same request returns 201, then 200 on retry |
| Purchase outbox insert | Transaction and audit visible | No new merchant, transaction, audit or outbox | Same request returns 201, then 200 on retry |
| Second CSV row's outbox insert | Two transactions, two audits and first row's outbox visible | No purchases/events/merchants; original batch remains an unchanged preview | Same token imports exactly two rows; replay returns the same receipt |
| Refund outbox insert | Refund transaction and audit visible | Original purchase, total and available refund capacity unchanged | Same refund succeeds after removing the injected fault |

The CSV recovery produces exactly two transaction/audit/outbox/device-event
sets and PKR 200.00 spending. The refund recovery leaves PKR 450.05. No test
relies only on a 500 response as evidence of rollback: each compares database
snapshots and checks the transient notice and successful recovery.

- [Purchase outbox failure](evidence/reliability-20261109/cases/test_failed_purchase_rolls_back_every_write_then_retries_transaction_outbox_.json).
- [Second CSV row failure](evidence/reliability-20261109/cases/test_csv_second_row_failure_rolls_back_first_row_and_batch.json).
- [Refund failure and recovery](evidence/reliability-20261109/cases/test_failed_refund_preserves_purchase_and_refund_capacity.json).

## Transaction boundaries and visibility

Two additional cases insert a transaction and observe its audit/outbox rows
from the same connection, without committing. A second connection sees none
of those additions, and outbox expansion finds no new event. One case calls
explicit rollback; the other closes the database connection without commit.
Both leave the database identical to its prior snapshot.

A commit control shows the opposite: before commit the write is invisible;
after commit the transaction, audit and outbox counts all increase together.
Notification expansion then creates exactly one device event, and running
expansion again creates none.

These checks cover orderly connection closure and transaction rollback. They
are not a database-server crash, power-loss or filesystem-durability experiment.

- [Uncommitted connection closure](evidence/reliability-20261109/cases/test_uncommitted_transaction_is_invisible_and_is_discarded_disconnect_.json).
- [Commit visibility](evidence/reliability-20261109/cases/test_commit_exposes_transaction_audit_and_outbox_together.json).

## Verification and reproduction

The focused suite passed **23 tests in 53.51 seconds**, with one existing
Starlette/AnyIO dependency deprecation warning. Its raw test results are in
[junit.xml](evidence/reliability-20261109/junit.xml). The evidence verifier checks
all 23 expected scenarios, native constraint outcomes, committed counts,
duplicate response IDs, refund totals, blocker chains, failed-write snapshots
and transient notices. It records source and migration hashes in
[verification.json](evidence/reliability-20261109/verification.json).

The final full backend suite passed **104 tests in 186.88 seconds**, with the
same single dependency warning and no skipped tests. Its raw results are in
[full-backend-junit.xml](evidence/reliability-20261109/full-backend-junit.xml).
The offline verifier also checks that report contains no failures or errors.

The final [safety check](evidence/reliability-20261109/safety_check.json)
confirmed that all 23 recorded schemas and 23 restricted test roles had been
removed. The application still had nine transactions, nine audit records and
PKR 18,998.55 net spending, matching the prior verified checkpoint.

Use a dedicated PostgreSQL test database and an administrator with schema/role
creation and cleanup privileges plus visibility into other sessions. The test
fixtures create and remove randomly named schemas and runtime roles. Existing
evidence files are never overwritten; choose a new folder for another run.

From the repository root, with the backend dependencies installed:

```powershell
$env:TEST_DATABASE_URL='postgresql://TEST_ADMIN:PASSWORD@localhost:5432/spendtrail_test'
$env:RELIABILITY_EVIDENCE_DIR='docs/evidence/my-reliability-run/cases'
python backend/run.py pytest backend/tests/test_reliability_evidence.py -q --junitxml=docs/evidence/my-reliability-run/junit.xml
Remove-Item Env:RELIABILITY_EVIDENCE_DIR
python backend/run.py tools.verify_reliability_evidence docs/evidence/my-reliability-run
```

The workspace uses the documented pgAdmin embedded Python executable and
loads test credentials from ignored `backend/.local/test.env`. Tokens and
database credentials are not written into the case observations. All response
content in the artifacts belongs to synthetic accounts in disposable schemas.

The concurrency/rollback roadmap item is complete. Backup restoration and the
final device/accessibility/release demonstration package remain separate work.
