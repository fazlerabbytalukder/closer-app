import 'package:closer_app/core/data/closer_backend.dart';
import 'package:closer_app/core/data/firebase/fcm_background.dart';
import 'package:closer_app/core/data/firebase/firebase_backend.dart';
import 'package:closer_app/core/data/local/local_backend.dart';

/// `--dart-define=CLOSER_BACKEND=firebase` switches to Firebase.
const backendKind = String.fromEnvironment('CLOSER_BACKEND', defaultValue: 'local');

/// Creates and initialises the configured backend. For Firebase this also
/// registers the FCM background handler, which must happen before runApp
/// (plan 5.3).
///
/// Firebase setup still needed: `flutterfire configure`, then pass
/// `DefaultFirebaseOptions.currentPlatform` in FirebaseBackend.init().
Future<CloserBackend> createBackend() async {
  final CloserBackend backend;
  if (backendKind == 'firebase') {
    backend = FirebaseBackend();
    await backend.init();
    await initFirebaseMessaging();
  } else {
    backend = LocalBackend();
    await backend.init();
  }
  return backend;
}
