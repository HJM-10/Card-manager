# Transaction alerts: implementation and verification

Delivered 8 November 2026. The Firebase-connected Android app and local server
worker were verified with actual phone delivery and authenticated transaction
opening, including after the app process was stopped and fingerprint sign-in.

## Implemented

- Migration 008 adds immutable-owner device registrations, active token
  uniqueness, notification event persistence, outbox expansion tracking, leases,
  bounded attempt counts and independent provider/client observation fields.
- Authenticated device registration, token rotation, disabling and owned event
  history/observation APIs. Account switching cancels old pending work. Sign-out
  and lock pause delivery atomically with session revocation.
- Separate FCM HTTP v1 worker using application-default credentials. It expands
  only committed outbox rows, handles transient/permanent errors, honors
  Retry-After, disables unregistered tokens and reclaims interrupted leases.
- Android permission opt-in, token refresh and resume synchronization, a named
  notification channel/icon, generic foreground banners and background tap
  handling. Cold-start taps wait for matching sign-in; owned event and
  transaction APIs verify access before navigation.
- Persisted recent event IDs suppress repeat foreground banners and navigation
  per account/API across restarts. A stable Android notification tag is reused
  across send attempts. At-least-once delivery limits are documented.
- Profile notification controls and owned alert history, connected to the Home
  bell. Purchases remain usable without Firebase configuration or permission.
- Public config generation from a matching Android `google-services.json`;
  private server credentials remain outside the app and Git.

## Automated evidence

- **70 Flutter tests passed**, with the opt-in HTTP integration case skipped in
  the offline suite. Seven new notification tests cover denied permission,
  continued purchase saving, token rotation, disabling, persisted duplicate
  suppression, cold-start sign-in, foreground banners, wrong accounts, session
  expiry and actual app navigation into transaction details.
- The full backend suite passed **57 tests**, including nine notification
  database checks and seven FCM transport checks, from the renamed project
  directory with the relocated PostgreSQL cluster.

- Database evidence includes one event per transaction/device, distinct
  acceptance/receipt/opened timestamps, owner isolation, bounded backoff,
  interruption/reclaim, same-ID resend after an uncertain send, exhausted lease
  failure, token reassignment, logout/registration races, disabling/lock, no
  historical alerts and competing-worker claims.
- Transport checks inspect the real message shape with a mocked HTTP boundary,
  including generic notification text, stable tag/link IDs, retryable 429/503,
  UNREGISTERED versus INVALID_ARGUMENT, network errors and invalid responses.
  These checks **do not establish FCM acceptance or phone receipt**.
- Flutter static analysis and the web release build passed. The real Flutter
  HTTP integration case passed against a temporary API/schema, including device
  registration, rotation, foreign-device rejection and disabling, alongside the
  existing account/purchase/import/refund/budget journey.
- An Android debug build with Firebase libraries
  succeeded before project connection; the configured build and real-device
  checks are tracked separately below.
- The development database was backed up before migration 008. All nine existing
  transactions and audit/outbox counts were verified unchanged afterward.

## Project identity

The project files now live in D:/python/Flutter/Spendtrail, and the Dart
package is spendtrail. Android uses com.hjm.Spendtrail, matching the existing
Firebase Android registration. Kotlin sources and test imports were updated.
The API/database restarted from the new location; Flutter analysis and all
70 Flutter tests passed after the move. Git history and existing account data
were retained. The old location contains only empty directory shells held open
by Windows. Android treats the new package as a separate installation, requiring
fresh sign-in and optional fingerprint enrollment.

## Real-device evidence

- A configured Android debug APK for `com.hjm.Spendtrail` built successfully,
  installed on the Samsung SM-A725F and launched. The Firebase Android identity
  matches the app; server authentication with Google succeeded.
- The user signed in, re-enabled fingerprint login for the new installation and
  enabled transaction alerts. Device registration and token synchronization
  returned 200 from the authenticated API.
- Two explicit test alert events linked to existing owned purchases were queued.
  Neither test created or changed a spending record; all nine purchases remained.
  Both FCM requests returned HTTP 200 with provider message IDs, each on attempt 1.
- The user confirmed the first alert appeared and opened its purchase. Its
  separate accepted, received and opened timestamps were then verified in the DB.
- For the second test, the user put the app in the background. `am kill` stopped
  the background process and `pidof` confirmed it absent, without force-stopping
  FCM delivery. A second alert was accepted. The user confirmed it opened the
  linked purchase after sign-in. API evidence includes successful biometric
  refresh, owned event/detail reads and an opened observation returning 204.
- Both final event rows have accepted/received/opened timestamps and no error.
  Provider acceptance is not used as a substitute for receipt. Bounded retry,
  worker interruption, denial, foreground banners, duplicate suppression and
  cross-account rejection remain covered by automated checks; the device tests
  do not claim those failure modes were all induced on the physical phone.
- Detailed local event evidence and provider IDs are retained under ignored
  `backend/.local/notification-device-evidence.json`. Server credentials and
  device tokens were not committed or embedded into the app.

The API, database and worker are running from the renamed project. Local phone
access continues to use USB port forwarding. See [NOTIFICATIONS.md](NOTIFICATIONS.md)
for setup and delivery limitations. Google Analytics may be enabled in the
Firebase console; analytics instrumentation remains separate work.

The roadmap now has **38/47 completed items (81%)**, with **9 remaining (19%)**.
Restricted audit-role privileges, database evaluation and final release/restore
checks remain. The existing AnyIO deprecation warning is unchanged.
