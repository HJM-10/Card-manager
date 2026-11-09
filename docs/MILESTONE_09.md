# Milestone 9 — audit-history protection

Verified on 9 November 2026 against the workspace's PostgreSQL 15 instance.

## Delivered behavior

The API and notification worker now use the dedicated `spendtrail_runtime`
database login. The original schema-owning login is retained only through
`MIGRATION_DATABASE_URL` for explicit migrations. A temporary administrator
connection can provision roles when the schema owner lacks `CREATEROLE`.
No credentials are committed or printed by the provisioning tool.

Migration `009_audit_protection.sql` makes `record_transaction_created()` a
`SECURITY DEFINER` trigger function, retaining its migration-owner identity.
It binds both insert targets to the application schema at migration time,
sets `search_path` to `pg_catalog, pg_temp`, and revokes PUBLIC execution.
Purchases still create audit and outbox rows inside the same transaction.

`app.db_access` grants audit SELECT only. The runtime login cannot directly
insert, update, delete or truncate audit rows, add audit triggers, disable the
transaction trigger, replace its function, delete transactions, or edit the
migration ledger. It has no object ownership, administrative attributes or
role memberships. Provisioning refuses an existing owner/admin/member role.
PUBLIC creation in the application schema is revoked. The worker retains
outbox SELECT/UPDATE; only the creation trigger inserts outbox rows.

Schema owners and administrators remain trusted maintenance identities.
This milestone restricts the runtime database login; it does not prevent
an administrator from deliberately maintaining the database.

## Automated evidence

Final full backend run: **81 passed in 148.64 seconds**, with one dependency
deprecation warning from Starlette/AnyIO. No tests failed or were skipped.

`backend/tests/test_audit_protection.py` contains 24 focused checks using
actual PostgreSQL runtime logins, not mocked permission errors:

- Fifteen denied operations cover audit writes, truncation and cascading
  truncation, trigger disabling, function replacement/direct execution,
  replication-role bypass, schema creation, transaction deletion, direct
  outbox insertion and migration-ledger changes.
- Registration, card creation, purchases, category edits, CSV imports,
  declined simulations, refunds, budgets, reports, history and notification
  worker processing work with restricted privileges.
- Concurrent matching requests return one 201 and one 200, with exactly one
  new transaction/audit/outbox triple.
- An injected outbox constraint failure leaves zero transaction, merchant,
  audit or outbox rows; removing the fault permits a successful retry.
- Temporary audit/outbox shadow tables and a caller-controlled search path
  cannot redirect the trigger's writes.
- Assuming the migration owner fails. Provisioning rejects owner roles and
  role memberships. Reapplying the audit migration preserves existing rows.
- Provisioning with either a sufficiently privileged migration connection
  or a separate administrator produces working credentials. Reprovisioning
  rotates credentials and preserves restrictions without printing passwords.

Run with an administrator on a dedicated test database:

```powershell
$env:TEST_DATABASE_URL='postgresql://TEST_ADMIN:PASSWORD@localhost:5432/spendtrail_test'
Push-Location backend
python -m pytest tests -q
Pop-Location
```

The workspace uses its documented embedded Python launcher and ignored
`backend/.local/test.env` instead of a standard virtual environment.

## Local application database evidence

Before switching runtime credentials, a custom-format backup was created at
`backend/.local/before-audit-protection-20261109-100244.dump`.
This is a precautionary backup; a restoration rehearsal remains a separate
roadmap item.

After applying migration 009 and configuring the new runtime login:

| Check | Observed result |
| --- | --- |
| Runtime database identity | `spendtrail_runtime` |
| Existing transaction count | 9, unchanged |
| Existing audit count | 9, unchanged |
| Existing audit IDs/timestamps | Exact before/after match |
| Net spending | PKR 18,998.55, unchanged |
| Direct audit INSERT/UPDATE/DELETE/TRUNCATE attempts | All denied |
| Disable creation trigger attempt | Denied |
| API after restart | `/health` returned 200 and `status=ok` |
| Notification worker | Restarted with the new runtime settings; no startup error |
| Migration command after credential split | Succeeded; applied migrations skipped |

The API and worker were restarted after configuration. Runtime credentials
and the retained migration connection live in ignored `backend/.env`.
Machine-readable local evidence is in ignored
`backend/.local/audit-protection-evidence.json`.

The audit-protection roadmap item is complete. Index experiments, full
concurrency/rollback evidence, backup restoration and release checks remain
separate work; this milestone does not mark those items complete.
