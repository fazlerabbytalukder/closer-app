# Duosy — প্রজেক্টের গ্যাপ নোট

_চেক করা হয়েছে: ২৭ নভেম্বর ২০২৬ · ব্রাঞ্চ `main` @ 9f43d5b_

## সংক্ষেপে

অ্যাপের **UI আর ফিচারের কোড প্রায় সব লেখা আছে**। **ব্যাকএন্ডের কোডও লেখা আছে**
(Dart-এ Firebase backend, ৩০টার বেশি Cloud Functions, Firestore/Storage rules)।
কিন্তু **ব্যাকএন্ড এখনো কানেক্ট বা ডিপ্লয় করা হয়নি**।

তাই অ্যাপ এখন শুধু **ডেমো মোডে** চলে। ডেটা ফোনেই থাকে, আর পার্টনারটা ("Sam" / "Alex")
আসল না, অ্যাপ নিজেই বানিয়ে দেখায়।

মানে: **দুইটা আসল ফোন এখনো একে অপরের সাথে যোগাযোগ করতে পারবে না।**

---

## 🔴 ১. সবচেয়ে জরুরি: ব্যাকএন্ড কানেক্ট হয়নি

| # | সমস্যা | কোথায় | কী করতে হবে |
|---|-----|--------|---------------|
| ১ | ~~Firebase প্রজেক্ট ID নেই~~ ✅ | `.firebaserc` | প্রজেক্ট `duosy-f5bc2`। এখনো **Spark** প্ল্যানে। Storage আর Functions-এর জন্য Blaze লাগবে |
| ২ | ~~`lib/firebase_options.dart` নেই~~ ✅ | `lib/firebase_options.dart` | `flutterfire configure` দিয়ে বানানো |
| ৩ | ~~`android/app/google-services.json` নেই~~ ✅ | `android/app/google-services.json` | debug SHA যোগ করার পর আবার download করা |
| ৪ | ~~Google Services Gradle plugin নেই~~ ✅ | `android/settings.gradle.kts`, `android/app/build.gradle.kts` | `flutterfire configure` যোগ করেছে |
| ৫ | ~~`Firebase.initializeApp()` option ছাড়া~~ ✅ | `lib/core/data/firebase/firebase_setup.dart` | `DefaultFirebaseOptions.currentPlatform` পাস হয় (emulator মোডে demo options) |
| ৬ | ডিফল্ট ব্যাকএন্ড `local` (ডেমো) | `lib/core/data/backend_factory.dart` | `--dart-define=CLOSER_BACKEND=firebase` দিয়ে চালাতে হবে, অথবা রিলিজের জন্য ডিফল্ট বদলাতে হবে |
| ৭ | ~~Cloud Functions install বা compile করা হয়নি~~ ✅ | `functions/` | `npm install` আর `npm run build` হয়ে গেছে, কোনো type error আসেনি (২৭ নভেম্বর ২০২৬)। Emulator-এ সব function লোড হয় |
| ৮ | Functions-এ lint script নেই | `functions/package.json` | ঐচ্ছিক: eslint যোগ করা |
| ৯ | Functions, Storage rules আর hosting ডিপ্লয় হয়নি | `storage.rules`, `functions/`, `web/` | Firestore rules আর indexes ডিপ্লয় হয়ে গেছে ✅। `taps.expireAt`-এর TTL policy, Storage আর Functions-এর জন্য Blaze লাগবে। Blaze নেওয়ার পর: `firebase deploy --only firestore:indexes,storage,functions,hosting` |
| ১০ | Upload আর Play signing key-এর SHA যোগ করা নেই | Firebase console | Debug key-এর SHA-1 আর SHA-256 যোগ করা হয়েছে ✅। রিলিজ keystore বানানোর পর upload key আর Play signing key-এর SHA-ও যোগ করতে হবে |
| ১১ | RevenueCat webhook secret সেট করা নেই | `functions/src/premium.ts` | `firebase functions:secrets:set REVENUECAT_WEBHOOK_AUTH` (শুধু monetization চালু করলে) |

**ভালো খবর:** অ্যাপ যে ১৫টা callable function কল করে, তার সবগুলো
`functions/src/index.ts`-এ export করা আছে। অ্যাপ Firestore-এর যেসব path ব্যবহার করে
(`items`, `messages`, `capsules`, `todos`, `wishes`, `goodnights`, `moods`, `games` ইত্যাদি),
সবগুলোর rules `firestore.rules`-এ আছে। তাই ব্যাকএন্ডের কোডে কোনো অংশ বাদ পড়েনি,
শুধু **সেটআপ আর ডিপ্লয়** বাকি। তবে আসল ফোনে এখনো কিছুই টেস্ট হয়নি।

---

## 🟠 ২. Play Store-এ দেওয়ার আগে লাগবে

