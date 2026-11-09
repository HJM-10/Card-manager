# Database backup and restoration rehearsal

Completed on 9 November 2026 with PostgreSQL 15.17 on the existing Windows
development cluster. A new custom-format backup of the populated SpendTrail
database was restored into a newly created database and checked against the
same exported snapshot. The live API, notification worker and phone settings
were not switched to the restored copy.

## Actual result

| Check | Observed result |
| --- | --- |
| `pg_dump` | Exit 0; 0.435 seconds; no errors or warnings |
| Archive | 58,797 bytes, custom format |
| `pg_restore` | Exit 0; 0.444 seconds; no errors or warnings |
| All application tables | 14 row counts and SHA-256 data fingerprints matched |
| Reporting views | Both view-data fingerprints matched |
| Schema and security | Ten catalog groups matched, including constraints, indexes, trigger/function definitions, ownership and grants |
| Transactions / audit / outbox | 9 / 9 / 9, unchanged |
| Net approved spending | PKR 18,998.55, unchanged |
| Monthly report | November 2026: 9 transactions, PKR 18,998.55 |
| Restored runtime identity | `spendtrail_runtime`, not a superuser |
| Audit tampering | Insert, update, delete, truncate and disabling the creation trigger were denied |
| API on the restored copy | Health, authenticated profile, history and monthly report all returned 200 |
| Write and matching retry | One temporary PKR 12.34 purchase, one audit and one outbox; retry reused the record |
| Smoke-check cleanup | Temporary session removed; purchase transaction rolled back; restored fingerprints still matched the backup |
| Owner migration rerun | Succeeded; already-applied migrations stayed unchanged |
| Live source after rehearsal | Matched the exported snapshot across all checked data and catalog groups |

The archive and restored database are retained locally:

- Archive: `backend/.local/backups/spendtrail_restore_20261109_105211_28edad98.dump`.
- Restored database: `spendtrail_restore_20261109_105211_28edad98`.
- Private dump/restore logs: adjacent to the archive.
- Archive SHA-256:
  `f1f28ddf2306c70174f2c0de8b676b30cd54d6491d6ed6f877f9ed88397db1f1`.

The archive contains the database's account/session hashes and saved device
tokens as well as application records. Keep it in private storage; it is under
the ignored `backend/.local` directory and is not part of the public evidence.
The public artifacts contain row counts, aggregate amounts and fingerprints,
not copied account records, passwords, access tokens or database URLs.

These timings describe this small demonstration database, not recovery-time
estimates for a larger deployment.

## What was compared

| Table | Restored rows |
| --- | ---: |
| users | 3 |
| sessions | 18 |
| biometric_sessions | 3 |
| card_profiles | 4 |
| merchants | 9 |
| categories | 18 |
| spending_transactions | 9 |
| transaction_audit_events | 9 |
| transaction_outbox | 9 |
| import_batches | 1 |
| budgets | 1 |
| device_registrations | 1 |
| notification_events | 2 |
| schema_migrations | 9 |

The runner fingerprints canonical JSON text for **every row**, sorted in C
collation with UTC timestamps. This checks more than counts and aggregate
amounts: altered transaction values, audit timestamps, budgets, authentication
hashes and notification state would change a fingerprint.

The two views are `transaction_spending` and `monthly_category_spending`.
Catalog groups cover columns, 87 constraints, 40 indexes, three application
triggers, three functions, relation ownership, relation grants, function
grants, public-schema grants and view definitions. All nine migration records
were restored. Runtime permissions were additionally exercised using an actual
restricted login, rather than inferred solely from the catalog comparison.

## Reproduce the rehearsal

The runner is [backup_rehearsal.py](../backend/tools/backup_rehearsal.py).
It requires three connection settings:

- `DATABASE_URL`: the existing restricted application connection.
- `MIGRATION_DATABASE_URL`: the existing source schema-owner connection used
  to read and back up all application records.
- `REHEARSAL_ADMIN_DATABASE_URL`: an administrator connection to the same
  cluster, able to create a database and restore existing owners/grants.

The first two are loaded from ignored `backend/.env`. Supply the administrator
connection temporarily. Do not replace the application's connection with the
administrator connection.

From the repository root with the backend dependencies installed:

```powershell
$env:REHEARSAL_ADMIN_DATABASE_URL='postgresql://ADMIN:PASSWORD@localhost:5432/postgres'
python backend/run.py tools.backup_rehearsal --output docs/evidence/my-backup-rehearsal --pg-bin 'C:\Program Files\PostgreSQL\15\bin'
Remove-Item Env:REHEARSAL_ADMIN_DATABASE_URL
```

