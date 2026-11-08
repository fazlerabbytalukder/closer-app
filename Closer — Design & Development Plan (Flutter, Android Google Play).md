# Closer — Design & Development Plan (Flutter, Android / Google Play)

Nov 8, 2026 · @Tdevs

> **One line:** your favourite person, right on your home screen. A free app that connects two people (a couple or two best friends). A photo, note or doodle sent by one person appears on the other person's **Android home-screen widget** in seconds, plus daily rituals (daily question, thinking-of-you tap, streak + shared plant, memories).

- **Platform (v1):** Android, published on Google Play
- **Framework:** Flutter (latest stable, Dart 3) for the app; **Kotlin + Jetpack Glance** for the home-screen widgets
- **Audience:** 18–40, US and Europe
- **Languages:** English at launch, then German, French, Spanish
- **Business model:** Free with ads + Closer Plus subscription (one subscription covers both partners) + one-time sticker/theme packs

**What changes from the React Native plan:** the product, features, backend, data model, design and release plan stay the same. Only the mobile app is rebuilt. The app UI moves to Flutter and Dart. The home-screen widgets become small native Kotlin widgets, because Flutter cannot draw Android widgets directly. A Flutter-to-native bridge (`home_widget`) passes data between the two. Everything that runs on Firebase is reused as is.

## 1. Goals and success metrics

The targets do not change with the framework. Flutter should help most with crash-free users and smooth animations.

| Goal | Metric | Target (first 3 months) |
| --- | --- | --- |
| Pairs actually form | % of installs that complete pairing | ≥ 55% |
| Pairing is fast | Median time from install to paired | < 2 min |
| Widget is the habit | % of paired users with a widget on home screen | ≥ 60% |
| Daily use | D1 / D7 / D30 retention (paired users) | 50% / 30% / 18% |
| Rituals work | Pairs answering the daily question (both) per day | ≥ 35% of DAU pairs |
| Revenue | Paywall → trial conversion | ≥ 4% |
| Quality | Crash-free users | ≥ 99.5% |
| Smoothness | Frames rendered without jank (Flutter DevTools / Play vitals) | ≥ 98% |
| Delivery speed | Send → partner widget updated (p50 / p90) | < 5 s / < 30 s |

## 2. Scope: v1.0 vs later

All 13 features stay planned. The **core loop** (pair → send → widget → reply) must be excellent before anything else.

| # | Feature | v1.0 (launch) | v1.1 | Notes |
| --- | --- | --- | --- | --- |
| 1 | Pairing (code + link) | ✅ |  | Couple / best-friend mode |
| 2 | Home-screen widgets (photo, countdown, streak; S/M/L) | ✅ |  | Native Kotlin (Glance) — built first |
| 3 | Send photos, notes, doodles | ✅ |  | 10/day free, unlimited Plus |
| 4 | Daily question (reveal when both answer) | ✅ |  | 1 free/day; extra packs Plus |
| 5 | Thinking-of-you tap | ✅ | Custom taps |  |
| 6 | Mood, status, distance | ✅ mood + status | Distance | Distance needs location policy work |
| 7 | Countdowns | ✅ | Gift ideas | 3 free, unlimited Plus |
| 8 | Streak + shared plant | ✅ | More plant species | Plant wilts, never dies |
| 9 | Memories scrapbook | ✅ | Export as PDF/video | 30 days free, forever Plus |
| 10 | Games & quizzes | ✅ "How well do you know me?" | More games | Themed packs Plus |
| 11 | Widget themes & stickers | ✅ basic | Seasonal paid packs |  |
| 12 | Premium + ads | ✅ | Price tests | RevenueCat + AdMob |
| 13 | Account, privacy, settings | ✅ | DE/FR/ES |  |

**Out of scope for v1:** iOS (Flutter app runs on iOS, but widgets need a native Swift WidgetKit extension — planned for v2), chat, groups larger than two, web app.

## 3. Tech stack

Every React Native library has a Flutter replacement. The biggest change is the widget layer, which moves to native Kotlin.

### Mobile app (Flutter)

| Area | Flutter choice | Replaces (React Native) | Why |
| --- | --- | --- | --- |
| Framework | **Flutter stable + Dart 3 (Impeller renderer)** | React Native + Expo | One codebase, smooth 60/120 fps animations, strong tooling |
| Language | Dart (null-safe, strict lints via `very_good_analysis`) | TypeScript | Type safety and fast hot reload |
| Navigation | `go_router` | Expo Router | URL-based routes, so invite deep links map cleanly |
| Android widgets | **Native Kotlin + Jetpack Glance**, bridged with **`home_widget`** | `react-native-android-widget` | Flutter cannot draw home-screen widgets; Glance is Google's modern widget toolkit |
| State management | **Riverpod** (`flutter_riverpod` + `riverpod_generator`) | TanStack Query + Zustand | One tool for server state, caching and app state |
| Data models | `freezed` + `json_serializable` | TypeScript types + zod | Immutable models, safe JSON parsing |
| Local storage | `shared_preferences` (via `home_widget`) for widget state; Firestore offline cache for app data | `react-native-mmkv` | The native widget can read SharedPreferences directly |
| Firebase SDK | FlutterFire: `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage`, `cloud_functions`, `firebase_messaging`, `firebase_analytics`, `firebase_crashlytics`, `firebase_remote_config`, `firebase_app_check`, `firebase_performance` | `@react-native-firebase/*` | Official Firebase plugins, background messaging supported |
| Sign-in | `google_sign_in` (Credential Manager on Android) | `@react-native-google-signin` | Google sign-in required by the spec |
| Camera / gallery | `image_picker` (uses the Android Photo Picker), `camera` only if a custom camera is needed | `expo-camera`, `expo-image-picker` | Photo Picker avoids the broad photo permission |
| Crop / compress | `image_cropper`, `flutter_image_compress` | `expo-image-manipulator` | Crop to widget ratio, shrink before upload |
| Doodles | `CustomPainter` (+ `perfect_freehand` for smooth strokes), export with `RepaintBoundary.toImage()` | `@shopify/react-native-skia` | Flutter already draws with Skia/Impeller — no extra library needed |
| Animations | Built-in animations, `flutter_animate`, `lottie` (optionally `rive` for the plant) | Reanimated, `lottie-react-native` | Heart tap, plant growth, reveal animations |
| Haptics / vibration | `HapticFeedback` (built-in), `vibration` for custom patterns | `expo-haptics` | Soft buzz on send, custom tap patterns |
| Images | `cached_network_image` | `expo-image` | Caching and placeholders |
| Local notifications | `flutter_local_notifications` | (Expo notifications) | Channels, BigPicture style, quiet display |
| i18n | `flutter_localizations` + `intl` + ARB files (`gen-l10n`) | `i18next` | Built-in, type-safe strings |
| Subscriptions & IAP | **RevenueCat** (`purchases_flutter`, optionally `purchases_ui_flutter`) | `react-native-purchases` | Same RevenueCat project, same webhooks |
| Ads | `google_mobile_ads` (includes Google UMP consent) | `react-native-google-mobile-ads` | Banner + rewarded; EU consent |
| Location (v1.1) | `geolocator` (foreground, coarse) | `expo-location` | Optional distance only |
| Other | `share_plus`, `in_app_review`, `path_provider`, `url_launcher`, `app_links` | Expo equivalents | Share cards, review prompt, files, links |

