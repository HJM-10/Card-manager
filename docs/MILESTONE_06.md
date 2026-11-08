# Simulated purchases and linked refunds

Delivered 8 November 2026. Open **Account purchases → Simulate purchase** and
choose Approved or Declined, with an online/POS channel. Open an approved
purchase's details to **Simulate refund**. Partial refunds are supported; refund
details link to the original purchase. History displays type/status and combines
these new filters with existing search/card/category/date filters.

Authenticated Home replaces Send/Request/TopUp shortcuts with **Simulate
purchases & refunds**, leading to Account purchases. Explicit legacy demo mode
keeps its local actions. Local wallet balances and statistics remain demo data;
server budgets/reports are the next feature.

## Consistency rules

Migration 006 expands transaction constraints, adds owned original-purchase
references and a refund lookup index, and creates `transaction_spending` with
exact signed amounts. Declines contribute zero; approved refunds subtract once.
Refunds inherit the original merchant/card/channel and current category at
creation, and cannot predate the purchase. Archived cards accept refunds.
Only approved purchases can be refunded; refunds of refunds are rejected.

The shared purchase writer handles manual/CSV/simulated purchases, including
ownership, retries, card locks and atomic event creation. Refund creation uses
the same card-lock order; a database trigger independently locks the original
purchase and checks the cumulative ceiling. Creation fields become immutable;
current category remains editable. Unique source references and frozen Flutter
request bodies preserve retry safety, including after an uncertain response.

## Verification

- Flutter analysis: no issues. Full offline Flutter suite: **57 passed**, with
  the opt-in HTTP test skipped. New widget checks exercise a declined outcome,
  identical lost-response retry, refund request fields and absence of the refund
  action on declined purchases. Existing categories, imports, filters, sessions,
  persistence and layouts continue to pass.
- Existing backend suite plus the initial five simulation checks: **33 passed**.
  The expanded simulation suite: **7 passed**, including the original five.
  Together these verify **35 distinct database tests**. Coverage includes
  ownership, archived-card refunds, zero/invalid amounts, linked partial/full
  refunds, reference conflicts/replays, concurrent API refunds, concurrent direct
  SQL refunds, creation immutability and rollback on an outbox write failure.
- Fixed SQL fixture: November PKR 1,250.05 + 300.00 - 250.05 = **1,300.00**;
  a PKR 900.00 decline contributes zero and a PKR 50.00 purchase at December's
  first instant is excluded. A fully refunded purchase contributes exactly zero.
- The opt-in Flutter real-HTTP test passed against a temporary PostgreSQL schema,
  including declined simulation replay/filtering, an archived-card refund,
  linked refund replay/type filtering and cross-account refund denial, alongside
  the existing account/category/import journey. Its schema was removed afterward.
- Web release build succeeded. Flutter's Windows batch launcher hung during
  startup; checks succeeded through the installed Dart runtime and Flutter tools
  snapshot. The two stuck check processes started during this task were stopped.
- The local development database was backed up before migration 006. All **nine
  existing transactions**, including their values and owners, and audit/outbox
  counts were verified unchanged after migration.

The backend retains its existing AnyIO deprecation warning. This slice does not
establish Android device behavior, notification delivery or final release
readiness. Updated source requires the API/app to reload. Audit protection via
a restricted application database role is still pending.

## Design backlog and progress

[DESIGN.md](DESIGN.md) now records the reusable-screen inventory, demo
assumptions, ER relationships, data dictionary, transaction/correction rules,
report timezone, fixed totals and per-feature acceptance conditions. Planned
tables are explicitly identified. API and CSV contracts remain in their linked
guides. This closes the four earlier foundation checklist gaps.

The roadmap advances from **18/47 (38%)** to **27/47 (57%)** completed items;
**20/47 (43%)** remain. These are checklist proportions, not effort estimates.
Remaining work includes audit-role hardening, budgets/reports, notification
dispatch, database experiments and final delivery/device/restore checks.
