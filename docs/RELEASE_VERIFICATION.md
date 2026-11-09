# Final USB demonstration release verification

Verified on 9 November 2026. Delivery is the user-selected **USB demonstration
build**, compiled in Flutter release mode and signed with the existing Android
development certificate. The application identity remains `com.hjm.Spendtrail`;
version is **1.0.0, build 2**. This is a review/submission artifact, not a
Play Store release or a publicly hosted backend deployment.

## Automated acceptance

| Check | Result |
| --- | --- |
| Final Flutter static analysis | No issues |
| Full offline Flutter suite | 79 passed, one intentionally skipped live test; zero errors |
| Dedicated live HTTP test | Passed separately; zero skipped tests |
| Accessibility-focused suite | All nine tests passed; included in the 79 above |
| Existing backend reliability suite | Most recent full result: 104 passed; backend application/migration source unchanged for this release |
| APK build | `assembleDemoRelease` succeeded in 207.1 seconds |
| APK size | 57,636,991 bytes |
| Signature | APK v2 verification passed; Android Debug certificate, matching the existing installation |
| Package metadata | `com.hjm.Spendtrail`, versionCode 2, versionName 1.0.0, min SDK 24, target SDK 36 |
| Compiled manifest | Release app; no `android:debuggable=true`; demo network-security configuration present |

The one live test is skipped in the ordinary offline test command because it
requires a dedicated API. The separate [live acceptance runner](../backend/tools/live_acceptance.py)
created a fresh PostgreSQL test schema and restricted login, started a temporary
API on loopback, then ran the actual Flutter HTTP client against it. It tested
registration/sign-in, saved cards, purchases, matching retries, fresh-client
persistence, filters, categories, CSV imports, simulations/refunds, reports,
budgets, biometric session APIs and device-token ownership. It committed five
transactions with five audit/outbox rows across two synthetic users. The API,
schema and login were removed afterward; the application database was untouched.

Raw final Flutter events, analysis output, live results and APK/signing
inspection are in [release evidence](evidence/release-20261109/).
The existing [backend suite result](evidence/reliability-20261109/full-backend-junit.xml)
and its source hashes remain the backend verification reference.

## Accessibility review and fixes

The final [accessibility tests](../test/accessibility_release_test.dart) check:

- Login and registration in light/dark appearance: labeled controls, Android
  minimum touch-target guideline and Flutter text-contrast guideline.
- Purchase history, purchase entry and monthly spending/budgets in light/dark
  appearance using the same guidelines on the rendered on-screen controls.
- Named Home/Cards/Stats/Profile navigation and Transaction alerts, each with
  at least a 48-dp target.
- Keyboard Enter/Space activation for custom actions.
- Reduced motion: startup completes without the 2.9-second splash animation.
- Account history/forms at 320×568 with 200% text and at 844×390 landscape,
  including scrolling to the save action.

Review found and fixed four issues: 44-dp navigation targets, an undersized
unlabeled alert control, purchase history's trailing amount failing layout at
large text, and a channel selector overflowing at large text. Large/narrow
history rows now place the amount below the descriptive text; selectors expand
within the form. Reduced-motion startup was also added.

These are scoped automated guidelines and native-label/layout checks. They are
not a formal accessibility certification or a complete spoken TalkBack audit.
All three existing wallet designs retain their previously tested small-screen,
light/dark and enlarged-text layout coverage; contrast measurements above focus
on the account workflows and light/dark login rather than every decorative card.

## Physical device results

Samsung **SM-A725F**, Android **14**, display **1080×2400**, density **450 dpi**:

- Installed the new release APK over the existing app successfully, preserving
  its preferences and biometric setup. No second package was created.
- Cold-launched the release build successfully. The user performed fingerprint
  sign-in and confirmed the account Home opened.
- Android's native accessibility hierarchy exposed all five named Home controls
  as clickable; their measured bounds were at least 48 dp in both dimensions.
- Account history loaded from the local backend through USB, with PKR amounts.
  Statistics and Profile loaded successfully.
- Temporarily set phone font scale to 2.0 and visually inspected history:
  descriptions and amounts wrapped/stacked without the previous failure.
- Confirmed actual physical landscape rendering at **2400×1080** with the window
  manager and visually inspected purchase details. Widget tests separately
  exercised landscape history/forms. The initial settings-only rotation attempt
  retained a portrait capture; the explicit window-manager check confirmed the
  landscape viewport and is recorded separately.
- Restored the original font scale and rotation settings after checks.

Private phone screenshots/hierarchies stay under ignored `backend/.local`.
Sanitized [native bounds/layout evidence](evidence/release-20261109/device-layout.json)
and [confirmed rotation evidence](evidence/release-20261109/device-rotation.json)
contain no copied account profile or device tokens.

## Real cold-start notification and transaction link

The app was backgrounded and killed with `am kill`, **not force-stopped**.
`pidof` confirmed the process absent before the test. One real notification event
was queued for an existing owned purchase/device pair; no spending transaction
was added. The running FCM worker dispatched it successfully on its first attempt.

The user tapped the notification, authenticated and confirmed that the associated
purchase opened. Separate database fields recorded:

- Firebase acceptance: **16:56:49 PKT**.
- Phone receipt: **16:57:25 PKT**.
- Opened observation: **16:57:25 PKT**.

The [cold-start evidence](evidence/release-20261109/cold-start-notification.json)
preserves the full timestamps and outcomes without tokens/provider identifiers.
The app still had **nine transactions and PKR 18,998.55** in spending afterward.
The test adds a notification-history event, not a purchase or refund.

Notification denial, retry/backoff, duplicate handling and cross-account link
rejection are covered by existing automated tests. Those failure conditions were
not all deliberately induced on the physical phone in this release check.

## Package and reproducibility

The final delivery directory is
`build/delivery/SpendTrail-1.0.0+2-usb-demo/`, with a sibling ZIP. It contains:

- `SpendTrail-1.0.0+2-usb-demo.apk`.
- `SpendTrail-1.0.0+2-source.zip`.
- Setup, demonstration and release-verification guides.
- The sample CSV and `MANIFEST.json` with file sizes and SHA-256 checksums.

The APK SHA-256 is
`e92c31851b106a0a26f4f02c5798ac870e352c664c3c403bb369b71490f46a03`.
The [package evidence](evidence/release-20261109/package.json) records the final
delivery ZIP's checksum as well. The package generator checks ZIP integrity and
excludes `.env`, local databases, private backups, device screenshots, signing
keys, service-account files and unrelated presentation work.
The outer bundle's checksum record is kept beside the repository evidence,
rather than inside the source ZIP; the included `MANIFEST.json` supplies the
offline package's file checksums without a circular self-checksum.

Rebuild with the commands in [SETUP_GUIDE.md](SETUP_GUIDE.md), then package from
the repository root:

```powershell
python backend/run.py tools.package_demo --apk build/app/outputs/flutter-apk/app-demo-release.apk --output build/delivery/SpendTrail-1.0.0+2-usb-demo
```

Choose a new or empty output directory when repackaging. The final versioned
package path above is for this run. The USB flavor's Android HTTP exception
contains only loopback hosts; the default production flavor has no demo network
exception. An independent release requires an HTTPS API and managed production
signing/deployment, as described in the setup guide.

Use [DEMO_GUIDE.md](DEMO_GUIDE.md) for the presenter sequence and expected totals.
Database performance, reliability and restore evidence are linked there. No
real payments, bank feeds, NFC provisioning or production hosting is claimed.
