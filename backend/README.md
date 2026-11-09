# SpendTrail backend

The API provides registration/login, revocable 12-hour bearer sessions, optional 30-day biometric login credentials, user-owned fictional card profiles, and manual PKR purchase recording and history. PostgreSQL is the persistent store. Access tokens stay in client memory. On Android, opt-in fingerprint login stores a separate credential encrypted with an authentication-bound Keystore key. Passwords use Argon2, and the database stores only hashes of session credentials.

## Standard local setup

Use Python 3.11+ and PostgreSQL 15+. Create an empty `spendtrail` database and a dedicated schema-owner login (`spendtrail_owner` in the example). Do not use an existing production database. The API and worker use a separate restricted login; the owner is used for migrations only.

From the repository root, in PowerShell:

```powershell
py -m venv backend/.venv
& backend/.venv/Scripts/python.exe -m pip install -r backend/requirements.txt
Copy-Item backend/.env.example backend/.env
# Set MIGRATION_DATABASE_URL in backend/.env to the schema-owner connection.
Push-Location backend
& .venv/Scripts/python.exe -m app.db
# Provision with an administrator able to create roles and grant table access.
# If the migration account has those privileges, this temporary setting is optional.
$env:PROVISION_DATABASE_URL='postgresql://ADMIN:PASSWORD@localhost:5432/spendtrail'
& .venv/Scripts/python.exe -m app.db_access --configure-local
Remove-Item Env:PROVISION_DATABASE_URL -ErrorAction SilentlyContinue
& .venv/Scripts/python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
Pop-Location
```

Migrations are explicit, transactional and versioned; API startup never silently changes the schema. Re-running the migration command skips applied files.

### Audit-history protection (migration 009)

`DATABASE_URL` is for the API/worker's `spendtrail_runtime` login.
`MIGRATION_DATABASE_URL` is for the separate schema owner. For legacy setups,
the migration command falls back to `DATABASE_URL` when no migration URL is set;
after hardening, always retain the owner URL for future migrations.

Apply migration 009, then run `app.db_access --configure-local` using the setup
above. Provisioning generates a password, saves the two connections in ignored
`backend/.env` without printing credentials, and grants only known application
operations. An optional temporary `PROVISION_DATABASE_URL` lets an administrator
create the login when the schema owner lacks `CREATEROLE`; it is not saved.
The administrator must target the same database as the migration URL.
Restart the API and notification worker afterward. Re-running provisioning
rotates the runtime password and reapplies grants, so restart both services again.
`--role` and `--schema` support isolated/custom installations; the defaults are
`spendtrail_runtime` and `public`.

The runtime role can read audit history but cannot insert, update, delete,
truncate, add audit triggers, change the creation trigger, or assume the owner
role. It owns no application objects and has no administrative privileges or
role memberships. Only the creation trigger writes audit/outbox rows through
a `SECURITY DEFINER` function owned by the migration owner. The function uses
schema-qualified targets, a fixed search path, and no PUBLIC execution grant.
Temporary shadow tables cannot redirect its writes. Audit, transaction and
outbox writes still commit or roll back together. The worker retains the
outbox update permission needed for dispatch.

Provisioning revokes PUBLIC schema creation in the selected application schema;
use a dedicated SpendTrail database. New tables receive no automatic runtime
grants: update the explicit grant list when future migrations need new access.
Schema owners and administrators remain trusted maintenance identities; this
restriction protects against changes made through the runtime database login.
See [audit verification](../docs/MILESTONE_09.md) for tests and local evidence.

Start Flutter in a second terminal:

```powershell
flutter run -d chrome --web-port 5173 --dart-define=API_BASE_URL=http://localhost:8000
```

For the Android emulator, use `--dart-define=API_BASE_URL=http://10.0.2.2:8000`. Debug Android builds permit local HTTP. Release builds require an HTTPS API. For a USB-connected Android phone, run `adb reverse tcp:8000 tcp:8000` and build with `--dart-define=API_BASE_URL=http://127.0.0.1:8000`. Web origins must be explicitly listed in `CORS_ORIGINS`.

The **Appearance** menu on sign-in and Home offers System, Light and Dark. The app saves the choice on the device. After sign-in, **Cards → Account card profiles** opens the PostgreSQL-backed wallet profiles.

