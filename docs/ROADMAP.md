# SpendTrail project roadmap

Created: 4 November 2026. The account/card slice and the first manual purchase endpoints are implemented. See [account/card evidence](MILESTONE_01.md) and the [purchase API contract](../backend/README.md).

## Goal and scope

Turn the existing Flutter demo into **SpendTrail — Personal Spending and Card Transaction Management System**, following the semester proposal scope summarized below.

Users register, manage fictional card profiles, record and import transactions, search their history, categorize spending, set monthly budgets, review reports and receive transaction notifications. The semester prototype uses synthetic PKR data and simulated payments.

Manual entry, controlled CSV import and simulation are record sources. Online and point of sale are transaction channels. Adding a card does not capture bank activity. Live payments, bank feeds and production NFC provisioning are future work; actual NFC hardware integration is optional. Multiple currencies are outside this implementation.

## Starting point

Source inspection shows an existing Magpie Flutter/Riverpod application with:

- Animated splash, dashboard, card stack and add-card flow.
- Local card metadata, expense editing, searching/filtering and statistics.
- Profile preferences and simulated Send, Request and TopUp actions.
- Shared-preferences persistence and automated tests.

At roadmap creation there was no backend or database implementation in the inspected application source. The first account/card slice now lives in `backend/` and `lib/features/account/`. Historical Magpie checks are documented in `docs/IMPLEMENTATION.md`. Existing demo screens remain reusable foundations for the remaining SpendTrail features.

## Build approach

- Keep Flutter and Riverpod. Retain useful interface components and animations.
- Add a Python FastAPI backend and PostgreSQL database, with migrations and pgAdmin inspection.
- Make the authenticated API the source of persistent application data. Keep database credentials on the server.
- Replace demo providers incrementally through repositories, completing one usable flow at a time.
- Use PKR consistently. Store server amounts as `NUMERIC(14,2)` and exchange decimal amounts without floating-point rounding; retain exact minor units in client calculations.
- Treat the original Magpie proposal as design history. This roadmap governs the SpendTrail build.

## Six-week delivery plan

Weeks are sequential working blocks, not promised calendar dates. Week 4 has the largest scope; begin its shared transaction/outbox foundations in week 2 and its integration path in week 3.

| Milestone | Work | Completion evidence |
| --- | --- | --- |
| **1 · Requirements and design — week 1** | Run the current app/checks; map existing screens; define SpendTrail journeys; produce ER diagram, data dictionary, API contract, CSV contract and acceptance examples. Define PKR, transaction statuses, refund rules, reporting month/timezone and notification behavior. | Reviewed contracts and schema design; baseline results recorded; each feature has a testable acceptance condition. |
| **2 · Database foundation — week 2** | Create backend structure, configuration, migrations, constraints and synthetic seed data. Add ownership enforcement, audit triggers, report views and notification outbox schema. | A fresh database can be created and seeded; invalid references, cross-user categories and duplicates are rejected; rollback leaves no partial writes. |
| **3 · First integrated application — week 3** | Implement registration/login, session handling, authenticated card APIs and Flutter repositories. Apply SpendTrail branding and PKR presentation. Integrate the shared transaction creation path. | A new user registers, logs in, saves a fictional card and sees it after restart. Another user cannot read or alter it. A recorded purchase persists and appears in history. |
| **4 · Complete spending workflows — week 4** | Deliver history/detail/search, categories, CSV preview/import, monthly budgets, reports, approved/declined purchase and refund simulation. Add device registration, notification worker, retries and transaction deep links. | Manual, imported and simulated records share the same rules; known totals match; duplicate submissions do not duplicate records/events; notifications open the correct transaction. |
| **5 · Database evaluation — week 5** | Generate 10,000- and 100,000-transaction datasets. Run repeatable index experiments, concurrency checks and rollback tests. Capture plans, timings, buffers and index sizes. | Reproducible scripts and actual results, including cases where an index offers little benefit. Correctness evidence accompanies performance results. |
| **6 · Integration and delivery — week 6** | Complete end-to-end tests, device checks, accessibility review, backup/restore rehearsal, setup guide and demonstration package. Fix release blockers. | A fresh setup runs the full demo; restored data matches expected totals; release artifact, documentation and evidence are ready for submission. |

