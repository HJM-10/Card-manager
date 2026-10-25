# Card-manager

**Magpie**: a credit card manager UI built in Flutter, recreated from a reference design video.

> Send, spend and track every card — your whole money life in one calm place.

## Features

- **Animated splash:** coins drop above a cash stack, the illustration collapses into the `Magpie.` wordmark, and a progress bar fills.
- **Wallet-style card stack:** tap a back card to bring it to the front; the balance counts up.
- **Notched front card:** an inverted-corner cut-out holds the *Add Card* pill (`CustomClipper`).
- **Add Card sheet:** live `0000 0000 0000 0000` formatting, `MM/YY` auto-slash, Visa/Mastercard detection with an animated logo, and a button that only enables on a valid form.
- **"Adding your card..." state:** the sheet morphs down to a gooey metaball loader, then the new card drops into the stack.
- **Floating dark nav bar:** the active tab expands to show its label.

## Tech

| Concern | Choice |
|---|---|
| Framework | Flutter 3.35, Material 3 |
| State | `flutter_riverpod` |
| Fonts | `google_fonts` (Plus Jakarta Sans) |
| Animations | Built-in implicit/explicit animations, `CustomPainter`, `CustomClipper` |

## Project structure

```
lib/
├─ main.dart
├─ core/        theme tokens, card utils (formatters, validation), shared widgets
├─ data/        models + Riverpod providers (mock data)
└─ features/    splash, home (card stack), add_card, shell (nav bar)
```

## Run

```bash
flutter pub get
flutter run
```

Run the tests with `flutter test`.

See [PROPOSAL.md](PROPOSAL.md) for the full design breakdown and roadmap.