| # | সমস্যা | কোথায় |
|---|-----|--------|
| ১২ | রিলিজ build এখনো **debug key** দিয়ে sign হয় | `android/app/build.gradle.kts:38-40` (`TODO`)। upload keystore আর `android/key.properties` লাগবে |
| ১৩ | Privacy policy-তে placeholder | `web/privacy.html:15,18` → `REPLACE_WITH_DATE`, `REPLACE_WITH_LEGAL_ENTITY`, `REPLACE_WITH_ADDRESS` |
| ১৪ | Terms-এ placeholder | `web/terms.html:15` → `REPLACE_WITH_DATE` |
| ১৫ | App Links-এ শুধু debug key-এর SHA-256 আছে | `web/.well-known/assetlinks.json` | রিলিজ keystore আর Play App Signing-এর SHA-256-ও এই তালিকায় যোগ করতে হবে |
| ১৬ | ~~ইনভাইট ডোমেইন `closer.app`~~ ✅ | `functions/src/pairing.ts`, `AndroidManifest.xml`, `lib/core/models/models.dart`, `settings_screens.dart` | এখন `duosy-f5bc2.web.app`। Hosting আর Functions deploy হলে তবেই লিঙ্ক কাজ করবে। `privacy@`/`support@closer.app` ইমেইল এখনো বদলানো বাকি (#১৩) |
| ১৭ | ~~প্যাকেজ নাম `app.closer.widget`~~ ✅ | `android/app/build.gradle.kts` | এখন `com.duosy.app`, Firebase-এ এই নামেই রেজিস্টার করা |
| ১৮ | Play Console অ্যাকাউন্ট, store listing, Data safety form | কোডের বাইরের কাজ |

---

## 🟡 ৩. কোড আছে, কিন্তু **আসল কাজ হয় না** (নকল বা simulated)

| # | ফিচার | এখন কী হয় | কোথায় |
|---|---------|--------------|--------|
| ১৯ | **সাবস্ক্রিপশন (Duosy Plus)** | `purchases_flutter` প্যাকেজই নেই। Firebase মোডে "Start free trial" চাপলে `UnsupportedError('RevenueCat is not configured yet')` আসে | `lib/features/premium/paywall_screen.dart:53-54` |
| ২০ | **Restore purchases** | Firebase মোডে শুধু "Restoring purchases…" মেসেজ দেখায়, আর কিছু করে না | `lib/features/premium/paywall_screen.dart:158` |
| ২১ | **বিজ্ঞাপন (AdMob)** | `google_mobile_ads` নেই। Rewarded ad আসলে ৫ সেকেন্ডের একটা নকল ডায়ালগ। Banner-টা নিজের "house" বিজ্ঞাপন। UMP consent-ও নেই | `lib/core/services/ads.dart` |
| ২২ | **Rewarded ad-এর সার্ভার যাচাই** | ইউজার সত্যিই বিজ্ঞাপন দেখেছে কিনা সার্ভার যাচাই করে না, তাই যে কেউ বোনাস পেতে পারে (`TODO(prod)` SSV) | `functions/src/items.ts:379` |
| ২৩ | Monetization **বন্ধ** | দুইটা flag আর তিন জায়গায় বদলাতে হবে | `lib/core/config.dart` (`monetizationEnabled`), `functions/src/common.ts` (`MONETIZATION_ENABLED`), `firestore.rules` (`monetizationEnabled()`) |
| ২৪ | ~~**টাইমজোন** অনুমান করা হত~~ ✅ | এখন `flutter_timezone` দিয়ে ফোনের আসল IANA zone (যেমন `Europe/Berlin`) পাঠানো হয়, লগইনে আর FCM token রেজিস্ট্রেশনে আপডেট হয় | `lib/core/services/device_timezone.dart` |
| ২৫ | ~~**অফলাইনে পাঠানো**~~ ✅ | নেট না থাকলে ছবি/note/doodle/location ফোনে জমা থাকে, Home-এ "N waiting to send" দেখায়, নেট ফিরলে, অ্যাপ খুললে বা প্রতি মিনিটে নিজে থেকে পাঠায়। সার্ভার একই itemId-এ duplicate বানায় না। Chat-এর ছবি/ভয়েস আর heart tap এখনো queue-এ যায় না | `lib/core/data/firebase/send_queue.dart` |

---

## 🔵 ৪. সেটআপ করা আছে, কিন্তু কাজ করে না বা শুরুই হয়নি

| # | সমস্যা | বিস্তারিত |
|---|-----|---------|
| ২৬ | **অনুবাদ (de/fr/es)** | `supportedLocales`-এ English, German, French, Spanish আছে (`lib/app/app.dart:124`), কিন্তু সব লেখা সরাসরি ইংরেজিতে কোডে বসানো। ARB/l10n ফাইল নেই। **বাংলাও নেই** |
| ২৭ | **Crashlytics / Analytics / Remote Config / App Check** | কোনো প্যাকেজই যোগ করা হয়নি। প্ল্যান ডকের §১৪-তে এগুলোর কথা আছে |
| ২৮ | **লগইনের অপশন** | শুধু Google sign-in। Email, phone বা Apple sign-in নেই |
| ২৯ | **ভিডিও** | Chat আর snaps-এ শুধু ছবি, ভয়েস আর টেক্সট |
| ৩০ | ডেমো মোডে chat head আর মূল অ্যাপের ডেটা মেলে না | শুধু ডেমো মোডের সমস্যা, Firebase মোডে হবে না |

---

## ⚪ ৫. iOS (শুধু iPhone সাপোর্ট করলে)

| # | সমস্যা |
|---|-----|
| ৩১ | `ios/Runner/GoogleService-Info.plist` নেই |
| ৩২ | APNs key আপলোড করা নেই, তাই iPhone-এ নোটিফিকেশন আসবে না |
| ৩৩ | Google Sign-In-এর reversed client ID URL scheme `Info.plist`-এ নেই |
| ৩৪ | **Sign in with Apple** নেই। এটা ছাড়া App Store review অ্যাপ রিজেক্ট করবে |
| ৩৫ | **iOS home-screen widget (WidgetKit) একদমই নেই**। Android-এ ৪টা Glance widget আছে (Photo, Countdown, Plant, Always With Me) |
| ৩৬ | Chat heads শুধু Android-এ চলে, আর iOS-এ screenshot আটকানো যায় না (প্ল্যাটফর্মের সীমাবদ্ধতা) |

---

## 🛠 ৬. ডেভেলপমেন্ট পরিবেশ

| # | সমস্যা |
|---|-----|
| ৩৭ | লোকাল Flutter SDK পুরোনো (Dart 3.13.5), কিন্তু `pubspec.yaml` চায় `^3.13.7`। `flutter upgrade` আটকে আছে, কারণ Dart process (IDE-র analysis server) চলছে। IDE বন্ধ করে আবার upgrade করুন |
| ৩৮ | Upgrade না হওয়া পর্যন্ত এই চেকে `flutter test` / `flutter analyze` চালানো যায়নি। **টেস্ট পাস করে কিনা যাচাই হয়নি** |

---

## 💰 ৭. Firebase-এর ফ্রি লিমিট

| জিনিস | ফ্রি লিমিট |
|---|---|
| Google login (Authentication) | প্রতি মাসে ৫০,০০০ সক্রিয় ইউজার |
| ফোন নম্বর login (SMS OTP) | ফ্রি লিমিট খুব কম। প্রতিটা SMS-এর দাম দেশ অনুযায়ী, বাংলাদেশে তুলনামূলক দামি। **সঠিক সংখ্যা যাচাই করা হয়নি**, যোগ করার আগে অফিসিয়াল পেজ দেখুন |
| Firestore-এ ডেটা রাখা | মোট ১ GB |
| Firestore read | দিনে ৫০,০০০ |
| Firestore write | দিনে ২০,০০০ |
| ডেটা ডাউনলোড | মাসে ১০ GB |

- লিমিটগুলো পুরো প্রজেক্টের জন্য একসাথে, প্রতি ইউজারের আলাদা না।
- এই অ্যাপ Cloud Functions ব্যবহার করে, তাই **Blaze প্ল্যান লাগবেই**।
- একটা গাইড অনুযায়ী, ফেব্রুয়ারি ২০২৬ থেকে Cloud Storage-এর জন্যও Blaze লাগে (অফিসিয়ালি যাচাই করা হয়নি)।
- **Blaze-এও উপরের ফ্রি লিমিট থাকে**। লিমিট পার না হলে টাকা লাগে না। ছোট পরিসরে সাধারণত মাসে $০ থেকে $২।
- Blaze চালু করলে অবশ্যই **budget alert** সেট করুন।
- সূত্র: [Firebase Pricing](https://firebase.google.com/pricing/?hl=en), [Firebase pricing plans](https://firebase.google.com/docs/projects/billing/firebase-pricing-plans)

---

## ✅ কোন কাজ আগে করবেন

১. Flutter upgrade → `flutter pub get` → `flutter analyze` আর `flutter test`
২. প্যাকেজ নাম চূড়ান্ত করা (#১৭) আর ইনভাইট ডোমেইন ঠিক করা (#১৬)
৩. Firebase প্রজেক্ট বানানো → `flutterfire configure` → `TODO(setup)` গুলো ঠিক করা (#১–৬)
৪. Functions build করে error ঠিক করা → ডিপ্লয় (#৭, #৯)
৫. SHA key যোগ করা → দুইটা আসল ফোনে টেস্ট (`SETUP_CHECKLIST.md`-এর টেস্ট লিস্ট অনুযায়ী)
৬. রিলিজ keystore, privacy/terms, assetlinks (#১২–১৫)
৭. টাইমজোন ঠিক করা (#২৪), অফলাইন queue (#২৫), Crashlytics (#২৭)
৮. পরে: RevenueCat + AdMob + SSV (#১৯–২৩), অনুবাদ, iOS

> বিস্তারিত ধাপের জন্য `SETUP_CHECKLIST.md` আর `README.md`-র "Not wired yet" অংশ দেখুন।
