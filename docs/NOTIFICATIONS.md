# Transaction alert setup and behavior

The Android app, authenticated device/event APIs and retrying worker are
implemented. Actual FCM acceptance, phone receipt and cold-start transaction
opening were verified on 8 November 2026; see [device evidence](MILESTONE_08.md).
New setups should repeat the checklist below. Simulated transport checks alone
do not establish device delivery.

## Connect an Android app

1. Create or select a Firebase project. Google Analytics is optional for this
   notification flow. Enabling it in the console does not add the Flutter
   Analytics SDK; analytics instrumentation remains separate work.
2. Add an Android app with package **`com.hjm.Spendtrail`**, matching the
   currently installed application. Use SpendTrail as its nickname. SHA-1 is
   not needed for this FCM flow.
3. Save its downloaded configuration as
   `android/app/google-services.json`. This file is ignored by Git.
4. Generate local public Flutter build settings:

   ```powershell
   & 'C:\Program Files\PostgreSQL\15\pgAdmin 4\python\python.exe' backend/tools/configure_firebase.py
   ```

   Standard Python users can run `python backend/tools/configure_firebase.py`.
   The script validates the Android package and writes only public app settings
   to ignored `backend/.local/firebase-config.json`. It rejects server key files.
5. Build with both the native Android configuration file and Flutter settings:

   ```powershell
   flutter build apk --debug --dart-define-from-file=backend/.local/firebase-config.json
   ```

The Google services plugin is applied only when its configuration file exists.
Its generated native resources initialize Firebase when Android starts the
process to receive a background notification. Builds without Firebase settings
remain usable and show that phone alerts are not connected. Push support in
this slice is Android only; web and other platforms retain transaction saving.

## Configure the server

The app contains no server credentials. The worker uses Google
application-default credentials with the `firebase.messaging` scope.

For local development, open Firebase **Project settings → Service accounts →
Firebase Admin SDK**, generate a service-account private key, and store it in
ignored `backend/.local/firebase-service-account.json`. Keep it local; never
paste its contents into chat or commit it. The service account needs permission
to send Firebase Cloud Messaging messages to this project. Use a dedicated
least-privilege service account for deployment.

Add these values to the ignored `backend/.env`:

```dotenv
FCM_PROJECT_ID=YOUR_FIREBASE_PROJECT_ID
GOOGLE_APPLICATION_CREDENTIALS=D:/python/Flutter/Spendtrail/backend/.local/firebase-service-account.json
```

Run migrations and restart the API before using the new app. Then run the
worker separately:

```powershell
& 'C:\Program Files\PostgreSQL\15\pgAdmin 4\python\python.exe' backend/run.py app.notification_worker
# One bounded cycle, useful for inspection:
& 'C:\Program Files\PostgreSQL\15\pgAdmin 4\python\python.exe' backend/run.py app.notification_worker --once
```

Without a configured project/credential the worker exits before claiming work.
It never substitutes a fake successful send. The API continues saving purchases
when the worker, network, credentials or notification permission is unavailable.

## Phone flow

Sign in and enable **Profile → Transaction alerts**, then accept the Android
notification prompt. Denial leaves purchases usable; permissions can later be
changed in Android settings. Returning to the app resynchronizes permission and
token state. Sign-out and Lock app pause server delivery; signing back in
restores a previously enabled preference for that account.

Foreground messages show a generic in-app banner with View. Background messages
use Android's Transaction alerts channel and open the associated record when
tapped. A cold-start tap waits for sign-in. Payload ownership, the owned event
API and transaction API are checked before navigation. A different account
cannot open the record. Network failures preserve an opening retry in Profile.
The Home bell and Profile's Alert history show owned delivery states and links.

## Persistence and delivery guarantees

- Each committed transaction already inserts one audit and outbox row in the
  same database transaction. Manual, imported, declined and refund records all
  follow that path. No rolled-back record can be dispatched.
- Migration 008 adds owned device registrations and notification events.
  Active token uniqueness prevents a token targeting multiple accounts.
  Registration serializes token transfers, preserves immutable device ownership,
  rotates tokens, and cancels old-account pending deliveries. Tokens are never
  returned by the public APIs or logged by the worker.
- Outbox expansion creates at most one event per transaction/device. An
  `enabled_at` boundary excludes history from before alerts were enabled or
  while they were disabled. Expansion and its completion marker commit together.
- Workers claim work using `FOR UPDATE SKIP LOCKED`, a unique lease and a
  persisted attempt count. A two-minute expired lease can be reclaimed, up to
  five attempts. The fifth interrupted attempt becomes failed/uncertain.
- Transient network/auth/429/5xx errors retry with exponential delay starting at
  60 seconds plus jitter, honoring Retry-After. Permanent errors stop retrying.
  UNREGISTERED disables the token and cancels its other pending events.
  INVALID_ARGUMENT alone does not revoke a token, since payloads can be invalid.
- A bounded send locks its device before the event. Disable/sign-out waits for
  an already-started send, then cancels future attempts. A message already
  accepted by FCM may still arrive afterward; its text is generic and access
  checks remain mandatory on tap.
- FCM does not offer transactional exactly-once delivery with PostgreSQL. A
  crash after sending but before committing the receipt can cause a resend.
  Every retry carries the same event ID and Android notification tag. The client
  retains the most recent 200 received/opened IDs per account/API to suppress
  repeated banners/navigation across restarts. An older notification can be
  handled again after leaving this bounded window.
- `accepted_at` and provider message ID mean FCM accepted a send. They do not
  prove device receipt. `received_at`/`opened_at` are separate authenticated
  client-reported observations; background receipt is not asserted until the
  app observes the message or the user opens it.

## API

All routes require a bearer session. Foreign device/event IDs return 404.

| Route | Behavior |
| --- | --- |
| `PUT /devices/{UUID}` | `{token, platform: "android"}` registers/rotates/re-enables an owned device. Token: 32–2048 visible ASCII characters. 200. |
| `GET /devices/{UUID}` | Owned public ID/enabled/platform; never returns token. |
| `DELETE /devices/{UUID}` | Disables owned device and cancels pending/processing events. Repeatable 204. |
| `GET /notifications` | Owned event history; limit 1–100, default 25; offset supported. |
| `GET /notifications/{UUID}` | Owned event and transaction IDs, state, attempts and separate observation timestamps. |
| `POST /notifications/{UUID}/observations` | `{action: "received" or "opened"}`; idempotent timestamps, 204. Opening also records receipt. |

## Device acceptance checklist

Record each separately rather than inferring receipt from acceptance:

1. Permission denied; purchase still saves.
2. Enable permission and verify device registration/rotation.
3. Record a new purchase with the app foregrounded; observe one banner and View.
4. Background the app, record a purchase, observe the Android notification and
   tap it into its transaction.
5. Restart/cold-start from a notification; sign in and verify the correct detail.
6. Switch accounts/lock/sign out; verify pending delivery cancellation and
   unauthorized old-account links cannot open details.
7. Stop/restart worker, force a retryable failure in isolated tests, and confirm
   the stable event ID, attempt bound and independent acceptance/receipt fields.

References: [Flutter receive/interaction](https://firebase.google.com/docs/cloud-messaging/flutter/receive),
[Android setup](https://firebase.google.com/docs/android/setup),
[token lifecycle](https://firebase.google.com/docs/cloud-messaging/manage-tokens),
[FCM errors/retries](https://firebase.google.com/docs/cloud-messaging/error-codes).