## Ordered implementation backlog

### 1. Establish the foundation

- [ ] Run static analysis and the existing test suite; record actual results.
- [ ] Inventory reusable screens and identify demo assumptions to remove.
- [ ] Define transaction examples and exact expected report/budget totals.
- [ ] Write the ER diagram, data dictionary and API/CSV contracts.
- [x] Add `backend/` for the API, migrations and backend tests; worker follows with transaction events.
- [x] Add environment examples without credentials and local database setup instructions.

### 2. Complete the first vertical slice

- [x] Add User and CardProfile migrations and ownership constraints.
- [x] Implement registration, password verification, login, current-user and logout/session behavior.
- [x] Implement authenticated list/create/update/archive card-profile operations.
- [x] Add the Flutter API client and in-memory session handling, including loading, empty, error and retry states. Shared domain repositories will expand with transactions.
- [x] Replace the demo startup with registration/login and persisted user-owned cards.
- [x] Apply SpendTrail identity and PKR context to this flow; amount formatting follows with transaction entry.
- [x] Verify isolation with two users and persistence through fresh-client sign-in; see milestone evidence for restart checks.

**First build milestone:** registration → login → create fictional card profile → restart → retrieve that same card from PostgreSQL. Complete this before expanding the remaining screens.

### 3. Build the transaction core

Manual purchases now persist in PostgreSQL and are available through authenticated history and detail endpoints. Flutter entry, paginated history and transaction details are connected under Home → Account purchases. The 7 November 2026 checks passed 37 Flutter tests, a separate live Flutter HTTP integration test, and nine PostgreSQL backend tests. See [purchase integration evidence](MILESTONE_02.md). The remaining transaction sources, filters and category rules expand this foundation.

- [x] Add Merchant, Category and SpendingTransaction records with required references and constraints.
- [ ] Define purchase/refund types, approved/declined states and source/channel values explicitly.
- [x] Require a non-null source reference and enforce unique `(card_id, source, source_reference)` at the database level.
- [x] Save the transaction, creation audit record and notification outbox event atomically.
- [x] Add history/detail APIs, pagination, date/card/category filters and merchant search.
- [ ] Extend history filters to statuses when declined purchases and refunds are implemented.
- [x] Connect manual entry and history screens to the API.
- [x] Enforce ownership on reads and writes, including a database trigger rejecting cross-user categories.
- [ ] Protect audit history from modification by the application role.

### 4. Add imports and payment simulation

Added prerequisite: optional Android fingerprint login, backed by revocable sessions and biometric-bound storage. Implemented before CSV imports; see [biometric login evidence](MILESTONE_04.md).

- [ ] Specify CSV columns, date/decimal formats, size limits and row-error behavior before implementation.
- [ ] Add ImportBatch tracking and a preview that identifies invalid/duplicate rows before confirmation.
- [ ] Implement the agreed atomic import policy and repeat-import protection.
- [ ] Replace demo money actions with simulated approved purchases, declines and refunds for online/POS channels.
- [ ] Link refunds to original purchases and prevent cumulative approved refunds exceeding the approved purchase amount, including concurrent requests.
- [ ] Verify that declines do not affect spending and approved refunds reduce it exactly once.

### 5. Deliver budgets and reports

- [ ] Add user-owned monthly category budgets, unique per user/category/month.
- [ ] Implement per-card and combined histories, monthly totals, category totals and budget comparisons through SQL joins, aggregates and views.
- [ ] Use approved purchases less approved refunds for PKR spending calculations.
- [ ] Connect the existing statistics UI to server reports and add budget editing/progress.
- [ ] Verify totals against the fixed examples, including month boundaries, declines and partial refunds.

