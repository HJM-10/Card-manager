# SpendTrail

Project folder: Spendtrail. Flutter package: spendtrail. Android application
ID: com.hjm.Spendtrail, matching the registered Firebase Android app.

See the [project roadmap](docs/ROADMAP.md) for the six-week build plan, ordered backlog and acceptance criteria.

**Default launch:** the animated SpendTrail splash, sign-in or registration, then the original wallet layout. Open **Cards → Account card profiles** to manage server-backed fictional cards. See the [backend setup and API guide](backend/README.md) to run the API. Use `--dart-define=LEGACY_DEMO=true` for a local-only review of the wallet.

All balances and money actions are simulated. No bank connection, payment processing, or messages to recipients.

**Account purchases:** open **Home → Account purchases** or **Cards → Account card profiles → Account purchases**. Record a manual PKR purchase against an active account card, then browse paginated history and open transaction details. Purchases persist in PostgreSQL and return after signing in again. The entry form accepts a merchant, exact decimal amount, date/time and online/POS channel. Failed saves retain the same request for safe retry while the form stays open. Account purchases are separate from the existing local demo expenses and statistics.

Choose a saved category when recording a purchase, or open its details and tap **Change category** later. Each account starts with Groceries, Food, Transport, Shopping, Bills and Other; **New category** adds a custom choice. **Search merchants** searches the full account history. **Filters** combines a card (including archived cards), category or Uncategorized, and an inclusive local date range. **Clear search & filters** returns to all purchases.

**CSV imports:** open **Account purchases → Import CSV**, select an active account card, and choose a file or **Try sample CSV**. Preview rows, errors, duplicates and the exact new-purchase total before confirming. Any row error blocks the whole import; matching references are skipped, and successful confirmation saves all new rows atomically. Retrying confirmation or re-uploading the same file does not add the purchases twice. See the [CSV format and rules](docs/CSV_IMPORT.md) and [sample file](assets/imports/sample_purchases.csv).

**Fingerprint login (Android):** sign in with your password, then enable **Profile → Fingerprint login** and complete the phone's biometric prompt. **Lock app**, or restart the app, then choose **Sign in with fingerprint**. Saved login is valid for up to 30 days and requires the backend connection. Sign out or turn the setting off to revoke it. Password login remains available and clears the previous saved fingerprint setup; enable it again afterward if wanted. The setting uses Android Keystore and strong biometrics, with no saved password or fingerprint data. See [verification and behavior](docs/MILESTONE_04.md).

## Features

**Transaction alerts:** notification delivery is being connected to Firebase.
The implementation includes **Profile → Transaction alerts**, owned alert
history from the Home bell, permission handling, generic foreground banners and
authenticated transaction links. Builds without Firebase configuration keep
purchases usable and show that alerts are not connected. See
[setup and behavior](docs/NOTIFICATIONS.md) and [verification status](docs/MILESTONE_08.md).

**Monthly budgeting:** after signing in, open **Statistics → Set category
budget**. Choose a month and category, enter a PKR limit, then review spending,
remaining money and progress across all your cards. Edit or remove a limit from
its budget card. Previous/Next month selects past or future budgets; limits do
not roll over. Card filtering shows that card's monthly spending; choose All
cards to edit the account-wide budgets. Totals come from saved account purchases
less refunds, exclude declines, and follow Pakistan calendar months. Refresh or
return to Statistics to reload changes. See [verification](docs/MILESTONE_07.md).

**Payment simulation:** open **Account purchases → Simulate purchase**, choose
an active account card, online/POS channel and Approved or Declined outcome.
Open an approved purchase's details to **Simulate refund**, including partial
refunds. Refund details link back to the original purchase; total refunds cannot
exceed its amount. History shows type/status and supports both filters. Account
Home replaces the old money shortcuts with this route; legacy demo mode keeps
its local actions. No money moves. Signed-in Statistics includes server reports and budgets.
See [verification](docs/MILESTONE_06.md) and [design contracts](docs/DESIGN.md).

- **Animated splash:** coins drop above a cash stack, the illustration collapses into the SpendTrail wordmark, and a progress bar fills.
- **Wallet-style card stack:** tap a back card to bring it to the front; the balance counts up.
- **Notched front card:** an inverted-corner cut-out holds the *Add Card* pill (`CustomClipper`).
- **Add Card sheet:** live `0000 0000 0000 0000` formatting, `MM/YY` auto-slash, Visa/Mastercard detection with an animated logo, and a button that only enables on a valid form.
- **"Adding your card..." state:** the sheet morphs down to a gooey metaball loader, then the new card drops into the stack.
- **Floating dark nav bar:** the active tab expands to show its label.
- **Saved wallet:** card display details and ordering survive restarts. View details, choose a default card, or remove cards.
- **Expenses & activity:** add, edit, delete, search and filter records by category or card. Dates and exact cents are saved locally.
- **Statistics:** signed-in monthly account totals, card/category breakdowns and category budgets. Legacy demo mode retains local statistics and its six-month trend.
- **Theme:** choose SpendTrail Classic, Cobalt Fold or Fig Carousel under **Profile → Theme**, then save. Classic is the default. **Appearance** offers System, Light and Dark independently. The app saves both choices on the device. Login and registration use the selected design too, including after sign-out, lock and restart. All demo amounts use PKR.
- **Demo actions:** Send, Request and TopUp have review and confirmation screens. Expenses and demo sends reduce the demo balance; top-ups increase it. Requests remain pending. Editing/deleting activity recalculates balances.
- **Offline fonts:** Plus Jakarta Sans, DM Sans, Space Grotesk, Inter and Outfit are bundled with their OFL licenses.

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
PKR formatting and small-screen layouts with enlarged text. Visual preview
tests write PNGs for all tabs in light/dark themes under `build/qa/`.

The Android APK uses the project's existing debug signing setup for local review.
Configure a production application ID and release signing before store distribution.
Physical-device frame-rate profiling and iOS packaging require their target devices/toolchain.

Demo wallet records and appearance are stored on the current device or browser. Account card profiles are stored separately in PostgreSQL.

See [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md) for delivery history and checks,
and [PROPOSAL.md](PROPOSAL.md) for the original reference design proposal.
