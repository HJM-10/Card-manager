# Monthly category budgets and account reports

Implemented 8 November 2026. After signing in, open **Statistics → Set category
budget**. Choose a month/category and enter a PKR limit. The screen shows exact
account spending, budget progress and remaining funds, including an explicit
over-budget amount. Edit/remove a limit from its budget card. Previous/Next
month supports past and future planning; limits do not roll over or block saves.

The signed-in Statistics tab now reads server transactions rather than local
demo expenses. Monthly net spending is approved purchases minus approved refunds;
declines contribute zero. Category and card breakdowns include archived-card
history. Budgets cover all cards. Selecting one card filters spending and hides
budget editing until All cards is selected, keeping the comparison scope clear.
Returning to Statistics or using refresh reloads current records. Explicit
legacy demo mode retains its original local statistics.

## Data and API

Migration 007 adds `budgets`: UUID identifier, owner, owned category, first day
of the month, positive `NUMERIC(14,2)` limit and update timestamp. Composite
ownership references and a unique user/category/month constraint enforce one
limit. PUT creates or updates that row; retries retain its identifier and
simultaneous requests cannot create duplicates. Last committed update wins.
DELETE removes only the chosen monthly limit and can be retried safely.

`monthly_category_spending` groups the signed transaction view by owned
card/category and Asia/Karachi calendar month. The API combines exact SQL
aggregates and category/budget joins in one repeatable-read snapshot. Monetary
values are decimal strings; no floating-point money calculation is introduced.
Percentages round half-up to two decimals. Progress bars clamp visually to
0–100%, while accompanying amounts/percentages retain negative or over-limit
values. A later-month refund can yield negative spending and remaining money
greater than the budget. Current category determines each record's grouping;
recategorizing a purchase does not recategorize its existing refunds.

Routes:

- `GET /reports/monthly?month=YYYY-MM`, with optional owned `card_id`.
- `PUT /budgets/{month}/{category_id}` with `{amount: "1500.00"}`.
- `DELETE /budgets/{month}/{category_id}`.

All require authentication. Budget months are 2000-01 through 2100-12. Amounts
are positive strings with exactly two fractional digits and at most twelve
whole digits. Budgets cannot target Uncategorized; assign a saved category
first. See [the API contract](../backend/README.md) and [design](DESIGN.md).

## Verification

- Full offline Flutter suite: **62 passed**, one opt-in HTTP test skipped.
  The expanded account-flow suite then passed **4 tests**, including one newly
  added test, for **63 distinct passing Flutter tests** overall. The new checks
  cover budget create/edit/remove, exact amount validation, lost-response retry,
  card/month requests, stale-data clearing, session expiry, inactive-tab loading,
  refresh after tab changes and the form at 320×568 with doubled text.
- Full PostgreSQL backend suite: **41 passed**, including six new budgeting
  tests. Ownership, validation, database constraints, concurrent same-budget
  saves, idempotent removal, month isolation, recategorization and archived cards
  are covered. The existing AnyIO deprecation warning remains.
- Fixed November example: PKR 1,250.05 + 300.00 - 250.05 = **1,300.00**;
  the PKR 900.00 decline contributes zero. A PKR 1,500.00 budget leaves
  **200.00**, with **86.67%** used. Lowering the limit to PKR 1,000.00 yields
  **300.00 over budget** and **130.00%** used.
- Per-card November totals are **1,000.00** and **300.00**. The PKR 50.00
  purchase at December's first instant appears only in December. Adding a
  December PKR 500.00 refund yields **-450.00** net spending, **1,450.00**
  remaining on a PKR 1,000.00 budget and **-45.00%** used.
- The real Flutter HTTP integration test passed against a temporary PostgreSQL
  schema. It verifies setting/retrying/changing a budget, exact imported/manual/
  refund totals, archived-card reporting, cross-account denial, persistence
  after a fresh client signs in, and removal. The temporary schema was dropped.
- The local application database was backed up before migration 007; all **nine
  existing transactions**, their values/owners, and audit/outbox counts were
  verified unchanged afterward.
- Flutter static analysis completed without issues; the web release build
  succeeded. Checks used the installed Dart runtime and Flutter tools snapshot
  because the Windows batch launcher had stalled in the preceding milestone.

The API and app must reload updated source to expose the new routes/screens.
Physical Android/device behavior is not established by these checks.
Notification delivery, restricted audit-role privileges, database performance
evaluation and final delivery checks remain on the roadmap.

This completes the five budgets/reports backlog items: **32/47 complete (68%)**,
with **15/47 remaining (32%)**. These percentages count items, not effort.
