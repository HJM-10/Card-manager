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

## Delivery history

| Step | Commit | Result |
| --- | --- | --- |
| 1 | `0e78f73` | Baseline review and implementation scope |
| 2 | `daee225` | Strict card validation, duplicate feedback and retry |
| 3 | `4ad6330` | Persist masked metadata and wallet ordering |
| 4 | `05e58e9` | Card details, default selection, removal and empty state |
| 5 | `079f25e` | Persistent expenses, editor, search and filters |
| 6 | `8480345` | Monthly statistics, category breakdown and trends |
| 7 | `a889cfb` | Profile, currency labels and appearance settings |
| 8 | `e4c2b99` | Simulated money actions with review/confirmation |
| 9 | This commit | Offline font, responsive/accessibility fixes, derived demo balances, release validation and documentation |

Each preceding step was pushed to `origin/main` before proceeding to the next.

## Validation and review

- Static analysis passes with no issues.
- All 24 automated tests pass. Coverage includes the splash-to-home-to-add-card journey, keyboard layout,
  all four tabs at 320×568 with normal and doubled text, expense create/edit/delete,
  action confirmation, duplicate card rejection, storage failure, restoration,
  exact cents, currency settings, balance recalculation and statistics.
- Visual previews for every tab in light/dark mode are generated under `build/qa/`.
  Home, statistics and profile previews were inspected, including real font/icons.
- Web and Android release builds are used as packaging checks. The existing
  Android debug signing identity remains suitable for local review only.
- Kotlin incremental caching is disabled because the project lives on D: and
  plugin sources are in the Pub cache on C:, which caused cross-root cache errors.
- No Android/iOS device was connected during this work. Physical-device frame-rate
  measurements, platform screen-reader checks and iOS signing/builds remain manual.

## Data behavior

Cards retain only ID, network, last four digits, holder, expiry, starting demo
balance and visual colors. Full card numbers and CVVs are never written to storage.
The initial cards are examples; newly recorded expenses start empty.

Demo balances are derived from the starting figures and activity: expenses/sends
subtract, top-ups add, requests have no balance effect. Edits and deletions therefore
recalculate balances without keeping a second mutable total. Removing a card keeps
its historical activity, which is labeled as belonging to a removed card in filters.

Preferences and activity stay on the current device/browser; there is no server,
real payment processing, authentication, conversion service or cloud backup.
