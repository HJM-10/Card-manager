# Android fingerprint login

Implemented before CSV imports on 7 November 2026.

## User flow

1. Sign in normally, then open **Profile → Fingerprint login**.
2. Enable the switch and authenticate with the phone's strong biometric prompt.
3. Choose **Lock app** or restart the application. The sign-in screen offers **Sign in with fingerprint**.
4. Authenticate again to unlock the saved credential and retrieve a fresh access session from the API.

Password sign-in remains available. Successful password sign-in clears the previous saved setup, including when switching accounts. Cancellation, temporary lockout and network failures leave password fallback available. An expired/revoked server credential or invalidated encryption key requires password sign-in and re-enablement. Disabling the setting revokes its credential while keeping the current account open. Explicit sign-out revokes its credential and removes the local saved copy. Locking preserves the saved credential; it also hides the account when the server is unreachable. Backgrounding alone does not automatically lock an already open account.

## Implementation

Android uses the stable AndroidX Biometric library, a Flutter fragment activity and a small native method channel. Each AES-GCM encryption/decryption operation requires a strong biometric through `BiometricPrompt.CryptoObject` and an authentication-bound Android Keystore key. The key is non-exportable and is invalidated when biometric enrollment changes. The encrypted credential and IV are written atomically under `noBackupFilesDir`; neither plaintext credential, password nor fingerprint data is written to preferences or application files. The encrypted payload binds the credential to its API base URL. Other platforms retain password login.

The API creates a separate random credential only after authenticated opt-in, stores its SHA-256 hash, and limits it to an absolute 30-day window. Access renewal is capped at 12 hours and the credential expiry. Renewal does not extend the 30-day window. Access tokens remain in memory. Revoking the credential invalidates every associated access session; a new password session or another device's credential is independent. The app attempts to revoke a credential if native enrollment is cancelled/unsuccessful. If the server becomes unreachable during cleanup, the unused credential expires normally; no usable credential is retained locally.

## Verification

- PostgreSQL integration suite: 19 passed, including access expiry/renewal, absolute credential expiry, hashed storage, disable/replacement/sign-out revocation, user isolation, invalid input and concurrent refresh/replacement versus sign-out races.
- Flutter suite: 49 passed, with the opt-in live test skipped in the offline run. Biometric tests cover enable/lock/unlock/sign-out, cancelled enrollment cleanup, cancelled/expired/offline/unavailable sign-in, server binding on the native channel, password fallback and offline locking.
- The live Flutter HTTP test passed separately against a temporary isolated PostgreSQL schema, including biometric credential issue, lock, fresh-client renewal, persisted purchase retrieval and revocation. The schema was removed afterward.
- Static analysis passed without issues. Android debug and web release builds succeeded.
- The development database was backed up before migration 004. Existing purchase identifiers, ownership, amounts and dates were verified unchanged.
- On the connected Samsung SM-A725F, the user completed the native enablement prompt. The setting then reported enabled. **Lock app** returned to sign-in. After a full process restart, a fingerprint login renewed the session successfully (`POST /auth/biometric/refresh` returned 200) and the phone returned to the test account.

Enrollment-change invalidation, physical lockout and other Android models are handled in code but were not exercised on the connected phone. Automated UI tests simulate biometric results; they do not replace the successful physical scan above. iOS biometric login is outside this Android milestone. Local development continues to use the USB-connected API; release deployments require HTTPS.

References: [Android biometric authentication](https://developer.android.com/identity/sign-in/biometric-auth), [Android Keystore](https://developer.android.com/privacy-and-security/keystore), [AndroidX Biometric releases](https://developer.android.com/jetpack/androidx/releases/biometric).
