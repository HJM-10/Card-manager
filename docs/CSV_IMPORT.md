# CSV purchase import contract

Select one active account card per file. Imports record approved PKR purchases; they do not move money.

- File: `.csv`, UTF-8 (optional BOM), comma-separated, at most 256 KiB and 500 nonblank data records. Standard quoted fields and CRLF/LF newlines are accepted.
- Required columns: `reference,merchant,amount,occurred_at,channel`. Optional column: `category`. Column order is flexible; header names are trimmed and case insensitive. Missing, duplicate or unknown columns are rejected.
- `reference`: a stable receipt/statement identifier, 1–100 characters. Reuse it for the same transaction; do not generate a fresh reference when retrying an import.
- `merchant`: nonblank, at most 100 characters.
- `amount`: a positive PKR decimal with exactly two fractional digits, no thousands separators and at most 12 whole digits.
- `occurred_at`: ISO 8601 with a UTC offset or `Z`, from UTC year 2000 through 2100. Example: `2026-11-07T14:30:00+05:00`.
- `channel`: `online` or `pos`.
- `category`: an existing category name from the current account, matched case insensitively. Empty/omitted means Uncategorized. Create custom categories in the app before importing.

## Preview and confirmation

Selecting a file only creates a saved preview. The preview lists every record as Ready, Duplicate or Error and shows the exact total for new purchases. Confirmation is blocked while any record is invalid or conflicts with an existing reference.

Duplicate identity is `(card, csv source, reference)`, independent of filename and row order. A matching reference is skipped only when merchant, amount, timestamp, channel and original category agree. Later recategorization does not change duplicate identity. Reusing a reference with different purchase values is an error. Identical repeated references inside a file are skipped; conflicting ones block the batch.

Confirmation creates all new transactions, creation audit rows and outbox events, and marks the batch confirmed in one database transaction. Any failure rolls everything back. Matching duplicates are skipped. Concurrent imports on one card serialize; retrying confirmation or re-uploading a confirmed file returns its original receipt without inserting another transaction/event. References from manual entry are a separate source; CSV does not guess whether a manual purchase represents the same receipt.

The app retains the batch and preview token while an uncertain confirmation is retried. The server rechecks ownership, active-card state, categories and references during confirmation. Files cannot import into another user's card/category. Existing cards, purchases and balances are not replaced.

Only bounded row data, validation results, file name/hash and batch metadata are stored; the original raw CSV file is not retained by the API. No bank credentials, full card numbers or CVVs belong in these files.
