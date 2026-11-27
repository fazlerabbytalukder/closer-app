# Duosy

Your favourite person, right on your home screen. A Flutter app for two people (a couple or two best friends). Photos, notes and doodles appear on the partner's Android home-screen widget, alongside a daily question, a thinking-of-you tap, a shared streak plant, countdowns, memories and a "How well do you know me?" game.

The full product plan is in `Duosy — Design & Development Plan (Flutter, Android Google Play).md`.

## Run it

```
flutter run                                         # demo mode, fully on device
flutter run --dart-define=CLOSER_BACKEND=firebase   # Firebase backend (needs setup below)
```

**Demo mode** (the default) needs no cloud setup. Data is stored on the device, and a simulated partner ("Sam" in couple mode, "Alex" in best-friends mode) joins your invite after a few seconds. They also:
- send notes back and tap your heart,
- answer the daily question and take their turn in games.

This lets you exercise the whole loop on one emulator, including widget updates and notifications. In demo mode, "Duosy Plus" can be switched on and off from the paywall without a real charge. The rewarded ad is a 5-second simulation.

## Layout

| Path | What |
| --- | --- |
| `lib/core/models` | Data models (mirror the Firestore model, plan §6) |
| `lib/core/data/closer_backend.dart` | The backend interface the app uses |
| `lib/core/data/local` | On-device backend + simulated partner |
| `lib/core/data/firebase` | Firebase backend + FCM background handler |
| `lib/core/services` | Widget bridge (`home_widget`), notifications, live sync, ads |
| `lib/core/services/widget_contract.dart` | Keys shared with the Kotlin widgets |
| `lib/app` | Router (`go_router` with onboarding redirects), providers (Riverpod), theme setup |
| `lib/features` | Screens: onboarding, home, send, together, memories, me, premium |
| `android/app/src/main/kotlin/com/duosy/app` | Glance widgets (photo, countdown, plant) + WorkManager refresh |
| `functions/` | Cloud Functions (TypeScript) |
| `firestore.rules`, `storage.rules`, `firestore.indexes.json` | Security rules + indexes |
| `schema/` | JSON Schemas shared by app and functions |
| `web/` | Hosting: landing, privacy, terms, delete-account, invite fallback, assetlinks |

## Firebase setup (to switch off demo mode)

Done so far (project `duosy-f5bc2`, still on the Spark plan): Google sign-in enabled, Firestore in **eur3**, Android app `com.duosy.app` registered with the debug SHA-1/SHA-256, `flutterfire configure` run, Firestore rules and indexes deployed.

1. Upgrade to the Blaze plan, then create the Storage bucket in `europe-west1`.
2. Add the upload and Play signing SHA-1/SHA-256 fingerprints once the release keystore exists, then re-download `google-services.json`.
3. Re-run `flutterfire configure` only if apps or fingerprints change.
4. Deploy the `taps.expireAt` TTL policy with the indexes (needs billing).
5. Install Node 22 and the Firebase CLI, then:
   ```
   cd functions && npm install && npm run build
   ```
6. Set the RevenueCat secret: `firebase functions:secrets:set REVENUECAT_WEBHOOK_AUTH`.
7. Deploy:
   ```
   firebase deploy --only firestore:rules,firestore:indexes,storage,functions,hosting
   ```
8. Put the Play signing SHA-256 into `web/.well-known/assetlinks.json` and point `closer.app` at Firebase Hosting.

## Local backend (Firebase Emulator Suite)

Runs the real backend (Auth, Firestore, Functions, Storage, rules) on your PC.
No billing needed: the app keeps the real project's id (`duosy-f5bc2`) but every service points at your PC.

Needs Node, the Firebase CLI (`npm install -g firebase-tools`) and Java 21+
(Android Studio's bundled JBR works).

1. Build the functions once (again after each change in `functions/src`):
   ```
   cd functions && npm install && npm run build
   ```
2. Start the emulators from the project root. PowerShell:
   ```
   $env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
   firebase emulators:start --project duosy-f5bc2
   ```
   The Emulator UI (users, Firestore data, files, function logs) is at http://127.0.0.1:4000.
3. Run the app against them:
   ```
   flutter run --dart-define=CLOSER_BACKEND=firebase --dart-define=CLOSER_EMULATOR_HOST=<host>
   ```
   `<host>` is `10.0.2.2` on the Android emulator, or your PC's Wi-Fi IPv4
   address (`ipconfig`) on a real phone on the same network. Allow Node and
   Java through Windows Firewall on private networks when asked.

How it differs from a real project:
- "Continue with Google" signs in a test account (`Tester XXXX`) without a
  Google prompt. Each install is its own person, so two phones can pair.
- No push notifications or home-screen widget updates from the partner (FCM
  has no emulator). Open the app to see new items.
- Scheduled functions (daily question, streaks, reminders, capsule unlocks,
  cleanup) don't run on their own. Call one by hand from
  `firebase functions:shell --project duosy-f5bc2`.
- Data is wiped when the emulators stop. Add
  `--import=.emulator-data --export-on-exit` to keep it.
- Cleartext HTTP is allowed in debug builds only (`android/app/src/debug/AndroidManifest.xml`).

## Pairing and relationship

One person taps **Invite your person** and sends the 6-character code (or link). The other taps **I have a code** and enters it, and the two are connected as a couple or as best friends, whichever the inviter chose. During onboarding each person can also say what the other is to them (girlfriend, boyfriend, partner, wife, husband, fiancé(e), best friend, BFF, bestie, sibling).

**Settings → Relationship** lets each person change:
- the relationship type (shared by both),
- what they call their partner,
- a private nickname that replaces the partner's name in their own app and widget,
- the "together since" date, which can also become a yearly anniversary countdown.

Pairing two real phones needs the Firebase backend. In demo mode the partner is simulated.

## Monetization (switched off)

Subscriptions, the paywall, free-tier limits and ads are **off** for now: everything is free and unlimited. The code is still there. To turn it back on, set:
- `AppConfig.monetizationEnabled = true` in `lib/core/config.dart`,
- `MONETIZATION_ENABLED = true` in `functions/src/common.ts`,
- `monetizationEnabled()` to `true` in `firestore.rules`.

Then wire RevenueCat and AdMob.

## Not wired yet

- **RevenueCat** (`purchases_flutter`) and **AdMob** (`google_mobile_ads` + UMP consent). Both need real API keys and ad unit ids. The paywall and ad slots exist behind `lib/core/services/ads.dart` and `paywall_screen.dart`.
- **German, French and Spanish translations.** Strings are currently English and inline. The Material localization delegates are already set up.
- **Crashlytics, Analytics, Remote Config and App Check.** Add these after `flutterfire configure`.
- **An offline send queue.**

## Tests

```
flutter test
flutter analyze
```
