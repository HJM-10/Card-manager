# SpendTrail backend

The API provides registration/login, revocable 12-hour bearer sessions, user-owned fictional card profiles, and manual PKR purchase recording and history. PostgreSQL is the persistent store. Tokens stay in client memory, so users sign in again after an app restart. Passwords use Argon2, and the database stores session token hashes.

## Standard local setup

Use Python 3.11+ and PostgreSQL 15+. Create an empty `spendtrail` database and a dedicated login role with access to create its initial schema. Do not use an existing production database.

From the repository root, in PowerShell:

```powershell
py -m venv backend/.venv
& backend/.venv/Scripts/python.exe -m pip install -r backend/requirements.txt
Copy-Item backend/.env.example backend/.env
# Set DATABASE_URL in backend/.env to your local database connection.
Push-Location backend
& .venv/Scripts/python.exe -m app.db
& .venv/Scripts/python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
Pop-Location
```

Migrations are explicit, transactional and versioned; API startup never silently changes the schema. Re-running the migration command skips applied files.

Start Flutter in a second terminal:

```powershell
flutter run -d chrome --web-port 5173 --dart-define=SPENDTRAIL_PREVIEW=true --dart-define=API_BASE_URL=http://localhost:8000
```

For the Android emulator, use the same preview flag with `--dart-define=API_BASE_URL=http://10.0.2.2:8000`. Debug Android builds permit local HTTP. Release builds require an HTTPS API. Physical devices need a reachable server address; development binding/firewall changes must be configured separately. Web origins must be explicitly listed in `CORS_ORIGINS`.

The **Appearance** menu on the sign-in screen and in the signed-in wallet offers System, Light and Dark. The app saves the choice on the device.

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
| `GET /cards` | Current user's active card profiles only |
| `POST /cards` | `{label, network, last4, expiry_month, expiry_year}`; 201 |
| `PATCH /cards/{id}` | Replaces the editable fields using the same complete body |
| `DELETE /cards/{id}` | Archives an owned active card; 204 |
| `POST /transactions` | Records a manual PKR purchase on an owned active card; 201, or 200 for a matching retry |
| `GET /transactions` | Current user's purchase history, newest first. Optional `limit` (1–100, default 25) and `offset` (default 0) |
| `GET /transactions/{id}` | Current user's purchase detail; 404 for a missing or inaccessible record |

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

## Verification

Set `TEST_DATABASE_URL` to a test PostgreSQL database whose user can create schemas. Tests create a unique schema per case and drop only that schema afterward; no existing tables are truncated.

```powershell
$env:TEST_DATABASE_URL='postgresql://USER:PASSWORD@localhost:5432/spendtrail_test'
Push-Location backend
& .venv/Scripts/python.exe -m pytest tests -q
Pop-Location
flutter analyze
flutter test
flutter build web --release
```

For embedded Python, use `backend/run.py pytest backend/tests -q` instead. The backend tests cover fresh-session persistence, two-user isolation, card archival, validation, concurrent retries, migration reruns and rollback when a purchase's outbox write fails. Flutter tests cover the registration/card/login journey and recoverable authentication errors.

## Remaining scope

Flutter purchase entry and history, categories, budgets, imports, simulated payments, notification dispatch, account recovery and production deployment are future work. A separate runtime database role with restricted audit privileges is also pending.

Implementation references: [FastAPI authentication and password hashing](https://fastapi.tiangolo.com/tutorial/security/oauth2-jwt/) and [Psycopg transaction management](https://www.psycopg.org/psycopg3/docs/basic/transactions.html).
