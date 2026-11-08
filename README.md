# Closer

Your favourite person, right on your home screen. A Flutter app for two people (a couple or two best friends). Photos, notes and doodles appear on the partner's Android home-screen widget, alongside a daily question, a thinking-of-you tap, a shared streak plant, countdowns, memories and a "How well do you know me?" game.

The full product plan is in `Closer — Design & Development Plan (Flutter, Android Google Play).md`.

## Run it

```
flutter run                                         # demo mode, fully on device
flutter run --dart-define=CLOSER_BACKEND=firebase   # Firebase backend (needs setup below)
```

**Demo mode** (the default) needs no cloud setup. Data is stored on the device, and a simulated partner ("Sam" in couple mode, "Alex" in best-friends mode) joins your invite after a few seconds. They also:
- send notes back and tap your heart,
- answer the daily question and take their turn in games.

This lets you exercise the whole loop on one emulator, including widget updates and notifications. In demo mode, "Closer Plus" can be switched on and off from the paywall without a real charge. The rewarded ad is a 5-second simulation.

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
| `android/app/src/main/kotlin/app/closer/widget` | Glance widgets (photo, countdown, plant) + WorkManager refresh |
| `functions/` | Cloud Functions (TypeScript) |
| `firestore.rules`, `storage.rules`, `firestore.indexes.json` | Security rules + indexes |
| `schema/` | JSON Schemas shared by app and functions |
| `web/` | Hosting: landing, privacy, terms, delete-account, invite fallback, assetlinks |

## Firebase setup (to switch off demo mode)

1. Create a Firebase project on the Blaze plan. Put Firestore in **eur3** (this cannot be changed later) and Storage in the EU. Put the project id in `.firebaserc`.
2. Enable the Google sign-in provider.
3. Add the Android app `app.closer.widget` with its SHA-1 and SHA-256 fingerprints (debug, upload and Play signing keys).
4. Run `flutterfire configure`, then pass `DefaultFirebaseOptions.currentPlatform` to `Firebase.initializeApp` in `FirebaseBackend.init()` and in `fcm_background.dart` (both are marked with `TODO(setup)`).
5. Install Node 22 and the Firebase CLI, then:
   ```
   cd functions && npm install && npm run build
   ```
   The TypeScript has not been compiled yet, so expect small type fixes on the first build.
6. Set the RevenueCat secret: `firebase functions:secrets:set REVENUECAT_WEBHOOK_AUTH`.
7. Deploy:
   ```
   firebase deploy --only firestore:rules,firestore:indexes,storage,functions,hosting
   ```
8. Put the Play signing SHA-256 into `web/.well-known/assetlinks.json` and point `closer.app` at Firebase Hosting.

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
