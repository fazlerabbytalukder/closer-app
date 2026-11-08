import 'dart:async';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Android notification channels (plan section 13). The server sends to the
/// same channel ids.
abstract final class Channels {
  static const partnerItems = AndroidNotificationChannel(
    'partner_items',
    'Photos, notes & doodles',
    description: 'When your person sends something to your widget',
  );
  static final taps = AndroidNotificationChannel(
    'taps',
    'Thinking of you',
    description: 'Soft buzz when your person taps the heart',
    playSound: false,
    vibrationPattern: Int64List.fromList([0, 80, 120, 80]),
  );
  static const dailyQuestion = AndroidNotificationChannel(
    'daily_question',
    'Daily question',
    description: 'New question and answer reveals',
  );
  static const streak = AndroidNotificationChannel(
    'streak',
    'Streak & plant',
    description: 'Reminders to water your plant',
  );
  static const countdowns = AndroidNotificationChannel(
    'countdowns',
    'Countdowns',
    description: 'Reminders before important dates',
  );
  static const gameTurns = AndroidNotificationChannel(
    'game_turns',
    'Game turns',
    description: "When it's your turn in a game",
  );
  static const account = AndroidNotificationChannel(
    'account',
    'Account',
    description: 'Pairing, unpairing and subscription',
  );

  static List<AndroidNotificationChannel> get all =>
      [partnerItems, taps, dailyQuestion, streak, countdowns, gameTurns, account];
}

/// Thin wrapper around flutter_local_notifications. Notification taps carry a
/// route (payload) that is forwarded to go_router via [taps].
class NotificationService {
  NotificationService._();

  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<String>.broadcast();
  bool _ready = false;
  String? _launchRoute;

  /// Routes from tapped notifications while the app is running.
  Stream<String> get taps => _taps.stream;

  /// Route of the notification that cold-started the app, read once.
  String? takeLaunchRoute() {
    final r = _launchRoute;
    _launchRoute = null;
    return r;
  }

  Future<void> init() async {
    if (_ready || !Platform.isAndroid) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_closer'),
        ),
        onDidReceiveNotificationResponse: (r) {
          final p = r.payload;
          if (p != null && p.isNotEmpty) _taps.add(p);
        },
      );
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      for (final c in Channels.all) {
        await android?.createNotificationChannel(c);
      }
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _launchRoute = launch?.notificationResponse?.payload;
      }
      _ready = true;
    } on Object catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  /// Android 13+ POST_NOTIFICATIONS runtime permission.
  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  Future<bool> areEnabled() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? false;
  }

  Future<void> show({
    required AndroidNotificationChannel channel,
    required String title,
    required String body,
    String? route,
    String? imagePath,
    int? id,
  }) async {
    if (!_ready) return;
    final style = imagePath != null && File(imagePath).existsSync()
        ? BigPictureStyleInformation(
            FilePathAndroidBitmap(imagePath),
            largeIcon: FilePathAndroidBitmap(imagePath),
            hideExpandedLargeIcon: true,
          )
        : null;
    try {
      await _plugin.show(
        id: id ?? DateTime.now().millisecondsSinceEpoch.remainder(1 << 30),
        title: title,
        body: body,
        payload: route,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: channel.importance,
            playSound: channel.playSound,
            enableVibration: channel.enableVibration,
            vibrationPattern: channel.vibrationPattern,
            styleInformation: style,
            color: const Color(0xFFFF6B8A),
          ),
        ),
      );
    } on Object catch (e) {
      debugPrint('Notification failed: $e');
    }
  }
}

