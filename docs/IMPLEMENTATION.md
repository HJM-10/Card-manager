# Magpie implementation tracker

Scope: a local card and expense manager. Send, Request and TopUp are explicitly
simulated; balances are demo figures, not bank balances. No payment integration.

Each numbered step is delivered as its own commit and push.

1. Baseline: inspect the existing splash, home, card flow and navigation; run
   analysis and tests. Findings: three placeholder tabs, volatile data, disabled
   checksum validation, non-interactive expense navigation and demo actions.
2. Add Card: strict validation, field feedback, duplicate protection and retry.
3. Persistence: save display metadata and ordering; never persist PAN or CVV.
4. Cards: details, default selection and removal, including the empty wallet.
5. Expenses: create/edit/delete, card association, search and filters.
6. Statistics: totals, categories and monthly trends from recorded expenses.
7. Profile: editable name, currency display preference and appearance.
8. Actions: clearly labeled simulated Send, Request and TopUp flows.
9. Release checks: responsive layouts, accessibility, empty states, automated
   journeys and release build. Physical-device performance remains a manual check.

## Baseline review

The existing source includes the splash-to-home transition, card stack selection,
formatted inputs and adding animation. Existing tests cover utility functions only.
Visual matching and 60 fps are not established by source inspection or unit tests.