### 6. Deliver notifications

- [ ] Add DeviceRegistration and NotificationEvent persistence and device-token lifecycle handling.
- [ ] Dispatch committed outbox events through Firebase Cloud Messaging with bounded retry/backoff and observable failure states.
- [ ] Prevent duplicate event creation; use event IDs to suppress repeated client handling.
- [ ] Request notification permission and handle denial without blocking transaction saving.
- [ ] Open the associated transaction on notification tap, checking the active user's access.
- [ ] Test worker interruption/retry and record FCM acceptance separately from observed device receipt.

### 7. Evaluate and package

- [ ] Evaluate composite B-tree `(card_id, occurred_at)` for history queries.
- [ ] Compare B-tree versus hash for `source_reference` equality with only one candidate active at a time; document other indexes that may affect the plan.
- [ ] Evaluate GIN for a defined JSONB containment workload.
- [ ] Repeat identical workloads before/after indexing on both dataset sizes; preserve seeds, SQL, environment details and raw `EXPLAIN (ANALYZE, BUFFERS)` outputs.
- [ ] Report median query time, scan choice, buffer activity and index size without inventing improvements.
- [ ] Prove concurrent duplicates commit one transaction and one event; prove failed writes roll back transaction/audit/outbox together.
- [ ] Rehearse database backup and restoration; verify row counts and known totals afterward.
- [ ] Complete real-device notification/deep-link checks, release packaging, setup instructions and a scripted demonstration.

## Data model and API planning map

| Area | Records | API responsibilities |
| --- | --- | --- |
| Account | User | Register, authenticate, current user, session termination |
| Wallet | CardProfile | User-owned fictional profile management; masked display metadata |
| Activity | SpendingTransaction, Merchant, Category | Manual/simulated creation, history, detail, categorization, controlled correction and refund rules |
| Imports | ImportBatch | Preview, validation, confirmation, row outcomes and duplicate tracking |
| Spending tools | Budget, reporting views | Monthly budgets, totals and category/card breakdowns |
| Reliability | AuditEvent, NotificationEvent, DeviceRegistration | Immutable audit history, atomic event creation, push dispatch and device registration |

Decide archive/deletion and correction behavior in milestone 1. Do not carry over unrestricted local transaction deletion or simulated bank balances without an explicit product rule. Store fictional identifiers and masked metadata; do not collect or persist real PANs, CVVs or banking credentials.

## Release acceptance journey

1. Register and sign in as user A; create two fictional card profiles.
2. Record a purchase, import a known CSV and generate approved/declined simulated purchases and an approved refund.
3. Repeat an import/request and confirm no duplicate transaction or notification event is created.
4. Search/filter history, open a transaction, categorize it and compare a monthly budget with known report totals.
5. Restart and sign in again; verify data persists. Sign in as user B and verify user A's records are inaccessible.
6. Exercise notification permission denial, a dispatch failure/retry and a notification tap on a supported device.
7. Run concurrency/rollback checks and index experiments; restore a database backup and repeat the known-total checks.

## Deliverables

- Integrated Flutter application, FastAPI service and notification worker.
- PostgreSQL migrations, synthetic seed scripts, report views and audit/ownership triggers.
- ER diagram, data dictionary, API/CSV contracts and setup/environment guide.
- Automated correctness tests, concurrency/rollback evidence and device verification notes.
- Reproducible database experiments, query plans and measured comparisons.
- Backup/restore guide, review build and final demonstration script.

## Execution rules

Complete milestones in dependency order. Each implementation task should include its behavior, appropriate verification and updated documentation. Record evidence as work completes; mark a checkbox only after its acceptance check passes. If time becomes constrained, defer optional NFC hardware work and visual refinements first while retaining the proposal's core application and database evidence.