**Home → Account purchases** opens PostgreSQL-backed purchase entry, history and detail. It is also available from Account card profiles. Create an active account card first. History includes purchases on archived cards; archived cards cannot be used for new purchases. The form uses UTC timestamps and decimal strings, retaining its UUID and complete payload for ambiguous-save retries. Local demo expenses and statistics remain separate.

## This Windows workspace

The machine has pgAdmin's embedded Python rather than a normal Python installation. Packages were installed under ignored `backend/.local/packages`. The optional `run.py` launcher adds that directory to the Python path.

An isolated PostgreSQL cluster was created under ignored `backend/.local/pgdata`, bound to `127.0.0.1:55432`. Its application database is configured in the ignored `.env`; credentials must never be committed. It is independent of any pre-existing PostgreSQL cluster.

```powershell
& 'C:\Program Files\PostgreSQL\15\bin\pg_ctl.exe' -D backend/.local/pgdata -l backend/.local/postgres.log -o '-h 127.0.0.1 -p 55432' -w start
& 'C:\Program Files\PostgreSQL\15\pgAdmin 4\python\python.exe' backend/run.py app.db
& 'C:\Program Files\PostgreSQL\15\pgAdmin 4\python\python.exe' backend/run.py uvicorn app.main:app --host 127.0.0.1 --port 8000
# Stop the API with Ctrl+C, then stop PostgreSQL when finished:
& 'C:\Program Files\PostgreSQL\15\bin\pg_ctl.exe' -D backend/.local/pgdata -w stop
```

If the cluster is already running, skip the start command. This machine-specific setup is not included in Git; other machines should use the standard setup above.

## API contract

Interactive documentation is available at `/docs` while the API runs.

| Method/path | Input / behavior |
| --- | --- |
| `GET /health` | Confirms database connectivity |
| `POST /auth/register` | `{email, password, name}` → session token and public user; 201 |
| `POST /auth/login` | `{email, password}` → new session token and public user |
| `GET /auth/me` | Authenticated user's ID, email and name |
| `DELETE /auth/session` | Revokes the current session; 204 |
| `POST /auth/biometric` | Authenticated opt-in; creates/replaces a credential for this session and returns `refresh_token` plus `expires_at`; 201 |
| `POST /auth/biometric/refresh` | `{refresh_token}` returns a fresh access token and its associated user; no password needed |
| `DELETE /auth/biometric` | Disables the current session's saved login, revokes other associated access sessions, and preserves the current access; 204 |
| `DELETE /auth/access` | Locks this instance by revoking only its access token; preserves the biometric credential; 204 |
| `GET /cards` | Current user's active card profiles only |
| `GET /cards?include_archived=true` | Current user's active and archived profiles for history filters |
| `GET /reports/monthly?month=YYYY-MM` | Exact monthly account spending, categories, cards and all-card budget comparisons; optional owned `card_id` filters spending |
| `PUT /budgets/{month}/{category_id}` | `{amount: "1500.00"}` sets or replaces the owned category/month limit; 200, stable budget ID on retries |
| `DELETE /budgets/{month}/{category_id}` | Removes only that owned category's monthly limit; idempotent 204 |
| `GET /categories` | Current user's saved categories |
| `POST /categories` | `{name}` creates a user-owned category; 201, or 409 for a case-insensitive duplicate |
| `POST /cards` | `{label, network, last4, expiry_month, expiry_year}`; 201 |
| `PATCH /cards/{id}` | Replaces the editable fields using the same complete body |
| `DELETE /cards/{id}` | Archives an owned active card; 204 |
| `POST /transactions` | Records a manual PKR purchase on an owned active card; 201, or 200 for a matching retry |
| `GET /transactions` | Current user's purchase history, newest first. Optional `limit` (1–100, default 25) and `offset` (default 0) |
| `GET /transactions/{id}` | Current user's purchase detail; 404 for a missing or inaccessible record |
| `PATCH /transactions/{id}/category` | `{category_id: UUID or null}` changes or clears the owned purchase's category, including on archived cards |
| `POST /imports/preview` | `{card_id, file_name, csv_text}` validates a UTF-8 CSV and saves its row preview without creating purchases |
| `GET /imports/{id}` | Current user's saved preview or confirmed import receipt |
| `POST /imports/{id}/confirm` | `{preview_token}` atomically creates valid new CSV purchases and returns an idempotent receipt |

