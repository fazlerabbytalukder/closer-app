# Duosy — Setup & Launch Checklist

What's left to turn Duosy from an offline demo into a real, published app.
Tick items off as you go (`- [x]`) and note who did them.

---

## Where things stand

- The app runs in **offline demo mode** by default (`flutter run`): one
  phone, data stored on the device, with a **simulated partner**.
- The **real backend is fully written** but not connected: Firebase login,
  chat, pairing, push notifications, Cloud Functions, Firestore/Storage rules.
- Nothing Firebase-specific exists yet:
  - `.firebaserc` still says `REPLACE_WITH_FIREBASE_PROJECT_ID`
  - no `android/app/google-services.json`
  - no `ios/Runner/GoogleService-Info.plist`
  - no `lib/firebase_options.dart`
- Release builds are signed with the **debug key** (`android/app/build.gradle.kts`).
- Monetization (Duosy Plus, ads) is built but **switched off**
  (`AppConfig.monetizationEnabled = false` in `lib/core/config.dart`, and
  `MONETIZATION_ENABLED` in `functions/src/common.ts`).

Run with the real backend once set up:

```sh
flutter run --dart-define=CLOSER_BACKEND=firebase
```

---

## 1. Required — two real phones talking

| # | Task | Owner | Output |
|---|------|-------|--------|
| 1 | Create a **Firebase project** at https://console.firebase.google.com | | Project ID |
| 2 | Upgrade the project to the **Blaze (pay-as-you-go) plan**. Needed for Cloud Functions, the scheduled jobs and Storage. Usually ~$0–2/month at small scale; **set a budget alert**. | | — |
| 3 | Enable **Authentication → Sign-in method → Google** | | — |
| 4 | Create **Firestore** (production mode) — pick a region close to users and keep it the same as `REGION` in `functions/src/common.ts` | | — |
| 5 | Enable **Storage** | | — |
| 6 | **Cloud Messaging** is on by default — just confirm it | | — |
| 7 | Decide the **Android package name**: keep `app.closer.widget` or change it now (it can never change after publishing) | | Package name |
| 8 | Add an **Android app** in Firebase with that package name | | `google-services.json` |
| 9 | Add the **SHA-1 and SHA-256 fingerprints** (debug + release) to the Firebase Android app — **Google login fails without them**. Get them with `cd android && ./gradlew signingReport` | | — |
| 10 | Install and log in to the CLIs:<br>`npm i -g firebase-tools`<br>`firebase login`<br>`dart pub global activate flutterfire_cli` | | — |

### Then, in the code

- [ ] Put the project ID in `.firebaserc` (`"default": "<project-id>"`)
- [ ] Run `flutterfire configure` → creates `lib/firebase_options.dart` and places `google-services.json`
- [ ] Pass `DefaultFirebaseOptions.currentPlatform` to `Firebase.initializeApp(...)` — see the `TODO(setup)` notes in:
  - `lib/core/data/firebase/firebase_backend.dart`
  - `lib/core/data/firebase/fcm_background.dart` (two places)
- [ ] Install the functions dependencies and check they compile:
  ```sh
  cd functions
  npm install
  npx tsc --noEmit
  npm run lint   # if configured
  ```
- [ ] Deploy everything:
  ```sh
  firebase deploy --only firestore:rules,firestore:indexes,storage,functions
  ```
  The new Firestore indexes take a few minutes to build. The hourly
  `chatCleanup` job (disappearing messages) won't delete anything until they're ready.
- [ ] Test on **two real Android phones** with `--dart-define=CLOSER_BACKEND=firebase`:
  - [ ] Google sign-in and pairing with an invite code
  - [ ] Chat: text, photo, voice, reactions, reply, delete
  - [ ] Snaps (opens once or twice, file deleted after the last view)
  - [ ] Screenshot alert (Android 14+) and "saved a photo" alert
  - [ ] Chat heads / bubbles (Android 11+) — from a push with the app closed, and from the "pop out" button
  - [ ] Disappearing messages: 24h default, change the setting, "after viewing"
  - [ ] Home-screen widgets update when the partner sends something