### Native Android widget layer (Kotlin)

| Area | Choice |
| --- | --- |
| Widget UI | Jetpack Glance (`androidx.glance:glance-appwidget`, `glance-material3`) |
| Data from Flutter | `HomeWidgetGlanceState` / SharedPreferences written by `home_widget` |
| Background refresh | WorkManager (periodic refresh, midnight countdown refresh) |
| Images | Decode the local thumbnail file with downsampling to stay inside the widget bitmap limit |

### Backend (unchanged)

| Area | Choice |
| --- | --- |
| Auth | Firebase Authentication (Google provider) |
| Database | Cloud Firestore (EU region, e.g. `eur3` — pick once, cannot change) |
| Files | Cloud Storage for Firebase |
| Server logic | Cloud Functions for Firebase (2nd gen, Node.js, TypeScript) |
| Push | Firebase Cloud Messaging (FCM) |
| Scheduled jobs | `onSchedule` functions |
| Image thumbnails | Function with `sharp` |
| Config / flags | Firebase Remote Config |
| Abuse protection | Firebase App Check (Play Integrity) |
| Website | Firebase Hosting: landing, privacy, terms, account deletion, `/.well-known/assetlinks.json` |

> Invite links use **Android App Links on our own domain** (e.g. `https://closer.app/i/ABC123`), handled by `go_router` + `app_links`, with a fallback web page that sends people to the Play Store. (Firebase Dynamic Links is shut down.)

### Tooling

- Flutter CLI + Android Studio (needed for the Kotlin widget code)
- Builds: **Codemagic** or GitHub Actions + **fastlane** to build the AAB and upload to Play (replaces EAS Build / Submit)
- Over-the-air fixes: **Shorebird** code push for Dart-only fixes, used carefully (replaces EAS Update); native widget changes always need a store release
- `dart format`, `very_good_analysis` lints, `build_runner` for code generation, pre-commit hooks via `lefthook`
- Tests: `flutter_test`, `mocktail`, golden tests, `integration_test` + **Patrol** for end-to-end (Maestro also works)
- Firebase Emulator Suite for backend + rules tests
- GitHub Actions: analyze, format check, tests, rules tests on every PR
- Design: Figma

## 4. System architecture

The server side is identical to the React Native plan. On the receiving phone, a Dart background handler saves the data and the native Kotlin widget draws it.

```
┌──────────────────────── Phone A (sender) ─────────────────────────┐
│ Flutter app                                                        │
│  ├─ Upload photo → Cloud Storage (pairs/{pairId}/raw/…)           │
│  └─ call sendItem() (callable function)                            │
└───────────────────────────────┬────────────────────────────────────┘
                                │
                ┌───────────────▼────────────────┐
                │ Firebase                        │
                │  Cloud Functions                │
                │   • check free limit (10/day)   │
                │   • make widget thumbnail       │
                │   • write item to Firestore     │
                │   • update pair.latestItem      │
                │   • update streak / plant       │
                │   • send FCM data message → B   │
                └───────────────┬────────────────┘
                                │ high-priority data message
┌───────────────────────────────▼────────────────────────────────────┐
│ Phone B (receiver) — app can be closed                             │
│  Dart background isolate (FirebaseMessaging.onBackgroundMessage)   │
│   ├─ download widget thumbnail → app files folder                 │
│   ├─ HomeWidget.saveWidgetData(...)  → SharedPreferences           │
│   ├─ HomeWidget.updateWidget(...)    → triggers native widget      │
│   └─ show soft notification (flutter_local_notifications)          │
│  Native Kotlin Glance widget                                       │
│   └─ reads SharedPreferences + local file → draws on home screen  │
└────────────────────────────────────────────────────────────────────┘
```

**Key principle (unchanged):** anything with a limit, a reward or a secret (send limits, daily question reveal, streaks, premium status) is decided **on the server**, never only in the app.

## 5. How the widget works (the critical path)

Flutter draws the app, but Android home-screen widgets must be native. So each widget is a small **Kotlin + Jetpack Glance** widget, and Flutter only sends it data through `home_widget`. **Build a technical spike in week 1** that proves: send from phone A → widget on phone B updates while B's app is closed.

### 5.1 Widget types

| Widget (Kotlin class) | Sizes | Shows | Tap action |
| --- | --- | --- | --- |
| `PartnerPhotoWidget` — photo / note / doodle | S (2×2), M (4×2), L (4×4) | Partner's latest item, caption, sender, "2m ago", heart badge after a tap | Opens quick-reply screen (`closer://reply`) |
| `CountdownWidget` | S, M | Next date: big number + label ("12 days to Paris") | Opens countdowns |
| `PlantWidget` — streak / plant | S, M | Plant illustration at current stage + streak count | Opens plant screen |

Glance uses `SizeMode.Responsive` so one widget class serves all three sizes.

### 5.2 Who does what

| Part | Written in | Job |
| --- | --- | --- |
| Background message handler | Dart | Receives FCM, downloads thumbnail, saves data, asks the widget to refresh |
| `home_widget` plugin | Dart ↔ Kotlin bridge | Writes key-values to SharedPreferences, triggers widget update, handles widget taps and pin requests |
| Glance widgets | Kotlin | Read the saved data and local image file, draw the widget, apply the theme |
| WorkManager worker | Kotlin | Periodic refresh and midnight countdown refresh, even if Flutter never starts |