Protected endpoints require `Authorization: Bearer <token>`. Unknown body fields are rejected. `network` is `visa` or `mastercard`; `last4` is four ASCII digits; expiry must be current/future, with year at most 2100. Names and labels are trimmed and limited to 50 characters; passwords preserve whitespace and contain 10–128 characters. Email uniqueness is case insensitive. Duplicate profile identity `(user_id, network, last4)` returns 409, including archived profiles. Editing another user's card returns 404. No balances are inferred from a card profile.

A manual purchase uses the following JSON body. Substitute an active card ID from `GET /cards` and generate a new UUID for each purchase.

```json
{
  "card_id": "dc720429-5a62-4501-896d-21241ab90987",
  "merchant": "Corner Market",
  "amount": "1250.05",
  "occurred_at": "2026-11-05T10:30:00+05:00",
  "channel": "pos",
  "source_reference": "387cf0f9-6462-4f64-ab50-6c57f5658587"
}
```

Send a positive amount as a string with exactly two fractional digits and at most twelve whole digits. Use an ISO 8601 timestamp with a UTC offset or `Z` and a UTC year from 2000 through 2100. Merchant names are trimmed and limited to 100 characters. The channel is `online` or `pos`. Manual entries are approved purchases in PKR. Responses add `id`, `currency`, `source`, `kind` and `status`, and preserve the amount as a decimal string.

Reuse the same request body and reference if delivery is uncertain. Reusing a card's reference with different purchase values returns 409. Archived cards keep their history and accept matching retries for existing purchases.

Purchases accept an optional `category_id` owned by the signed-in user. Responses include nullable `category_id` and `category` (name). Existing records remain uncategorized after migration. Registration creates six account-specific starter categories: Groceries, Food, Transport, Shopping, Bills and Other. Category names are trimmed, nonblank and limited to 50 characters; uniqueness is case insensitive within each account. Categories can be added and assigned; rename/deletion is not included.

History filters combine with `limit` and `offset`: `search` is a case-insensitive literal merchant substring (maximum 100 characters); `card_id` includes archived-card history; `category_id` selects one category; `uncategorized=true` selects no category. Supplying both category options is rejected. `occurred_from` is inclusive and `occurred_before` is exclusive; both require ISO 8601 timestamps with a UTC offset. A reversed or empty interval is rejected. The app translates an inclusive range of local calendar days into these exact UTC boundaries. Foreign account IDs return no history; category assignments to foreign IDs return 404.

The initial category is stored independently from the editable category. Retrying the original purchase creation after recategorization returns the current record without undoing the category change or creating another transaction/event. The entire original creation body, including its initial category, must be reused.

## Initial data dictionary

```mermaid
erDiagram
    USERS ||--o{ SESSIONS : authenticates
    USERS ||--o{ CARD_PROFILES : owns
    USERS {
        uuid id PK
        text email UK
        text name
        text password_hash
        timestamptz created_at
    }
    SESSIONS {
        text token_hash PK
        uuid user_id FK
        timestamptz expires_at
        timestamptz created_at
    }
    CARD_PROFILES {
        uuid id PK
        uuid user_id FK
        text label
        text network
        text last4
        integer expiry_month
        integer expiry_year
        boolean archived
        timestamptz created_at
    }
```

SQL migration `001_accounts_cards.sql` defines the checks, foreign keys and unique constraints. Cards are archived rather than deleted so future history can retain references. Registration and its initial session commit together. Database constraints arbitrate concurrent duplicate requests.

Migration `002_manual_purchases.sql` adds user-owned merchants and transactions. Composite foreign keys require the card and merchant to belong to the transaction owner. An insert trigger writes one creation audit row and one outbox row in the same database transaction as the purchase.

Migration `003_categories_history.sql` adds user-owned categories, starter categories for existing users, nullable current/original category references, composite ownership foreign keys, an ownership trigger and an index for category history. The existing purchases, amounts, audit events and outbox events are preserved. Run migrations before starting the updated API.