---

## 2. Required — publishing on Google Play

| # | Task | Owner | Notes |
|---|------|-------|-------|
| 11 | Create a **release signing key** (upload keystore) and wire it into `android/app/build.gradle.kts` through `android/key.properties`. **Back up the keystore and passwords somewhere safe** — if they're lost, the app can never be updated. Never commit them to git. | | Add its SHA-1/SHA-256 to Firebase (step 9) |
| 12 | **Google Play Console** developer account ($25 one-time) | | |
| 13 | **Privacy policy URL** — required because the app uses camera, microphone, location, photos and notifications | | Also fill in Play's "Data safety" form |
| 14 | Store listing: icon, screenshots, short/long description, content rating | | |
| 15 | Play App Signing: after the first upload, add **Play's app-signing SHA-1/SHA-256** to Firebase too, or Google login breaks for Play installs | | |
| 16 | **GitHub push access** — the contributor account needs write access to the repo (the last push was refused with a 403) | Repo owner | |

---

## 3. Needed — invite links

| # | Task | Owner | Notes |
|---|------|-------|-------|
| 17 | A **domain for invite links**. The code uses `https://closer.app/i/<CODE>` (`INVITE_BASE_URL` in `functions/src/pairing.ts` and the App Links intent filter in `android/app/src/main/AndroidManifest.xml`). Use a domain you own, or switch to free Firebase Hosting (`<project>.web.app`). | | |
| 18 | Host `/.well-known/assetlinks.json` on that domain (with the release + Play signing SHA-256) so links open the app directly | | |

---

## 4. Only if supporting iPhone

| # | Task | Owner | Notes |
|---|------|-------|-------|
| 19 | **Apple Developer Program** ($99/year) and a Mac with Xcode | | |
| 20 | Add an **iOS app** in Firebase | | `GoogleService-Info.plist` |
| 21 | Upload an **APNs auth key (.p8)** in Firebase → Project settings → Cloud Messaging | | Without it, iPhones get no notifications |
| 22 | Add the reversed client ID URL scheme for Google Sign-In to `ios/Runner/Info.plist` | | |
| 23 | Add **Sign in with Apple** — App Store review rejects apps that offer Google login without it | Dev work | |
| 24 | iOS **home-screen widgets** don't exist yet (Android only) — separate WidgetKit work | Dev work | |
| 25 | **Chat heads** are Android-only (iOS doesn't allow them); screenshots can't be blocked on iOS (only detected) | — | Platform limitation |

---

## 5. Optional — later

- [ ] **Monetization**: RevenueCat account + Play/App Store products, AdMob account + ad unit IDs. Then flip `monetizationEnabled` / `MONETIZATION_ENABLED` to `true`. The `TODO(prod)` in `functions/src/items.ts` (AdMob server-side verification) is required before turning on rewarded ads.
- [ ] **More login options** (email/password, phone) — only Google exists today.
- [ ] **Video** in chat and snaps — chat is photo, voice and text only.
- [ ] **Crash reporting / analytics** (e.g. Firebase Crashlytics).

---

## Notes for contributors

- **Gradle memory**: keep `-Xmx3G` in `android/gradle.properties` — 8G crashed the Gradle daemon on a 16 GB machine.
- **Code style**: Dart is formatted at **120 columns** — use `dart format -l 120 <files>` and only on files you changed.
- **Local plugin**: `packages/closer_bubbles` (Android chat heads, Java) is a path dependency — no publishing needed.
- **Deploy order for chat changes**: deploy `functions` together with releasing the new app version. Chat pushes are now data messages on Android, so older app versions won't show chat notifications.
- **Demo mode limitation**: the chat-head window and the main app keep separate copies of demo data, so they can get out of sync. Firebase mode isn't affected.
- **Never commit secrets**: `google-services.json` is fine to commit for most teams, but the keystore, `key.properties`, `.env` files and service-account keys must stay out of git.
