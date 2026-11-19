import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Chat privacy, backed by `MainActivity.kt` / `AppDelegate.swift`:
///
/// * [screenshots] fires when the user takes a screenshot of the app
///   (Android 14+ and iOS; older Android can't tell).
/// * [secure] blocks screenshots and screen recording (Android only — iOS
///   doesn't allow it, so there we rely on the screenshot notice).
abstract final class ScreenGuard {
  static const _channel = MethodChannel('app.closer/screen_guard');
  static final _shots = StreamController<void>.broadcast();
  static var _listening = false;
  static var _secureCount = 0;

  static Stream<void> get screenshots {
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'screenshot') _shots.add(null);
      });
    }
    return _shots.stream;
  }

  /// Blocks screenshots until the matching [release]. Nested calls are
  /// counted so two protected screens don't unlock each other.
  static Future<void> secure() async {
    _secureCount++;
    if (_secureCount == 1) await _set(on: true);
  }

  static Future<void> release() async {
    if (_secureCount == 0) return;
    _secureCount--;
    if (_secureCount == 0) await _set(on: false);
  }

  static Future<void> _set({required bool on}) async {
    try {
      await _channel.invokeMethod<bool>('setSecure', on);
    } on Object catch (e) {
      // Tests and platforms without the channel.
      debugPrint('ScreenGuard.setSecure: $e');
    }
  }
}