Migration `004_biometric_sessions.sql` adds hashed, user-owned credentials with an absolute 30-day expiry, revocation flag and ownership-enforced links from access sessions. Renewal issues access for up to 12 hours, capped by the credential expiry; it does not extend the 30-day window. Sign-out revokes the linked credential and all its derived accesses. Disabling biometric login detaches and preserves the current access, while other derived accesses become invalid. Separate device credentials are unaffected. Refresh and revocation serialize on the credential row so a concurrent refresh cannot restore a revoked login. Revoked rows remain for later cleanup. Credential responses use `Cache-Control: no-store`.

Migration `005_csv_imports.sql` adds user-owned ImportBatch records with file fingerprints, preview tokens, bounded row outcomes and confirmation receipts. A composite transaction-to-batch foreign key enforces owner/card identity. Manual and CSV purchases use the same validation/write helper in `app/purchases.py`, including audit/outbox triggers. The source is `csv` for imported purchases and `manual` for manual entry.

See [CSV_IMPORT.md](../docs/CSV_IMPORT.md) for exact columns, byte/row limits, duplicates and the all-or-nothing policy. Preview/confirm/get require a bearer session. New previews return 200 and include `id`, `preview_token`, `rows`, `ready_count`, `duplicate_count`, `error_count`, `total_amount` and `can_confirm`. Each row includes its record number, status/message and bounded purchase fields. Confirmation returns 200 with `status=confirmed`, `imported_count`, `duplicate_count` and the exact imported `total_amount`; retries return the same receipt. Any invalid row returns 422 on confirmation. A stale preview or newly conflicting reference returns 409. Foreign imports and unavailable active cards return 404. A new preview of an unconfirmed file replaces its preview token; previously confirmed files keep their receipt. Records that became matching duplicates since preview are safely skipped. An audit/outbox failure rolls back all new purchases and leaves the batch unconfirmed.

The backend trusts possession of the opaque credential; Android enforces biometric access to its encrypted local copy. It receives no biometric image/template or saved password. Release traffic requires HTTPS; local HTTP/USB remains the development setup. See `docs/MILESTONE_04.md` for device behavior and checks.

## Verification

Set `TEST_DATABASE_URL` to a dedicated PostgreSQL test database using a test administrator that can create schemas and create/clean up roles. Tests create a unique schema per case and drop only that schema afterward; audit tests also create and remove randomly named runtime roles. No existing tables are truncated.

```powershell
$env:TEST_DATABASE_URL='postgresql://USER:PASSWORD@localhost:5432/spendtrail_test'
Push-Location backend
& .venv/Scripts/python.exe -m pytest tests -q
Pop-Location
flutter analyze
flutter test
flutter build web --release
```

To exercise the actual Flutter HTTP client against a dedicated running test API (creates synthetic accounts and purchases):

```powershell
flutter test --no-pub --dart-define=LIVE_API_URL=http://127.0.0.1:8000 test/purchase_live_test.dart
```

The live test checks save/retry, fresh-client login/history/detail, exact amounts, combined search/card/category/date filters, custom categories, recategorization/replay, pagination, user isolation and archived-card history. It is skipped in ordinary offline test runs. Widget tests in `test/purchases_test.dart` separately cover entry, validation, category creation/change/clear, filter controls/reset, pagination/retry, small screens and expired sessions.

For embedded Python, use `backend/run.py pytest backend/tests -q` instead. The backend tests cover fresh-session persistence, two-user isolation, card archival, validation, concurrent retries, migration reruns and rollback when a purchase's outbox write fails. Flutter tests cover the registration/card/login journey and recoverable authentication errors.

## Remaining scope

### Database index experiments

The isolated 10,000/100,000-transaction index experiments are complete, including
an independent repeat, actual plans/timings/buffers/index sizes and offline
evidence verification. See [database evaluation](../docs/DATABASE_EVALUATION.md)
for findings, raw artifacts and reproduction commands. The candidates were
limited to disposable schemas in the test database; application indexes were
not changed. Run `tools.index_benchmarks` with an explicit test connection and
`tools.verify_index_evidence` to validate saved results.

