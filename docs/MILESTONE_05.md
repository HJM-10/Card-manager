# CSV purchase imports

Implemented on 7 November 2026 under **Account purchases → Import CSV**. The login page's “Fictional card profiles · PKR” note was also removed as requested.

The user selects one active card and a CSV file through the platform file picker, or previews the bundled sample. A saved preview shows every row's status, validation errors, duplicates and exact new-purchase total. Confirmation is blocked when any row is invalid/conflicting. A successful confirmation saves all new transactions, audit records, outbox events and the batch receipt atomically; matching duplicates are skipped. A failed/uncertain confirmation retains its batch and preview token for safe retry. A definite stale-preview failure requires re-previewing the retained file. Successful imports appear in the existing searchable/filterable history and details.

The [CSV contract](CSV_IMPORT.md) specifies UTF-8, a 256 KiB/500-record limit, required stable references, exact decimal amounts, explicit timezone timestamps and optional existing account category names. The system does not infer duplicate identity from amounts or merchant names, and does not merge CSV references with manual-entry references. Reordering/renaming a file does not defeat reference-level duplicate checks. Current category changes do not invalidate a matching original import.

Migration 005 adds ImportBatch persistence and ownership-enforced transaction references. Both entry sources now share `app/purchases.py` so ownership, card locking, validation and event writes follow the same rules. File bytes are read/validated before upload; the server repeats limits and validation. Only bounded row fields/results and batch metadata are retained, not the raw uploaded CSV.

## Verification

- Flutter suite: 54 passed; the opt-in live test is skipped during the offline suite. Tests cover file preview before saving, lost-response confirmation retry, error blocking, invalid UTF-8, file limits, picker cancellation, sample selection, stale preview/session recovery, and existing account/category/fingerprint flows.
- PostgreSQL suite: 28 passed. CSV coverage includes quoted Unicode fields/BOM/newlines, malformed headers, limits, exact totals, original-category duplicate comparison, per-account access, stale previews, archived cards, concurrent overlapping batches, late reference conflicts, composite batch ownership and atomic rollback on the second row's outbox failure.
- A full 500-row import was confirmed and retried, producing exactly 500 purchases and an exact PKR 500.00 total.
- The live Flutter HTTP test passed separately against a temporary PostgreSQL schema, including preview without insertion, confirmation, history persistence, Unicode, repeated confirmation/re-upload and foreign-batch access denial. The schema was removed afterward.
- Static analysis passed without issues; Android debug and web release builds succeeded. The local database was backed up before migration and existing purchase identifiers, amounts, dates and owners were verified unchanged.
- On the connected Samsung SM-A725F, the native file picker selected `SpendTrail-sample.csv` from Downloads. Preview showed 3 ready, 0 duplicates, 0 errors and PKR 5,649.50. Confirmation added three purchases; selecting the same file again returned the existing receipt. The saved sample references were checked for uniqueness afterward.

The database suite retains the existing AnyIO deprecation warning. Declines/refunds, server reports and budgets remain later roadmap work.
