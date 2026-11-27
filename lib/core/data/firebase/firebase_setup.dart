// Firebase start-up shared by the app and the FCM background isolate,
// including the local Emulator Suite mode.
//
// Emulator mode (no billing needed; nothing leaves your PC):
//   firebase emulators:start --project duosy-f5bc2
//   flutter run --dart-define=CLOSER_BACKEND=firebase \
//               --dart-define=CLOSER_EMULATOR_HOST=<your PC's LAN IP>
//
// Use 10.0.2.2 as the host for the Android emulator, or your PC's Wi-Fi IP
// (ipconfig → IPv4 Address) for a real phone on the same network.

import 'package:closer_app/firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Host running `firebase emulators:start`. Empty means the real Firebase.
const emulatorHost = String.fromEnvironment('CLOSER_EMULATOR_HOST');

/// True when the app talks to the local Emulator Suite.
const useFirebaseEmulator = emulatorHost != '';

/// Cloud Functions region; must match functions/src/common.ts REGION.
const firebaseRegion = 'europe-west1';

/// Emulator mode keeps the real project's options: Android already starts
/// that app from google-services.json, so different options would clash.
/// Every service is then pointed at the local emulators, so nothing reaches
/// the real project. Start the emulators with `--project duosy-f5bc2`.

// Ports must match "emulators" in firebase.json.
const _authPort = 9099;
const _firestorePort = 8080;
const _functionsPort = 5001;
const _storagePort = 9199;

/// Functions write thumbnail URLs for the real Storage host; in emulator mode
/// point them at the Storage emulator, which serves the same paths.
String emulatorStorageUrl(String url) {
  const real = 'https://firebasestorage.googleapis.com/';
  if (!useFirebaseEmulator || !url.startsWith(real)) return url;
  return 'http://$emulatorHost:$_storagePort/${url.substring(real.length)}';
}

bool _emulatorsConnected = false;

/// Initialises Firebase once per isolate and, in emulator mode, points every
/// service at [emulatorHost]. Safe to call more than once.
Future<void> initCloserFirebase() async {
  if (Firebase.apps.isEmpty) {
    // lib/firebase_options.dart from `flutterfire configure`.
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
  if (!useFirebaseEmulator || _emulatorsConnected) return;
  _emulatorsConnected = true;
  await FirebaseAuth.instance.useAuthEmulator(emulatorHost, _authPort);
  FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, _firestorePort);
  FirebaseFunctions.instanceFor(region: firebaseRegion).useFunctionsEmulator(emulatorHost, _functionsPort);
  await FirebaseStorage.instance.useStorageEmulator(emulatorHost, _storagePort);
}