The transaction notification APIs and separate retrying FCM worker are
implemented and verified with actual Firebase acceptance and phone receipt,
including cold-start transaction opening after fingerprint sign-in. See
[NOTIFICATIONS.md](../docs/NOTIFICATIONS.md) for the setup, API contract,
retry/lease behavior and distinct acceptance/receipt evidence. Migration 008
must be applied before the updated API is started. Worker credentials are kept
outside the app and repository.

### Payment simulation (migration 006)

Run the migration command before using the updated API. It preserves existing
transactions, expands type/status/source constraints, adds owned original-purchase
references and enforces immutable creation values plus a cumulative refund limit.
Current categories remain editable. `transaction_spending` exposes exact signed
`spending_amount`: approved purchase positive, approved refund negative, decline
zero. This is a foundation for the pending report/budget APIs.

- `POST /simulations/purchases`: the manual purchase body plus required
  `status` (`approved` or `declined`). Source is `simulation`.
- `POST /transactions/{id}/refunds`: `{amount, occurred_at, source_reference}`.
  Amount and timestamp follow the manual format. Source is `simulation`, kind
  `refund`, status `approved`; card, merchant, channel and initial category are
  inherited from the original owned approved purchase. Response includes
  `original_purchase_id` (null for purchases).
- Both routes return 201 for creation and 200 for matching retries. Conflicting
  references and excessive refunds return 409. Invalid refund targets or a refund
  before its purchase return 422; foreign/missing targets return 404.
- Archived cards allow refunds and matching retries. New simulated purchases
  require an active card. Refunds cannot themselves be refunded.
- `GET /transactions` additionally accepts combined `status=approved|declined`
  and `kind=purchase|refund` filters before pagination. History now includes all
  transaction kinds, despite the retained Account purchases screen title.
- Each creation queues one audit/outbox pair atomically, including declines.
  Notification delivery is pending. API card locks and database original-purchase
  locks prevent concurrent over-refunding; retries reuse the frozen request.

See [design and fixed acceptance examples](../docs/DESIGN.md) and
[verification evidence](../docs/MILESTONE_06.md).

Account recovery and production deployment are future work. Migration 009 and runtime-role provisioning restrict audit writes; see the setup above. Signed-in Statistics now uses account spending and budgets; explicit legacy demo mode retains local statistics.

### Monthly budgets and reports (migration 007)

Run migrations before loading the updated Statistics tab. Migration 007 adds
owned monthly category budgets, a unique owner/category/month constraint and
`monthly_category_spending`, a SQL aggregate view over exact signed transactions.
Reporting uses Asia/Karachi calendar months independently of the server's local
timezone. Refunds affect their own occurrence month and current category;
declines contribute zero. Archived cards remain included.

`month` must be `YYYY-MM`, from 2000-01 through 2100-12. Budget `amount` is a
positive decimal string with exactly two fractional digits and at most twelve
whole digits. Invalid months/amounts/unknown body fields return 422. Foreign or
missing categories/cards return 404. Bearer authentication is required.

PUT upserts one limit for the account/category/month. Retrying does not add a
second budget; simultaneous updates serialize on its unique constraint, with
the last committed update taking effect. DELETE is idempotent and changes no
transactions. Limits do not roll over or prevent transaction recording.

The monthly report returns `month`, `timezone`, `currency`, selected `card_id`,
exact string `spent`, `purchases`, `refunds`, `transaction_count`, `categories`,
`cards` and `budgets`. Category rows include zero-spend owned categories plus
Uncategorized (null ID). Card rows include active/archived profiles and their
totals. Record counts include declines. Monetary values remain strings.

Optional `card_id` filters headline/category totals. **Budgets always compare
all cards**, identified by `budget_scope=all_cards`. Each budget contains
`category_id`, `category`, `amount`, `spent`, `remaining`, signed `percent`
(two decimals, half-up) and `over_budget`. Negative net spending is retained,
including negative percentages and remaining funds greater than the limit.
One repeatable-read snapshot keeps each response's components aligned.

See [design examples](../docs/DESIGN.md) and
[verification evidence](../docs/MILESTONE_07.md).

Implementation references: [FastAPI authentication and password hashing](https://fastapi.tiangolo.com/tutorial/security/oauth2-jwt/) and [Psycopg transaction management](https://www.psycopg.org/psycopg3/docs/basic/transactions.html).