### 5.3 Update flow

1. Receiver gets an FCM **data-only, high-priority** message: `{ type: "item", pairId, itemId, thumbUrl, caption, senderName, sentAt }`.
2. `FirebaseMessaging.onBackgroundMessage(handler)` runs. The handler is a **top-level function** marked `@pragma('vm:entry-point')` and registered in `main()` before `runApp()`. It runs in a background isolate, so it must call `Firebase.initializeApp()` itself.
3. The handler downloads the **widget thumbnail** (server-made, max \~600 px, JPEG \~80%) to the folder from `path_provider` (`getApplicationSupportDirectory()`).
4. It saves widget state: `HomeWidget.saveWidgetData('latest_path', ...)`, plus caption, sender name, sent time and theme id.
5. It calls `HomeWidget.updateWidget(qualifiedAndroidName: 'app.closer.widget.PartnerPhotoWidgetReceiver')`.
6. The Glance widget reads the values in `provideGlance()`, decodes the image with downsampling and redraws.
7. Widget taps use `home_widget` launch intents with a URI (`closer://reply`). The app reads it with `HomeWidget.initiallyLaunchedFromHomeWidget()` and `widgetClicked`, then `go_router` opens the right screen.

**Optional:** for note and doodle styles that are hard to rebuild in Glance, use `HomeWidget.renderFlutterWidget()` in the app to draw the card as a PNG, then show that image in the widget. Only do this while the app is open (sender preview or on app open), not in the background handler.

### 5.4 Fallbacks (because Android can delay background work)

