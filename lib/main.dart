import 'dart:async';

import 'package:closer_app/app/app.dart';
import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/data/backend_factory.dart';
import 'package:closer_app/core/services/notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Backend selection:
///   flutter run                                         → on-device backend
///   flutter run --dart-define=CLOSER_BACKEND=firebase   → Firebase backend
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Must be registered before runApp (plan 5.3) when Firebase is used.
  final backend = await createBackend();
  final prefs = await SharedPreferences.getInstance();
  await NotificationService.instance.init();

  runApp(
    ProviderScope(
      overrides: [
        backendProvider.overrideWithValue(backend),
        prefsProvider.overrideWithValue(prefs),
      ],
      child: const CloserApp(),
    ),
  );
}
