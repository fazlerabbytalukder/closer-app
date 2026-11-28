import 'package:closer_app/core/data/closer_backend.dart';
import 'package:closer_app/core/data/firebase/fcm_background.dart';
import 'package:closer_app/core/data/firebase/firebase_backend.dart';
import 'package:closer_app/core/data/local/local_backend.dart';

/// The real Firebase project is the default. `--dart-define=CLOSER_BACKEND=local`
/// runs the on-device demo instead; `--dart-define=CLOSER_EMULATOR_HOST=<host>`
/// points Firebase at the local Emulator Suite (see firebase_setup.dart).
const backendKind = String.fromEnvironment('CLOSER_BACKEND', defaultValue: 'firebase');

/// Creates and initialises the configured backend. For Firebase this also
/// registers the FCM background handler, which must happen before runApp
/// (plan 5.3).
Future<CloserBackend> createBackend() async {
  final CloserBackend backend;
  if (backendKind != 'local') {
    backend = FirebaseBackend();
    await backend.init();
    await initFirebaseMessaging();
  } else {
    backend = LocalBackend();
    await backend.init();
  }
  return backend;
}
