import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android conversation bubbles ("chat heads", Android 11+).
///
/// Works from any isolate, including the FCM background handler. Every
/// call is a safe no-op on iOS and older Android.
abstract final class ChatBubbles {
  static const _channel = MethodChannel('closer_bubbles');

  /// Android 11+.
  static Future<bool> isSupported() => _call<bool>('isSupported').then((v) => v ?? false);

  /// The user allows this conversation to bubble (system settings).
  static Future<bool> areAllowed() => _call<bool>('areAllowed').then((v) => v ?? false);

  /// The app's bubble settings page.
  static Future<void> openSettings() => _call<void>('openSettings');

  /// Posts or updates the partner's chat notification with a bubble.
  /// [message] null = no new message ("pop out" the chat). Returns false
  /// if nothing was posted (unsupported, duplicate [messageId], blocked).
  static Future<bool> show({
    required String name,
    String? avatarPath,
    String? message,
    String? messageId,
    bool expand = false,
    bool silent = false,
  }) => _call<bool>('show', {
    'name': name,
    'avatarPath': avatarPath,
    'message': message,
    'messageId': messageId,
    'expand': expand,
    'silent': silent,
  }).then((v) => v ?? false);

  /// Removes the bubble and the conversation shortcut (e.g. after unpairing).
  static Future<void> dismiss() => _call<void>('dismiss');

  static Future<T?> _call<T>(String method, [Object? args]) async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('ChatBubbles.$method: ${e.message}');
      return null;
    }
  }
}
