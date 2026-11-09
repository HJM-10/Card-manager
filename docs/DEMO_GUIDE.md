# SpendTrail demonstration guide

This is a semester-prototype demonstration using fictional PKR transactions,
a local FastAPI/PostgreSQL backend and a USB-connected Android phone. Payments
are simulated. The packaged APK uses release-mode compilation and the existing
debug signing certificate for local review; it is not a store-distribution build.

## Before presenting

1. Follow [setup and installation](SETUP_GUIDE.md). Connect the Samsung phone,
   accept USB debugging if prompted and configure `adb reverse tcp:8000 tcp:8000`.
2. Start PostgreSQL, the API and, when showing phone alerts, the FCM worker.
   Confirm the API's `/health` returns `{"status":"ok"}`.
3. Use a **fresh presenter account** for the exact totals below. Choose your own
   email/password; do not publish a real account's credentials in the slides.
4. Keep all scripted purchase dates in the selected demonstration month.
   For this script, choose November 2026. Refund dates must follow purchases.
5. Make sure the phone has internet access for Firebase, even though its API
   connection is through USB. Enable transaction alerts before recording the
   purchase used for the notification demonstration.

The sample CSV contains three November 2026 purchases totaling **PKR 5,649.50**.
Run this script once per fresh account/card. Repeat imports and safe request
retries are intentionally demonstrated; manually recording another purchase
with a new reference creates a new record.

## Suggested 10–12 minute demonstration

| Step | Action | Expected result / explanation |
| --- | --- | --- |
| 1 · Account and persistence | Register, then open Cards → Account card profiles. Add a fictional Visa profile, last four 4242, future expiry. | Only fictional masked metadata is saved. No banking connection or real payment details are needed. |
| 2 · Manual purchase | Home → Account purchases → Record purchase. Enter Corner Market, PKR 1,250.05, Groceries, POS, 5 November 2026. | One approved manual purchase appears in history and detail. Explain exact decimal storage and server ownership. |
| 3 · CSV validation | Import CSV → choose the card → Try sample CSV → Preview. | Three valid rows, no duplicates, total PKR 5,649.50. Confirm only after reviewing the preview. |
| 4 · Repeat import | Preview/confirm the same sample again. | No new purchases; the confirmed receipt or duplicate handling prevents re-import. Current net spending is PKR 6,899.55. |
| 5 · Approved simulation | Simulate purchase: Coffee, PKR 300.00, Food, online, 10 November. Choose Approved. | It is a fictional approved purchase. Net spending becomes PKR 7,199.55. |
| 6 · Declined simulation | Simulate a PKR 900.00 purchase, 11 November, with Declined. | It appears in history with its status but adds zero spending. |
| 7 · Partial refund | Open Corner Market → Simulate refund → PKR 250.05, 12 November. | Refund links to the original purchase. Net spending becomes **PKR 6,949.50**. Refunds cannot exceed the remaining approved purchase amount. |
| 8 · Search and filters | Search Corner; combine card/category/date filters, then clear them. Open the refund and its original purchase. | Filtering happens on the account's server history. Approved/declined and purchase/refund types remain distinguishable. |
| 9 · Budget and reports | Statistics → November 2026 → All cards. Set Groceries budget PKR 1,500.00. | Groceries spent PKR 1,000.00; remaining PKR 500.00; progress 66.67%. All-card monthly net total PKR 6,949.50. |
| 10 · Restart / fingerprint | Profile → enable Fingerprint login and complete the scan. Lock/restart, then Sign in with fingerprint. | User performs the physical scan. Previously saved account data remains. Password fallback is available. |
| 11 · Alert and transaction link | With alerts enabled, record a new clearly labeled fictional purchase, background the app, and tap its alert. | Generic phone notification opens the associated purchase after authentication. This adds a record; show the fixed report totals **before** this optional extra purchase. |
| 12 · Isolation | Sign out and sign in to a second presenter account. | The first account's cards, history and budgets are inaccessible. Return to the presenter account if continuing. |

For an accessibility demonstration, show the named navigation controls and
alert button, enlarge phone text, open saved history, then restore the phone's
original text size. The app supports scrolling forms and keyboard activation;
reduced-motion settings skip the animated startup sequence.

## Database evidence to show alongside the phone

Open these repository documents rather than running destructive experiments
against the presentation account during the talk:

- [Audit history protection](MILESTONE_09.md): actual restricted login and
  rejected audit modification attempts.
- [Index evaluation](DATABASE_EVALUATION.md): two dataset sizes, independent
  repeat, raw plans and real timings/sizes. Explain why the extra history index
  was not selected and why broad JSON queries did not benefit from GIN.
- [Concurrency and rollback](CONCURRENCY_ROLLBACK.md): eight matching requests
  commit once, native duplicate constraints, refund ceiling, and injected CSV
  failure with no partial records.
- [Backup/restoration](BACKUP_RESTORE.md): actual archive restored into a
  separate database, matching data fingerprints, reports and audit privileges.

## Troubleshooting during the demonstration

| Symptom | Recovery |
| --- | --- |
| Cannot reach SpendTrail | Keep the API running, reconnect USB and reapply `adb reverse`. Confirm `/health` on the computer. |
| No alert | Check phone internet, app permission, Profile → Transaction alerts and the worker's Firebase configuration. A saved purchase is independent of delivery. |
| App asks for sign-in after restart | Sign in with fingerprint if enrolled, otherwise use the presenter password. Access tokens are kept in memory. |
| A total differs from this script | Check the selected month/card, transaction dates, extra manual purchases and whether the account/card was fresh. Refunds count in their own month. |
| CSV is already confirmed | This is expected on a repeated import. Use a fresh account/card for the full first-import demonstration. |
| APK update is rejected | Confirm the package and signing key match the installed version. Avoid uninstalling the current app unless you intend to reset its device-local preferences. |

No NFC hardware, bank feeds, real fund transfer, account recovery or public
production hosting is part of this prototype's demonstration scope.