- **On app open / resume:** sync the latest item and refresh all widgets.
- **Periodic refresh:** WorkManager job (minimum 15 min) plus widget `updatePeriodMillis` (minimum 30 min) re-read state. The countdown widget also refreshes at midnight.
- **Visible notification fallback:** if the data message can't be processed, a BigPicture notification still shows the photo; opening it updates the widget.
- **Battery optimisation help:** an in-app "Widget not updating?" page with device-specific steps (Xiaomi, Oppo, Vivo, Samsung, Huawei).
- **Plan B if the Dart background isolate is too slow on some phones:** move the download-and-save step into native Kotlin (a WorkManager job started by the widget's own receiver), so Flutter does not need to start at all.

### 5.5 Widget constraints to design around

- Glance turns into RemoteViews: basic layouts only, no live animation, limited view types. Fonts must be bundled; for fancy text, render it into the image.
- Bitmap memory limit per widget → always use the small server thumbnail and downsample when decoding.
- Respect Android 12+ rounded corners; offer Material You dynamic colour (`GlanceTheme`) as an option.
- In-app "Add widget to home screen" button using `HomeWidget.requestPinWidget()`, plus a short tutorial for launchers that don't support pinning.
- Theme (frame, colour, font) is part of the saved widget state so themes from feature 11 apply.
- Keep widget layouts in Figma close to what Glance can build, so design and code match.

### 5.6 Spike acceptance criteria

- [ ] Widget updates within 10 s on a Pixel (stock Android) with the app swiped away
- [ ] Widget updates on a Samsung device with the app swiped away
- [ ] Widget survives phone reboot and shows the last item
- [ ] Tapping the widget deep-links into the reply screen (cold start and warm start)
- [ ] Widget bitmap memory stays within limits on a large widget
- [ ] Background isolate start + download + update measured; p90 under 30 s on a mid-range phone

## 6. Data model (Firestore)

The data model is **unchanged**. In Flutter, each collection gets a `freezed` model class with `fromJson` / `toJson`, and Firestore reads use `withConverter<T>()` so the app always works with typed objects.

```
users/{uid}
  displayName, photoUrl, locale, timezone
  pairId | null
  ageConfirmed18: boolean          // gates spicy packs
  mood: { emoji, label, updatedAt }
  status: { text, updatedAt }
  notificationPrefs: { taps, questions, reminders, quietHours: {start, end} }
  fcmTokens: string[]              // managed by functions
  createdAt

invites/{code}                     // 6-char code, e.g. "K7Q2MX"
  inviterUid, mode: "couple" | "friends", expiresAt, usedBy | null

pairs/{pairId}
  memberIds: [uidA, uidB]
  mode: "couple" | "friends"
  pairedAt
  latestItemByUser: { [uid]: { itemId, type, thumbPath, caption, sentAt } }
  streak: { count, best, lastBothActiveDate, freezesLeft, freezesResetAt }
  plant: { stage: 0..N, health: "healthy" | "wilted", species }
  premium: { active, source: "subscription", ownerUid, expiresAt }
  widgetTheme: { [uid]: themeId }
  stats: { itemsSent, questionsAnswered, tapsSent }

pairs/{pairId}/items/{itemId}      // memories scrapbook
  type: "photo" | "note" | "doodle"
  senderId, storagePath, thumbPath, caption (≤ 40 chars)
  noteStyle?: { bg, font }
  saveToMemories: boolean
  createdAt

pairs/{pairId}/taps/{tapId}        // TTL policy 30 days
  senderId, kind: "heart" | customId, createdAt

pairs/{pairId}/dailyQuestions/{yyyy-mm-dd}
  questionId, text, packId
  answeredBy: [uid…]
  revealed: boolean
  answers: { [uid]: text }         // written by function only when both answered

pairs/{pairId}/dailyQuestions/{date}/private/{uid}
  answer, answeredAt               // only the owner can read/write

pairs/{pairId}/countdowns/{id}
  title, date, emoji, repeatsYearly, remindDaysBefore, createdBy

pairs/{pairId}/games/{gameId}
  type: "know-me", packId, questions[], answers: {…}, score, status

usage/{uid}_{yyyy-mm-dd}           // server-only, free limits
  sends

content/questionPacks/{packId}     // admin-managed
content/gamePacks/{packId}
content/themes/{themeId}
content/stickerPacks/{packId}

entitlements/{uid}                 // written by RevenueCat webhook only
  plus: { active, expiresAt }, packs: [productId…]
```

**Storage layout:** `pairs/{pairId}/raw/{itemId}.jpg`, `pairs/{pairId}/thumbs/{itemId}.jpg`, `users/{uid}/avatar.jpg`.

**Indexes:** items by `createdAt desc`; countdowns by `date asc`.

**Keeping app and server in sync:** the app is Dart and the functions are TypeScript, so types are no longer shared. Keep one `schema/` folder with JSON Schema files for each document, and test both the `freezed` models and the zod schemas against the same sample JSON.

## 7. Backend: Cloud Functions

The functions are **reused without changes** (Node.js + TypeScript). The Flutter app calls them with `FirebaseFunctions.instanceFor(region: 'europe-west1').httpsCallable('sendItem')`.

| Function | Trigger | Job |
| --- | --- | --- |
| `createInvite` | callable | Make unique 6-char code + link, 48 h expiry |
| `acceptInvite` | callable | Validate code, create `pairs/{id}`, link both users (transaction) |
| `unpair` | callable | Remove pair link; schedule deletion after export window |
| `sendItem` | callable | Check limit, write item, update `latestItemByUser`, mark daily activity, send FCM |
| `makeThumbnail` | Storage `onObjectFinalized` | Resize to widget size with `sharp`, strip EXIF/GPS |
| `sendTap` | callable | Rate-limit (1 per 10 s), write tap, FCM with vibration channel |
| `submitAnswer` | callable | Save private answer; if both answered → reveal, notify both |
| `assignDailyQuestions` | scheduled (hourly) | Pick next question for pairs whose local day starts this hour |
| `updateStreaks` | scheduled (hourly) | Both active yesterday → +1 and grow plant; else freeze or wilt |
| `countdownReminders` | scheduled (daily) | Notify both before important dates |
| `revenuecatWebhook` | HTTPS | Verify auth header; update `entitlements` and `pairs.premium` |
| `deleteAccount` | callable | Delete user data, storage, unlink pair (Play requirement) |
| `exportMemories` | callable | Zip of photos + JSON, signed URL valid 7 days |
| `registerFcmToken` | callable | Add/refresh device token (call on `onTokenRefresh` in Flutter) |

**One FCM detail to check:** keep item messages **data-only** (no `notification` block). If a message has a `notification` block, Android shows it by itself and the Dart background handler may not get the chance to update the widget. The app shows the notification itself with `flutter_local_notifications`.

"Interaction" for streaks = sending an item, a tap, or answering the daily question. A day counts when **both** people interacted, in the pair's agreed timezone.

## 8. Feature-by-feature implementation

The product behaviour is the same as before. Below, each feature lists how it is built in Flutter.

### F1 · Pairing

- Onboarding: welcome → Google sign-in → name + photo → choose **Couple** or **Best friends** → "Invite your person" (`share_plus` with link + code) or "I have a code".
- Waiting screen uses a Riverpod `StreamProvider` on the user document; confetti (`confetti` package or Lottie) when the partner joins.
- Invite links: `app_links` receives `https://closer.app/i/ABC123`, `go_router` route `/i/:code` calls `acceptInvite`.
- Edge cases: expired code, already paired, pairing with yourself, both inviting at once (server transaction).
- Target: paired in under a minute.

### F2 · Home-screen widgets

- See section 5. Settings → "My widgets": Flutter preview of each widget, "Add to home screen" (`HomeWidget.requestPinWidget`), theme picker, troubleshooting page.

### F3 · Send photos, notes, doodles

- `TabBar` with **Photo / Note / Doodle**. Live preview drawn with the same layout rules as the Glance widget.
- Photo: `image_picker` (camera or Photo Picker) → `image_cropper` to widget ratio → caption (max 40 chars) → stickers/text as positioned overlays.
- Note: coloured card, a few bundled fonts and backgrounds.
- Doodle: `CustomPainter` canvas (pen sizes, colours, undo, eraser); can draw over a photo; export with `RepaintBoundary.toImage()` to PNG.
- Compress with `flutter_image_compress` before upload; upload with `firebase_storage` `putFile` and show progress.
- "Also save to Memories" toggle (on by default).
- Send button: "Send to {name}'s widget" → optimistic UI, `HapticFeedback.mediumImpact()`, offline retry queue (small queue saved locally, retried on reconnect with `connectivity_plus`).
- Counter "7 of 10 left today" for free users; at limit → paywall or rewarded ad for +3.

### F4 · Daily question

- New question at the pair's local morning. Answer privately; partner's answer shows locked (`ImageFiltered` blur + "Waiting for Sam").
- Both answered → reveal animation (`flutter_animate` flip), push to both, emoji reaction.
- Pack picker (Plus): spicy (18+ only), deep talk, long-distance, best-friend pack.
- Share card: build the card as a Flutter widget, capture it with `RepaintBoundary`, share the PNG with `share_plus` (app watermark for growth).

### F5 · Thinking-of-you tap

- Big heart button with scale/bounce animation. Server sends FCM to a dedicated `taps` channel with a soft vibration pattern; widget shows a heart badge for 1 hour (badge expiry time saved in widget state).
- Plus: custom taps (different emojis / vibration patterns via `vibration`).

### F6 · Mood, status, distance

- Mood: emoji grid + label; status presets + custom text; partner's local time shown (`timezone` package).
- Shown on the app home and as an optional line on the medium/large widget.
- Distance (v1.1): opt-in by **both**, `geolocator` foreground coarse location, server stores only a rounded distance.

### F7 · Countdowns

- List with the next date big; add/edit with `showDatePicker`, emoji, yearly repeat, reminder.
- Free: 3; Plus: unlimited + gift ideas from Remote Config.
- After any change, save the next countdown to widget state and call `HomeWidget.updateWidget` for `CountdownWidget`.

### F8 · Streak + shared plant

- Plant stages at milestones (1, 3, 7, 14, 30, 60, 100, 365). Animated in the app with Lottie or Rive; the widget uses a static PNG per stage bundled in the Android `res/drawable` folder.
- Broken streak → plant wilts, "Revive" by interacting today; it **never dies**.
- Streak freezes: 1/month free, 3/month Plus, applied automatically.
- Milestone celebration screen + shareable card.

### F9 · Memories scrapbook

- Timeline grid grouped by month (`CustomScrollView` + `SliverGrid`), Firestore pagination with `startAfterDocument`.
- Free: last 30 days visible; older items blurred with "Unlock with Plus".
- "On this day" card on the home screen.

### F10 · Games & quizzes

- "How well do you know me?": one answers about themselves, the other guesses; score + result screen + share card.
- Turn-based via Firestore streams; push "Sam finished — your turn".

### F11 · Widget themes & stickers

- Theme = frame + colour palette + font + corner style; preview on a fake home screen built in Flutter.
- Theme id is saved into widget state; the Kotlin widget maps it to colours and drawables.
- Rewarded ad: unlock a theme for 24 h (server stores `unlockedUntil`).
- Sticker picker in a bottom sheet; locked stickers show a crown/price.

### F12 · Premium + ads

- See section 11.

### F13 · Account, privacy, settings

- Google sign-in + cloud backup (Firestore/Storage).
- Unpair: confirm → offer export → both notified → data deleted after 7 days or immediately.
- Delete account: in-app **and** web page (Play requirement).
- Age gate before any spicy content; store `ageConfirmed18`.
- Notification controls per type + quiet hours.
- Dark mode (`ThemeMode.system` with override), larger text (respect `MediaQuery.textScaler`, test at 1.3×+).
- Help & feedback form, "Rate us" via `in_app_review` after a positive moment (e.g. 7-day streak).

## 9. UI / UX design plan

The design process and look stay the same. The Figma tokens now map straight into a Flutter `ThemeData` (Material 3) plus a custom `ThemeExtension` for brand colours.

### 9.1 Design process

1. **Week 1:** moodboard (cute, warm, soft), brand name check, logo direction.
2. **Week 1–2:** low-fi wireframes for all screens.
3. **Week 2:** design system in Figma, then hi-fi core-loop screens: onboarding, pairing, home, send, widget states.
4. **Week 2:** clickable Figma prototype → test with 5 couples / 5 friend pairs.
5. Remaining hi-fi screens are designed one phase ahead of development.

### 9.2 Design system → Flutter theme

- **Feel:** soft, rounded, friendly; lots of white space; playful micro-animations.
- **Colours:** primary soft blue `#2F7BE6` / tint `#E6F0FC`, accent pink `#FF6B8A`, plant green `#5DBB63`, warm grey neutrals; full dark palette. Built as `ColorScheme.fromSeed` + a `CloserColors` `ThemeExtension`. Couple mode leans pink, friends mode blue/purple (swap the extension).
- **Typography:** one rounded sans (Nunito or Plus Jakarta Sans), **bundled** in `assets/fonts` (no `google_fonts` network loading); sizes 12/14/16/20/24/32 as a `TextTheme`.
- **Shape:** card radius 20–24, pill buttons (`StadiumBorder`), 8-pt spacing constants.
- **Components (in `lib/core/ui/`):** `CloserButton` (primary/secondary/ghost), `CloserCard`, bottom nav bar, `AvatarPair`, `LockedCard` (blur + lock), `CounterChip`, bottom sheet, toast/snackbar, empty state, paywall card, `WidgetPreviewFrame`.
- **Widget design:** the same tokens are copied into the Kotlin widget code (`colors.xml` / Glance theme), so app and home-screen widget match.
- **Accessibility:** contrast AA, touch targets ≥ 48 dp, `Semantics` labels on every icon button (TalkBack), respect `MediaQuery.disableAnimations`.

### 9.3 Navigation map (`go_router`)

```
Onboarding (redirect while not paired)
  /welcome → /sign-in → /profile → /mode → /invite | /code → /waiting → /widget-tutorial → /notifications

Main tabs (StatefulShellRoute, after pairing)
  ├─ /home       partner card, big heart tap, today's question, streak/plant, next countdown
  ├─ /send       Photo / Note / Doodle (center button)
  ├─ /together   Daily question · Games · Countdowns · Plant
  ├─ /memories   timeline / calendar
  └─ /me         profile, mood & status, widgets & themes, Closer Plus, settings

Full-screen / modal routes
  /paywall · /reply (from widget) · /item/:id · /question-reveal · /milestone · /theme/:id · /i/:code (invite link)
```

A `redirect` in `go_router` sends users to onboarding until signed in and paired, so deep links from widgets and invites always land correctly.

### 9.4 Screen list (hi-fi)

Welcome, Sign-in, Profile setup, Mode choice, Invite, Enter code, Waiting for partner, Paired celebration, Widget tutorial, Home, Send (3 tabs), Sticker picker, Reply, Daily question (answer / waiting / revealed), Question packs, Tap screen, Mood & status, Countdowns list, Countdown edit, Plant & streak, Milestone, Memories timeline, Memory viewer, Game lobby, Game play, Game results, Widget & theme store, Paywall, Settings, Notifications, Privacy & data, Unpair flow, Delete account, Help & feedback, Widget troubleshooting. Plus empty, loading, error and offline states for each.

### 9.5 Widget designs

Design every widget in S/M/L × light/dark × default theme, plus empty states ("Waiting for Sam's first photo 💌") and the "not paired" state ("Open Closer to connect"). Keep to layouts Glance supports (rows, columns, boxes, images, text).

## 10. Project structure

Feature-first folders in `lib/`, and the native widget code in the Android module.

```
closer/
├─ lib/
│  ├─ main.dart                  # Firebase init, FCM background handler registration, runApp
│  ├─ app/                       # App widget, go_router config, theme setup
│  ├─ core/
│  │  ├─ ui/                     # design-system components
│  │  ├─ theme/                  # tokens, light/dark, ThemeExtensions
│  │  ├─ services/               # firebase, messaging (background handler), storage,
│  │  │                          # widget_bridge (home_widget), ads, purchases, analytics
│  │  ├─ models/                 # freezed models shared across features
│  │  └─ utils/
│  ├─ features/                  # pairing, send, widget, question, tap, mood, countdown,
│  │  │                          # streak, memories, games, themes, premium, settings
│  │  └─ <feature>/ data/ (repository) · application/ (providers) · presentation/ (screens, widgets)
│  └─ l10n/                      # app_en.arb, app_de.arb, app_fr.arb, app_es.arb
├─ android/
│  └─ app/src/main/
│     ├─ kotlin/app/closer/widget/
│     │  ├─ MainActivity.kt
│     │  ├─ widgets/             # PartnerPhotoWidget.kt, CountdownWidget.kt, PlantWidget.kt (+ receivers)
│     │  ├─ widgets/ui/          # shared Glance components, theme mapping
│     │  └─ work/                # WidgetRefreshWorker.kt (WorkManager)
│     ├─ res/xml/                # appwidget-provider info files (sizes, previews)
│     ├─ res/drawable/           # plant stages, frames, widget previews
│     └─ AndroidManifest.xml     # widget receivers, App Links intent filter
├─ assets/                       # fonts, Lottie/Rive files, images, stickers
├─ test/                         # unit, widget and golden tests
├─ integration_test/             # Patrol / integration tests
├─ functions/                    # Cloud Functions (TypeScript) — unchanged
│  └─ src/ pairing.ts items.ts questions.ts streaks.ts premium.ts account.ts thumbnails.ts
├─ schema/                       # JSON Schemas shared by app tests and functions
├─ firestore.rules  storage.rules  firestore.indexes.json
├─ web/                          # landing, privacy, terms, delete-account, assetlinks.json
├─ pubspec.yaml  analysis_options.yaml  l10n.yaml
├─ codemagic.yaml or .github/workflows/  fastlane/
└─ plan.md
```

The Android `applicationId` stays **`app.closer.widget`** (or whatever was chosen) — it must never change after the first Play upload.

## 11. Monetization implementation

Pricing and rules are unchanged; only the client libraries change to `purchases_flutter` and `google_mobile_ads`.

### Closer Plus subscription

- Play Console products: `closer_plus_monthly` ($4.99) and `closer_plus_yearly` ($29.99), each with a **7-day free trial**. Test prices with RevenueCat Experiments / Play price experiments.
- Flutter: `Purchases.configure(PurchasesConfiguration(apiKey)..appUserID = firebaseUid)`, show offerings with `Purchases.getOfferings()`, buy with `Purchases.purchasePackage()`. `purchases_ui_flutter` can show a ready-made paywall if we want to save design time.
- **One subscription covers both partners:** the RevenueCat webhook sets `pairs/{pairId}.premium`. The app checks the **pair's** premium status (Firestore stream), not only the local RevenueCat customer info, so the partner gets Plus too.
- If the pair unpairs: Plus stays with the buyer only.
- Paywall at natural limits (11th send, 4th countdown, locked pack, 30-day memory wall) and from the Me tab. Never a hard block at first launch.
- "Restore purchases" (`Purchases.restorePurchases()`) and a manage-subscription link to Play.

### One-time packs

- Non-consumable products per sticker/theme pack (`pack_valentines_2027`, …) via RevenueCat; ownership in `entitlements/{uid}.packs`, shared with the partner.

### Ads (free users only)

- **AdMob banner** (`BannerAd` + `AdWidget`, adaptive size) on non-core screens only (Memories, Together lists) — never on the widget or send screen.
- **Rewarded ads** (`RewardedAd`): unlock a theme for 24 h, +3 sends today, or 1 extra streak freeze. The reward is granted by the server after the ad (use AdMob server-side verification callbacks to a function).
- **Consent:** `ConsentInformation.instance.requestConsentInfoUpdate()` then `ConsentForm.loadAndShowConsentFormIfRequired()` before loading any ad for EEA/UK users. Non-personalised ads if no consent.
- Ads removed immediately when the pair becomes Plus (Riverpod provider on pair premium hides ad widgets).

## 12. Security, privacy and compliance

Server-side rules are unchanged. Two Flutter-specific items are added: App Check activation and keeping secrets out of the Dart bundle.

- **Firestore rules:** a user can only read a pair if `request.auth.uid in resource.data.memberIds`; items readable only by members; `private/{uid}` answers only by that uid; `answers`, `revealed`, `streak`, `plant`, `premium`, `usage`, `entitlements` are **function-only**.
- **Storage rules:** only pair members can read `pairs/{pairId}/…`; uploads limited to images under 10 MB.
- **App Check:** `FirebaseAppCheck.instance.activate(androidProvider: AndroidProvider.playIntegrity)` in release; debug provider in development. Enforced on Firestore, Storage and callable functions.
- **No secrets in the app:** Dart code can be decompiled. Only public keys (Firebase config, RevenueCat public SDK key, AdMob app id) go in the app. Build release with `--obfuscate --split-debug-info` and upload symbols to Crashlytics.
- **Widget data:** SharedPreferences used by the widget holds only the latest caption, name and a local file path — nothing sensitive. Clear it on sign-out and unpair.
- **Encryption:** in transit (TLS) and at rest (Google-managed). Do **not** claim end-to-end encryption unless built (possible v2).
- **Privacy by design:** no public profiles, no search, no strangers; EXIF/GPS stripped from photos; distance only as a rounded number.
- **GDPR:** privacy policy, lawful basis, data export, deletion, EU data region, ad consent.
- **Age:** Play target audience **18+**; age confirmation in onboarding.
- **Content safety:** "Report a problem" and a block/unpair flow.

## 13. Notifications

Channels are created on first launch with `flutter_local_notifications` (`AndroidNotificationChannel`), and the server sends to the matching channel id.

| Channel (Android) | Used for | Default |
| --- | --- | --- |
| `partner_items` | New photo/note/doodle | On, soft sound |
| `taps` | Thinking-of-you (custom vibration) | On, vibration only |
| `daily_question` | New question, answers revealed | On |
| `streak` | "Your plant needs water 🌱" (evening, if not yet active) | On |
| `countdowns` | Reminders before dates | On |
| `game_turns` | Your turn | On |
| `account` | Pairing, unpair, subscription | On |

- Ask for `POST_NOTIFICATIONS` (Android 13+) with `FirebaseMessaging.instance.requestPermission()` **after** pairing, with a short explanation screen first.
- Notification taps: `FirebaseMessaging.onMessageOpenedApp`, `getInitialMessage()` and the local-notifications tap callback all route through `go_router`.
- Quiet hours are checked on the server before sending visible notifications; data messages still update the widget silently.

## 14. Analytics and monitoring

Same events and funnels, sent with `firebase_analytics`.

- **Events:** `sign_up`, `invite_sent`, `invite_accepted`, `pair_created`, `widget_added`, `item_sent{type}`, `tap_sent`, `question_answered`, `question_revealed`, `countdown_created`, `streak_milestone`, `paywall_view{trigger}`, `trial_start`, `purchase`, `ad_reward_earned`, `unpair`.
- **Widget added:** detect with `HomeWidget.getInstalledWidgets()` on app open and log when the count goes up.
- **Funnels:** install → sign-in → invite sent → paired → widget added → first item received.
- **Crashlytics:** set `FlutterError.onError` and `PlatformDispatcher.instance.onError` to record Dart errors; also catch errors in the background message handler and record them as non-fatal. Native Kotlin widget crashes are reported automatically.
- **Performance Monitoring:** custom trace for send-to-widget latency (server timestamp vs time the widget data was saved).
- **Screen tracking:** a `go_router` observer logs screen views.
- **Remote Config** for limits, paywall copy, reward amounts.
- Never send photo content or answers to analytics.

## 15. Testing strategy

Flutter tests cover the app; the native widget needs its own small Kotlin tests and a manual checklist.

| Level | Tools | Focus |
| --- | --- | --- |
| Unit (Dart) | `flutter_test`, `mocktail` | Limit logic in UI, timezone/day display, repositories, providers |
| Widget tests | `flutter_test` | Send screen, paywall, locked states, onboarding |
| Golden tests | `flutter_test` goldens (or `alchemist`) | Design-system components and widget previews in light/dark |
| Native widget | JUnit + Robolectric, `glance-appwidget-testing` | Widget reads saved data correctly, empty/not-paired states, theme mapping |
| Security rules | `@firebase/rules-unit-testing` + emulator | Partner can't read your private answer; strangers can't read pairs |
| Functions | Emulator + Jest | Pairing races, webhook, streak job, timezone boundaries |
| End-to-end | **Patrol** on two emulators (handles system dialogs, notifications, home screen) | Pair → send → receive → widget updates → answer → reveal |
| Device matrix | Real devices | Pixel (stock), Samsung (One UI), Xiaomi (HyperOS), one low-end device; Android 10 → latest |
| Widget QA | Manual checklist | All sizes, light/dark, after reboot, after app killed, launchers (Pixel, One UI, Nova) |
| Performance | Flutter DevTools, profile builds | No jank on low-end phones, app start time, image memory |
| Purchases | Play license testers + RevenueCat sandbox | Trial, renew, cancel, restore, partner sharing |

**SDK levels:** set `minSdk` to **24** (covers Glance and all plugins); `targetSdk` must meet Google Play's current requirement at submission (it rises every August). Use the Flutter-generated Gradle values as a starting point and raise as needed.

## 16. Google Play release checklist

The Play policy work is identical. Only the build and signing steps change.

### Account and setup

- [ ] Google Play Developer account ($25 one-time). **Organisation** account if possible (needs D-U-N-S); **personal** accounts created after Nov 2023 must run a **closed test with at least 12 testers for 14 continuous days** before production.
- [ ] Play App Signing enabled. Create an upload keystore, store it and `key.properties` in CI secrets (never in git), and configure `signingConfigs` in `android/app/build.gradle`.
- [ ] Package name chosen permanently (e.g. `app.closer.widget`). If the React Native version was already uploaded to Play, reuse the **same package name and upload key** so the Flutter build is an update, not a new app.
- [ ] Release build: `flutter build appbundle --release --obfuscate --split-debug-info=build/symbols`.
- [ ] Version: `version: 1.0.0+1` in `pubspec.yaml`; the build number must always go up.

### App content (Policy → App content)

- [ ] Privacy policy URL
- [ ] **Data safety form:** photos, user content, name, email, approx. location (if distance), app activity, device IDs (ads), crash logs; encryption in transit; deletion available
- [ ] **Account deletion:** in-app + web URL
- [ ] Ads declaration: contains ads = yes (also declare the AD\_ID permission, added by `google_mobile_ads`)
- [ ] Target audience: 18+
- [ ] Content rating questionnaire (IARC) — user-generated content between two users, mature question packs
- [ ] Photo & video permissions: use Photo Picker; check the merged manifest has **no** `READ_MEDIA_IMAGES` added by a plugin
- [ ] Location declaration + prominent disclosure (only when distance ships)

### Store listing

- [ ] App name (≤ 30 chars), e.g. "Closer: Couples & BFF Widget" — check trademarks
- [ ] Short description (≤ 80), full description (≤ 4000) with keywords: couples widget, best friend widget, long distance relationship, photo widget
- [ ] Icon 512×512 (`flutter_launcher_icons` for in-app icons), feature graphic 1024×500
- [ ] 6–8 phone screenshots (widget on home screen first!), optional promo video
- [ ] Localised listings for DE/FR/ES when those languages ship
- [ ] Category: Social (or Lifestyle)

### Release tracks

1. Internal testing (team), uploaded by fastlane `supply` from CI
2. Closed testing (≥ 12 testers, 14 days; real couples/friends)
3. Production with **staged rollout** (10% → 50% → 100%), watching Android vitals (ANR < 0.47%, crash < 1.09%)

## 17. Timeline and milestones

Total is still about **18 weeks** to production for **1 full-time Flutter developer (comfortable with basic Kotlin) + 1 part-time designer**. If the backend from the React Native version already exists, weeks 3–4 and parts of 8–10 get shorter.

| Week | Phase | Deliverables |
| --- | --- | --- |
| 1 | **Setup + widget spike** | Flutter project, flavors (dev/prod), FlutterFire config (`flutterfire configure`), CI; Kotlin Glance widget + `home_widget` + FCM background handler spike passes section 5.6; moodboard & wireframes |
| 2 | **Design foundation** | Design system in Figma and as Flutter `ThemeData` + core components; clickable prototype tested with 5–10 pairs |
| 3–4 | **Auth + pairing** | Google sign-in, profile, invites (code + App Link via `app_links`), pairing, rules + tests, onboarding, `go_router` redirects |
| 5–7 | **Core loop** | Send photo/note/doodle, thumbnails, limits, FCM, all 3 Glance widgets in S/M/L, tap, notifications, reply-from-widget, offline queue |
| 8–10 | **Daily rituals** | Daily question + reveal, mood/status, countdowns, streak + plant + freezes, scheduled jobs with timezones |
| 11–12 | **Memories, games, themes** | Scrapbook + "on this day", "How well do you know me?", themes on widgets, stickers |
| 13 | **Monetization** | RevenueCat + Play products, shared pair premium, paywall, AdMob banner + rewarded, UMP consent |
| 14 | **Settings & privacy** | Notification prefs/quiet hours, dark mode, large text, unpair + export, account deletion, age gate, help, in-app review |
| 15 | **QA & polish** | Device matrix, widget QA, performance profiling, accessibility, golden tests, analytics check, store assets |
| 16–17 | **Closed testing (14 days)** | ≥ 12 testers, fix bugs, improve onboarding funnel |
| 18 | **Launch** | Production staged rollout, launch content, monitor vitals |

**Milestones**

- **M1 (end wk 1):** widget spike proven — go/no-go on Dart background handler vs native Kotlin plan B
- **M2 (end wk 4):** two real phones can pair
- **M3 (end wk 7):** core loop usable daily by the team (dogfooding starts)
- **M4 (end wk 13):** feature complete
- **M5 (end wk 15):** release candidate in closed testing
- **M6 (wk 18):** live on Google Play

## 18. Costs (approximate, at launch scale)

Running costs are about the same. Expo EAS is replaced by Codemagic or GitHub Actions, and Shorebird is optional.

| Item | Cost |
| --- | --- |
| Google Play developer account | $25 one-time |
| Domain (invite links, website) | \~$10–20 / year |
| Firebase (Blaze plan — required for Functions) | \~$0–50 / month for the first few thousand users; photo storage/egress is the main driver |
| CI builds (Codemagic or GitHub Actions) | Free tier usually enough at first; paid plans if builds get frequent |
| Shorebird code push (optional) | Free tier, then paid by number of patch installs |
| RevenueCat | Free until a monthly revenue threshold, then a % of revenue |
| AdMob | Free (earns revenue) |
| Figma | Free / \~$15 per editor per month |
| Google Play fees | 15% of subscription revenue (and 15% on the first $1M/year for in-app products) |

Check current prices for Codemagic, Shorebird and RevenueCat before budgeting; they change.

## 19. Risks and mitigations

The top risk is still the widget. Flutter adds two new risks: the Kotlin skill gap and the background isolate start time.

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Widget doesn't update when app is closed on some phones (OEM battery killers) | Core promise broken | Week-1 spike; high-priority data FCM; notification fallback; refresh on open; OEM help page |
| Dart background isolate is slow to start or gets killed | Slow or missed widget updates | Measure in the spike; keep the handler tiny; plan B = native Kotlin worker that downloads and updates without Flutter |
| Team lacks Kotlin / Glance experience | Widget work takes longer | Keep widgets simple; budget extra days in weeks 1 and 5–7; use `home_widget` Glance examples as a base |
| Plugin versions break after Flutter upgrades | Build failures, delays | Pin versions, upgrade Flutter on a schedule (not mid-sprint), run CI on every upgrade |
| Only one person installs (pairing drop-off) | No value for user | Invite is the first action; reminder push to inviter; web invite page; widget preview while waiting |
| Play policy rejection (permissions, data safety, deletion, 18+) | Launch delay | Follow section 16 early; check merged manifest for extra permissions from plugins; postpone location to v1.1 |
| Closed-testing requirement for personal accounts | +2 weeks | Recruit 15–20 testers in week 10, or use an organisation account |
| Firebase costs from photos | Margin | Compress on device, server thumbnails, Storage lifecycle rules, free history limit |
| Timezone bugs in streaks/questions | Lost streaks, angry users | Single pair timezone, heavy unit tests, automatic freezes, plant never dies |
| Copying a competitor too closely | Weak positioning | Own brand, own plant/scrapbook identity, original art |
| Sensitive content between partners | Trust | Private by default, explicit share actions only, easy unpair/delete |

## 20. Post-launch roadmap

Flutter makes the iOS step in v2.0 smaller: the app code is reused, and only the widget needs native Swift.

- **v1.1 (launch + 4–6 weeks):** distance sharing, custom taps, gift ideas, seasonal sticker packs, more game packs, DE/FR/ES.
- **v1.2:** price experiments, onboarding A/B tests, memories export as video/PDF, anniversary "year in review".
- **v2.0:** **iOS** — same Flutter app + a native Swift **WidgetKit** extension reading data shared through an App Group (`home_widget` supports this), Apple sign-in, optional end-to-end encryption for notes.
- **Marketing calendar:** Valentine's Day (Feb 14), International Day of Friendship (Jul 30), National Best Friends Day (US, Jun 8), Christmas packs. TikTok/Reels: "what my boyfriend sent to my home screen", question reveals, quiz results.

### Immediate next steps

1. Confirm final app name and package name (reuse the React Native one if already on Play).
2. Create the Flutter project and connect the existing (or new, EU-region) Firebase project with `flutterfire configure`.
3. Start the **widget spike** (section 5.6) and the Figma design system in parallel.
4. Recruit 15–20 closed-test testers early.

## Appendix: moving from React Native to Flutter

About half of the project can be reused as is; the mobile app itself is a full rewrite.

| Part | Reuse or rewrite | Notes |
| --- | --- | --- |
| Cloud Functions, Firestore/Storage rules, indexes | **Reuse** | No changes needed |
| Firebase project, Auth, Remote Config, RevenueCat setup, AdMob units | **Reuse** | Register the Flutter app with the same package name and SHA-1/SHA-256 keys |
| Website (privacy, terms, deletion, `assetlinks.json`) | **Reuse** | Update `assetlinks.json` only if the signing key changes |
| Figma designs, illustrations, Lottie files, stickers, fonts | **Reuse** | Move into `assets/` and declare in `pubspec.yaml` |
| Translations (`en.json` …) | **Convert** | Turn JSON files into ARB files; placeholders change from `{{name}}` to `{name}` |
| TypeScript types / zod schemas | **Port** | Recreate as `freezed` models; keep JSON Schemas as the shared truth |
| App screens, navigation, state | **Rewrite** | Dart + Riverpod + `go_router` |
| Widgets (JSX) | **Rewrite** | Kotlin + Jetpack Glance |
| Maestro tests | **Mostly reuse** | Maestro works with Flutter apps; Patrol is optional |
| Play listing, package name, upload key | **Reuse** | Same package name + key = the Flutter build ships as an update to existing users |

**If the React Native app is already live:** keep the same Firebase data shape so old and new app versions can run side by side during the staged rollout. Do not change document fields until all users are on the Flutter version.
