# Milestone 01 — accounts and persistent card profiles

Delivered on 4 November 2026 as the first usable slice of the SpendTrail roadmap.

## Result

The default Flutter launch now opens SpendTrail registration/login. A signed-in user can create, list, edit and archive fictional card profiles through FastAPI and PostgreSQL. Starting a fresh client and signing in again restores the saved profiles. Empty, loading, validation, server-error and retry states are included. Sessions expire after 12 hours and logout revokes the current token. Session tokens are deliberately held in memory, so app restart requires sign-in.

The new flow uses the proposal's coral/navy/cream palette and PKR context. It does not show a fabricated balance. The earlier Magpie demo remains available with `LEGACY_DEMO=true` while transaction and reporting screens are migrated in later milestones.

## Evidence

- `flutter analyze`: no issues.
- `flutter test`: all 26 tests passed, including two new account/card flow tests.
- Backend PostgreSQL integration suite: all six tests passed against a real isolated PostgreSQL 15 instance.
- Integration coverage: fresh-client sign-in and persistence, two-user isolation, update/archive, token expiry/revocation, validation, duplicate accounts/cards, concurrent duplicate card requests, migration reruns and rollback.
- `flutter build web --release`: successful.
- Live HTTP smoke check: registered a synthetic user and saved a card through the running API, restarted the isolated PostgreSQL instance, then signed in using a fresh HTTP client and retrieved the same card successfully.

Flutter flow tests use a controlled HTTP transport. Backend integration tests use FastAPI's test client with real PostgreSQL. Physical-device interaction, Android/iOS packaging and screen-reader testing were not performed for this milestone. One dependency deprecation warning occurs in the backend test client's AnyIO integration; the six tests pass.

## Local setup and remaining work

See [backend/README.md](../backend/README.md) for setup, API contract and the initial data dictionary/ER diagram. A dedicated local cluster and application login were configured for this workspace. Passwords, packages and database files remain ignored by Git.

The complete requirements/ER design, transaction model, CSV contract and shared repository expansion remain open. Transactions, categories, budgets, imports, audit/outbox and notifications are not delivered by this milestone. The six-week roadmap is not marked complete.
