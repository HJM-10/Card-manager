# SpendTrail setup and USB demo installation

## What the final package contains

- A release-mode Android USB-demo APK for package `com.hjm.Spendtrail`, version
  **1.0.0 (build 2)**. It updates the existing app rather than creating another
  package. It is signed with the existing development certificate for review.
- Source, setup/demonstration guides, sample CSV, dependencies and verification
  evidence. Local databases, credentials, Firebase service-account files,
  private backups and phone data are excluded.

The USB demo allows HTTP only to `127.0.0.1` and `localhost` through its Android
network configuration. Other hosts require HTTPS. The default `production`
Android flavor does not include this demo network exception. Store deployment
and a privately managed release signing key are future deployment work.

## Standard prerequisites

Install Flutter compatible with the project's Dart constraint, Android SDK/JDK,
Python 3.11+ and PostgreSQL 15+. The recorded workspace uses Flutter's bundled
JDK and pgAdmin's embedded Python with packages under ignored `backend/.local`.
Other computers should use a normal Python virtual environment.

Create an empty SpendTrail database and a separate schema-owner login, then:

```powershell
py -m venv backend/.venv
& backend/.venv/Scripts/python.exe -m pip install -r backend/requirements.txt
Copy-Item backend/.env.example backend/.env
```

Set `MIGRATION_DATABASE_URL` in the local `.env` to the schema-owner connection.
Run migrations, provision the restricted runtime login and start the API:

```powershell
Push-Location backend
& .venv/Scripts/python.exe -m app.db
$env:PROVISION_DATABASE_URL='postgresql://ADMIN:PASSWORD@localhost:5432/spendtrail'
& .venv/Scripts/python.exe -m app.db_access --configure-local
Remove-Item Env:PROVISION_DATABASE_URL
& .venv/Scripts/python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
Pop-Location
```

Provisioning generates the runtime password and saves it to the ignored `.env`;
no database credential belongs in the Flutter build. For schema/role details,
see the [backend setup guide](../backend/README.md).

## This Windows workspace

From `D:\python\Flutter\Spendtrail`, start the isolated cluster if it is not
already running, then start the API in its own terminal:

```powershell
& 'C:\Program Files\PostgreSQL\15\bin\pg_ctl.exe' -D backend/.local/pgdata -l backend/.local/postgres.log -o '-h 127.0.0.1 -p 55432' -w start
& 'C:\Program Files\PostgreSQL\15\pgAdmin 4\python\python.exe' backend/run.py app.db
& 'C:\Program Files\PostgreSQL\15\pgAdmin 4\python\python.exe' backend/run.py uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Skip cluster/API startup if those services are already running. Confirm
`http://127.0.0.1:8000/health` returns `{"status":"ok"}` before using the phone.

## Firebase and phone notifications

Follow [NOTIFICATIONS.md](NOTIFICATIONS.md) to register the same Android package,
place the native Android config in ignored `android/app/google-services.json`
and generate the public Flutter build settings. The service-account key stays
on the backend machine and is never bundled with the phone app or source ZIP.

Start the separate worker in another terminal when presenting alerts:

```powershell
Push-Location backend
& .venv/Scripts/python.exe -m app.notification_worker
Pop-Location
```

Or use this workspace's embedded launcher
from the repository root:

```powershell
& 'C:\Program Files\PostgreSQL\15\pgAdmin 4\python\python.exe' backend/run.py app.notification_worker
```

Phone internet is required for Firebase even when API access uses USB. Builds
without Firebase configuration still support account purchases and reports.

## Build the release-mode USB demonstration APK

From the repository root:

```powershell
flutter pub get
python backend/tools/configure_firebase.py --api-base-url http://127.0.0.1:8000
flutter build apk --release --flavor demo --dart-define-from-file=backend/.local/firebase-config.json
```

Output: `build/app/outputs/flutter-apk/app-demo-release.apk`. Configure Firebase
first when alerts are needed. For a build without alerts, omit the configuration
generator and use `--dart-define=API_BASE_URL=http://127.0.0.1:8000` instead.
Both Android flavors keep the same package identity, so install one at a time.

## Install/update the phone

Connect the phone with USB debugging enabled and accept the phone's computer
authorization prompt. Using Android SDK platform-tools:

```powershell
adb devices
adb reverse tcp:8000 tcp:8000
adb install -r build/app/outputs/flutter-apk/app-demo-release.apk
adb shell am start -n com.hjm.Spendtrail/.MainActivity
```

If `adb` is not on PATH in this workspace, its executable is
`C:\Users\MPS\AppData\Local\Android\sdk\platform-tools\adb.exe`.
For multiple connected devices, pass `-s SERIAL` to each command. An update
preserves app data and settings. USB forwarding must be recreated after a
disconnection or reboot. The API computer must stay connected during this demo.

## Verify and demonstrate

Run `flutter analyze` and `flutter test`. The offline suite intentionally skips
the live HTTP test unless a dedicated test API is supplied. The repository's
`tools.live_acceptance` runner creates an isolated restricted API/schema and
executes that real-client journey; it requires `TEST_DATABASE_URL` and must not
point at the application database.

Use [DEMO_GUIDE.md](DEMO_GUIDE.md) for the scripted actions and exact expected
totals. Read [RELEASE_VERIFICATION.md](RELEASE_VERIFICATION.md) for the recorded
device, accessibility, build and packaging results.
