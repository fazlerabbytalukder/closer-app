import 'dart:io';

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/features/chat/chat_screen.dart';
import 'package:closer_bubbles/closer_bubbles.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Messenger-style chat heads: the partner's chat notification carries an
/// Android bubble (Android 11+), and tapping the bubble opens the chat in a
/// small window over any app ([BubbleChatApp]).
abstract final class ChatHeads {
  /// User setting (Settings → Notifications), on by default.
  static const prefKey = 'chat_heads';

  static bool enabled(SharedPreferences prefs) => prefs.getBool(prefKey) ?? true;

  /// Shows the partner's message as a chat head. Returns false when chat
  /// heads don't apply (off, iOS, Android 10 and older), so the caller
  /// shows a plain notification instead.
  static Future<bool> notify(
    SharedPreferences prefs, {
    required String name,
    String? photo,
    String? message,
    String? messageId,
    bool expand = false,
  }) async {
    if (kIsWeb || !Platform.isAndroid || !enabled(prefs)) return false;
    if (!await ChatBubbles.isSupported()) return false;
    await ChatBubbles.show(
      name: name,
      avatarPath: await _avatarFile(photo),
      message: message,
      messageId: messageId,
      expand: expand,
    );
    return true;
  }

  /// A local copy of the partner's photo for the bubble icon.
  static Future<String?> _avatarFile(String? photo) async {
    if (photo == null || photo.isEmpty) return null;
    if (!photo.startsWith('http')) return File(photo).existsSync() ? photo : null;
    try {
      final file = File('${(await getTemporaryDirectory()).path}/bubble_avatar_${photo.hashCode.toUnsigned(32)}.jpg');
      if (file.existsSync()) return file.path;
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      try {
        final res = await (await client.getUrl(Uri.parse(photo))).close().timeout(const Duration(seconds: 15));
        if (res.statusCode != HttpStatus.ok) return null;
        await res.pipe(file.openWrite());
        return file.path;
      } finally {
        client.close();
      }
    } on Object catch (e) {
      debugPrint('Chat head avatar: $e');
      return null;
    }
  }
}

/// The app that runs inside the chat head (`main(['bubble'])`): just the
/// chat, no tabs or onboarding.
class BubbleChatApp extends ConsumerWidget {
  const BubbleChatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(pairModeProvider);
    final me = ref.watch(meProvider);
    final paired = me.value?.pairId != null;
    return MaterialApp(
      title: 'Duosy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(Brightness.light, mode),
      darkTheme: AppTheme.build(Brightness.dark, mode),
      themeMode: ref.watch(themeModeProvider),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('de'), Locale('fr'), Locale('es')],
      home: paired
          ? const ChatScreen(inBubble: true)
          : me.isLoading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : const Scaffold(
              body: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Open Duosy to connect with your person first 💞', textAlign: TextAlign.center),
                ),
              ),
            ),
    );
  }
}
