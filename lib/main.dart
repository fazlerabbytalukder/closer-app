import 'dart:async';

import 'package:closer_app/app/app.dart';
import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/data/backend_factory.dart';
import 'package:closer_app/core/services/notifications.dart';
import 'package:closer_app/features/chat/chat_heads.dart';
import 'package:closer_app/features/onboarding/intro_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Backend selection:
///   flutter run                                         → on-device backend
///   flutter run --dart-define=CLOSER_BACKEND=firebase   → Firebase backend
///
/// `main(['bubble'])` is the chat head (Android bubble, see
/// ChatBubbleActivity): it shows only the chat.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final bubble = args.contains('bubble');
  if (bubble) {
    await _start(bubble: true);
    return;
  }
  // Paint the branded splash on the very first frame, then do the slow
  // startup work (backend, prefs, notifications) behind it.
  runApp(const _BootSplash());
  // Count the splash's minimum time from when it is actually on screen.
  WidgetsBinding.instance.addPostFrameCallback((_) => SplashGate.started = DateTime.now());
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await _start(bubble: false);
}

Future<void> _start({required bool bubble}) async {
  // Must be registered before runApp (plan 5.3) when Firebase is used.
  final backend = await createBackend();
  final prefs = await SharedPreferences.getInstance();
  if (!bubble) await NotificationService.instance.init();

  runApp(
    ProviderScope(
      overrides: [backendProvider.overrideWithValue(backend), prefsProvider.overrideWithValue(prefs)],
      child: bubble ? const BubbleChatApp() : const CloserApp(),
    ),
  );
}

/// The splash on its own, shown while [_start] runs. The real app then
/// opens on `/splash` too, so the hand-over is seamless.
class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(debugShowCheckedModeBanner: false, home: SplashScreen());
  }
}
