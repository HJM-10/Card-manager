# Manual purchase entry and history

Delivered 7 November 2026.

Signed-in users can open **Home → Account purchases**, or the same screen from **Cards → Account card profiles**. They can record a manual purchase using an active account card, merchant, positive PKR amount, local date/time and online/POS channel. The API receives an exact two-decimal string and a UTC timestamp. History is loaded in pages of 25, supports refresh/retry, and opens details fetched from the transaction endpoint. Archived-card history remains available.

Each save receives a UUID v4 source reference. If delivery is uncertain, the open form retains the reference and entire request, locks its fields and offers Retry save. A definite client rejection unlocks the form for correction. Busy saves prevent repeated submission and back navigation. Session expiry in history, card loading, saving or detail returns control to the sign-in flow. Account records are fetched anew for each opened screen; local demo expenses and statistics remain separate.

## Verification

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub`: 37 passed; the opt-in live API test is skipped in the offline suite.
- Eight purchase widget tests cover exact decimal validation, precision/limits, small-screen forms, correction after rejection, retry after a lost response following a simulated commit, refreshed history, detail retrieval, pagination failure/retry, empty cards and session expiry at each API stage.
- `test/purchase_live_test.dart` passed separately over real HTTP from the Flutter client to FastAPI using an isolated PostgreSQL test schema. It verifies safe duplicate retry, fresh-client sign-in and persisted history/detail, exact PKR amounts, pagination, cross-user access denial and retained history after archival. The temporary schema was removed afterward.
- Backend integration suite: all nine tests passed against PostgreSQL 15, including concurrent retries and transaction/audit/outbox rollback. One existing AnyIO deprecation warning remains.
- `flutter build web --release --no-pub`: successful.

The live HTTP test can be rerun against a dedicated test API using the command in `backend/README.md`. It creates synthetic users and records. Physical-device testing is not included in this milestone. Categories, advanced history filters, imports, budgets and server-backed reports remain on the roadmap.
