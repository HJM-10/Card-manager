# Card-manager

**Magpie** is a local demo wallet and expense tracker built in Flutter, with an animated interface inspired by the reference video.

All balances and money actions are simulated. No bank connection, payment processing, or messages to recipients.

## Features

- **Animated splash:** coins drop above a cash stack, the illustration collapses into the `Magpie.` wordmark, and a progress bar fills.
- **Wallet-style card stack:** tap a back card to bring it to the front; the balance counts up.
- **Notched front card:** an inverted-corner cut-out holds the *Add Card* pill (`CustomClipper`).
- **Add Card sheet:** live `0000 0000 0000 0000` formatting, `MM/YY` auto-slash, Visa/Mastercard detection with an animated logo, and a button that only enables on a valid form.
- **"Adding your card..." state:** the sheet morphs down to a gooey metaball loader, then the new card drops into the stack.
- **Floating dark nav bar:** the active tab expands to show its label.
- **Saved wallet:** card display details and ordering survive restarts. View details, choose a default card, or remove cards.
- **Expenses & activity:** add, edit, delete, search and filter records by category or card. Dates and exact cents are saved locally.
- **Statistics:** monthly spending totals, category breakdowns and a six-month trend based on your records. Requests and top-ups are excluded from spending.
- **Profile:** saved name, currency label and system/light/dark appearance. Currency selection changes labels without converting amounts.
- **Demo actions:** Send, Request and TopUp have review and confirmation screens. Expenses and demo sends reduce the demo balance; top-ups increase it. Requests remain pending. Editing/deleting activity recalculates balances.
- **Offline font:** Plus Jakarta Sans and its OFL license are bundled with the app.

The initial three cards are sample records; expenses start empty. Add Card supports 16-digit Visa/Mastercard test numbers, checksum and expiry validation. For example, use `4242 4242 4242 4242`, a future expiry and any three-digit test CVV. Duplicate network/last-four combinations are rejected. **Only masked card metadata is saved; full card numbers and CVVs are never persisted.**

## Tech

| Concern | Choice |
|---|---|
| Framework | Flutter 3.35, Material 3 |
| State | `flutter_riverpod` |
| Fonts | Bundled Plus Jakarta Sans |
| Storage | `shared_preferences` (local JSON records) |
| Animations | Built-in implicit/explicit animations, `CustomPainter`, `CustomClipper` |

## Project structure

```
lib/
├─ main.dart
├─ core/        theme tokens, card utils (formatters, validation), shared widgets
├─ data/        models, local storage, settings and Riverpod providers
└─ features/    splash, home, add_card, cards, expenses, statistics, profile, actions, shell
```

## Run

```bash
flutter pub get
flutter run
```

## Verify and build

```bash
flutter analyze
flutter test
flutter build web --release
flutter build apk --release
```

Tests exercise startup and adding a card, expense editing, action confirmation,
restoration after restart, storage failures, duplicate rejection, statistics,
currency settings and small-screen layouts with enlarged text. Visual preview
tests write PNGs for all tabs in light/dark themes under `build/qa/`.

The Android APK uses the project's existing debug signing setup for local review.
Configure a production application ID and release signing before store distribution.
Physical-device frame-rate profiling and iOS packaging require their target devices/toolchain.

Data is stored only on the current device/browser profile. Clearing app data or
browser storage removes it; there is no cloud backup or account synchronization.

See [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md) for delivery history and checks,
and [PROPOSAL.md](PROPOSAL.md) for the original reference design proposal.