If PostgreSQL tools are on PATH, omit `--pg-bin`. For this workspace, use the
documented pgAdmin embedded Python executable; the local cluster uses port
55432. The actual run obtained the administrator connection from the existing
ignored local test configuration without printing it or saving it to `.env`.

The runner exports a REPEATABLE READ, READ ONLY snapshot and passes its ID to
`pg_dump --snapshot`. Source fingerprints and backup data therefore describe
the same committed state even while the application remains online. No source
writes are performed. It then creates a **new generated database name** from
`template0`, using the source owner, encoding and locale. Existing target names
are refused. There is no option to overwrite the application database and no
`--clean` operation. Restoration uses `--exit-on-error --single-transaction`.

The archive retains ownership and grants; neither `--no-owner` nor
`--no-privileges` is used. PUBLIC connection access to the new database is
revoked and the application owner/runtime logins are allowed explicitly.
The runner never changes `.env` or starts a notification transport on the copy.
Temporary API sessions and smoke writes affect only the copy and are removed.

Choose a new evidence directory for each run; existing evidence is not
overwritten. Archives and private logs default to `backend/.local/backups`.
Each run retains its restored database for inspection. If a run fails, inspect
the private logs and retained artifacts before attempting another run.

## Verify the saved evidence

- [Rehearsal operations and smoke checks](evidence/backup-restore-20261109/rehearsal.json).
- [Source snapshot](evidence/backup-restore-20261109/source_snapshot.json).
- [Restored snapshot](evidence/backup-restore-20261109/restored_snapshot.json).
- [Restored state after smoke cleanup](evidence/backup-restore-20261109/after_smoke_snapshot.json).
- [Live database after rehearsal](evidence/backup-restore-20261109/live_after_snapshot.json).
- [Independent evidence verification](evidence/backup-restore-20261109/verification.json).

The [offline verifier](../backend/tools/verify_backup_evidence.py) checks that
source, restored and post-smoke snapshots match, checks migration coverage,
totals, audit denials and API/write smoke results, and optionally checks the
private archive's actual size and checksum:

```powershell
python backend/run.py tools.verify_backup_evidence docs/evidence/backup-restore-20261109 --archive backend/.local/backups/spendtrail_restore_20261109_105211_28edad98.dump
```

Omit `--archive` to verify the public artifacts alone; the resulting verification
will explicitly say the local archive was not checked by that invocation.

## Recovery procedure for an existing archive

1. Keep the archive private and confirm its recorded SHA-256 before restoring.
   Identify the backup time and known counts/totals from its evidence bundle.
2. Prepare a new recovery database with matching encoding/locale. Existing
   schema-owner and runtime roles must be available: a database dump does not
   include cluster-role logins/passwords. This rehearsal used the existing
   `spendtrail_app` owner and `spendtrail_runtime` login on the same cluster.
3. Restore as an administrator into that new database, retaining ownership and
   grants. Use explicit target settings and stop on the first error.
4. Compare every row count and fingerprint, reports, migration records,
   constraints, triggers, function ownership and grants with the backup bundle.
   Exercise the restricted login and audit denials; verify the report totals.
5. Use isolated application checks against the recovered copy. Keep its
   notification worker stopped during verification. The source application
   should continue using its existing database during a rehearsal.
6. For a real recovery, switch the API/worker connection settings only after
   verification and a planned service stop, then restart and verify account
   history and reports. Rehearsal completion does not perform this cutover.

For the recorded Windows backup, an administrator can use PostgreSQL tools
with `PGHOST`, `PGPORT`, `PGUSER` and a private `PGPASSFILE`, for example:

```powershell
# Set administrator connection settings for the intended recovery cluster.
# Both roles must already exist. Choose a database name that does not exist.
& 'C:\Program Files\PostgreSQL\15\bin\createdb.exe' --no-password --template=template0 --owner=spendtrail_app --encoding=UTF8 --lc-collate=English_Pakistan.1252 --lc-ctype=English_Pakistan.1252 spendtrail_recovered
& 'C:\Program Files\PostgreSQL\15\bin\pg_restore.exe' --dbname=spendtrail_recovered --exit-on-error --single-transaction --no-password backend/.local/backups/spendtrail_restore_20261109_105211_28edad98.dump
```

The verification performed here is a logical restore on the same PostgreSQL
15 Windows cluster. It does not exercise a new machine, role/password recovery,
cross-platform locale changes, point-in-time recovery, or recovery of server
configuration, Firebase service-account files and application configuration.
Those supporting files need their own private setup/backup process; they are
not contained in the database archive.

The backup/restoration roadmap item is complete. Final device/accessibility
checks, release packaging and the scripted demonstration remain.
