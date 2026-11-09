// FCM handling for Closer: the background isolate entry point that updates
// the home-screen widget when the partner sends something (plan section 5.3),
// plus a foreground listener doing the same while the app is open.
//
// Server messages (functions/src/common.ts):
// * type=item   data-only, high priority:
//     {type, pairId, itemId, itemType, thumbUrl, caption, senderName, sentAt, silent}
// * type=tap    data-only, high priority:
//     {type, pairId, tapId, kind, senderName, sentAt, silent}
// * type=unpaired  data-only: clear the widgets.
// * everything else (question, game_turn, countdown, streak_reminder, ...) is
//   a regular notification message with an Android channel id, which Android
//   shows by itself while the app is in the background.
//
// `silent == "1"` means quiet hours or the user's notification preference:
// still update the widget, but don't show a notification.

import 'dart:async';
import 'dart:io';

import 'package:closer_app/core/services/widget_contract.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';

/// Android notification channels (plan section 13). The server sends to
/// these ids; the app should create them on first launch with the same ids.
abstract final class CloserChannels {
  static const partnerItems = 'partner_items';
  static const taps = 'taps';
  static const dailyQuestion = 'daily_question';
  static const streak = 'streak';
  static const countdowns = 'countdowns';
  static const gameTurns = 'game_turns';
  static const account = 'account';

  static const names = <String, String>{
    partnerItems: 'Photos, notes & doodles',
    taps: 'Thinking-of-you taps',
    dailyQuestion: 'Daily question',
    streak: 'Streak & plant',
    countdowns: 'Countdowns',
    gameTurns: 'Games',
    account: 'Account & pairing',
  };
}

/// Notification icon (same drawable the app's NotificationService uses).
const _notificationIcon = 'ic_stat_closer';

/// Payload used for local notifications created here; the app routes it.
const _replyPayload = 'closer://reply';

StreamSubscription<RemoteMessage>? _foregroundSub;

/// Registers the FCM handlers. Call from `main()` before `runApp()`:
///
/// ```dart
/// WidgetsFlutterBinding.ensureInitialized();
/// await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
/// await initFirebaseMessaging();
/// runApp(...);
/// ```
///
/// This does NOT initialise Firebase itself.
// TODO(setup): run `flutterfire configure` to generate lib/firebase_options.dart
// and pass `DefaultFirebaseOptions.currentPlatform` to Firebase.initializeApp
// in main() and in [closerFirebaseBackgroundHandler] below.
Future<void> initFirebaseMessaging() async {
  FirebaseMessaging.onBackgroundMessage(closerFirebaseBackgroundHandler);
  // In the foreground the background handler doesn't run, so keep the widget
  // in sync here too (no system notification: the open app shows it).
  _foregroundSub ??= FirebaseMessaging.onMessage.listen(
    (m) => handleCloserMessage(m, foreground: true),
  );
}

/// Background isolate entry point. Must stay a top-level function.
@pragma('vm:entry-point')
Future<void> closerFirebaseBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      // TODO(setup): use `Firebase.initializeApp(options:
      // DefaultFirebaseOptions.currentPlatform)` once firebase_options.dart
      // exists. Without options this relies on google-services.json.
      await Firebase.initializeApp();
    }
  } on Object catch (e) {
    debugPrint('Closer FCM: Firebase init failed: $e');
  }
  await handleCloserMessage(message);
}

/// Handles one Closer message. Never throws.
Future<void> handleCloserMessage(
  RemoteMessage message, {
  bool foreground = false,
}) async {
  try {
    final data = message.data;
    final notify = !foreground && data['silent'] != '1';
    switch (data['type']) {
      case 'item':
        await _handleItem(data, notify: notify);
      case 'tap':
        await _handleTap(data, notify: notify);
      case 'unpaired':
        await _handleUnpaired();
      default:
        // Notification messages are shown by Android in the background.
        break;
    }
  } on Object catch (e, st) {
    debugPrint('Closer FCM: failed to handle message: $e\n$st');
  }
}

Future<void> _handleItem(
  Map<String, dynamic> data, {
  required bool notify,
}) async {
  final itemId = '${data['itemId'] ?? ''}';
  final thumbUrl = '${data['thumbUrl'] ?? ''}';
  if (itemId.isEmpty || thumbUrl.isEmpty) return;
  final sentAt = '${data['sentAt'] ?? DateTime.now().millisecondsSinceEpoch}';
  final senderName = '${data['senderName'] ?? ''}';
  final caption = '${data['caption'] ?? ''}';
  final itemType = '${data['itemType'] ?? 'photo'}';

  // Ignore out-of-order deliveries of older items.
  final previousSentAt = int.tryParse(
    await _read(WidgetKeys.latestSentAt) ?? '',
  );
  final thisSentAt = int.tryParse(sentAt) ?? 0;
  final isNewest = previousSentAt == null || thisSentAt >= previousSentAt;

  final dir = Directory('${(await getApplicationSupportDirectory()).path}/widget');
  await dir.create(recursive: true);
  final file = File('${dir.path}/latest_$itemId.jpg');
  if (!file.existsSync()) {
    await _download(thumbUrl, file);
  }

  if (isNewest) {
    final previousPath = await _read(WidgetKeys.latestPath);
    await HomeWidget.saveWidgetData<String>(WidgetKeys.latestPath, file.path);
    await HomeWidget.saveWidgetData<String>(WidgetKeys.latestType, itemType);
    await HomeWidget.saveWidgetData<String>(WidgetKeys.latestCaption, caption);
    await HomeWidget.saveWidgetData<String>(WidgetKeys.latestSentAt, sentAt);
    if (senderName.isNotEmpty) {
      await HomeWidget.saveWidgetData<String>(
        WidgetKeys.partnerName,
        senderName,
      );
    }
    await HomeWidget.saveWidgetData<bool>(WidgetKeys.paired, true);
    await HomeWidget.updateWidget(
      qualifiedAndroidName: WidgetReceivers.partnerPhoto,
    );
    if (previousPath != null &&
        previousPath.isNotEmpty &&
        previousPath != file.path) {
      try {
        final old = File(previousPath);
        if (old.existsSync()) await old.delete();
      } on Object catch (_) {}
    }
  }

  if (notify) {
    final what = switch (itemType) {
      'note' => 'a note',
      'doodle' => 'a doodle',
      'location' => 'where they are',
      _ => 'a photo',
    };
    final name = senderName.isEmpty ? 'Your person' : senderName;
    await _show(
      id: itemId.hashCode,
      channelId: CloserChannels.partnerItems,
      title: '$name sent you $what',
      body: caption.isNotEmpty ? caption : "It's on your home screen 💞",
      bigPicturePath: file.existsSync() ? file.path : null,
      // Soft: default importance, no vibration.
      vibrate: false,
    );
  }
}

Future<void> _handleTap(
  Map<String, dynamic> data, {
  required bool notify,
}) async {
  final until = DateTime.now().add(const Duration(hours: 1));
  await HomeWidget.saveWidgetData<String>(
    WidgetKeys.heartUntil,
    '${until.millisecondsSinceEpoch}',
  );
  final senderName = '${data['senderName'] ?? ''}';
  if (senderName.isNotEmpty) {
    await HomeWidget.saveWidgetData<String>(WidgetKeys.partnerName, senderName);
  }
  await HomeWidget.updateWidget(
    qualifiedAndroidName: WidgetReceivers.partnerPhoto,
  );
  if (notify) {
    final name = senderName.isEmpty ? 'Your person' : senderName;
    await _show(
      id: 'tap'.hashCode, // one tap notification at a time
      channelId: CloserChannels.taps,
      title: '$name is thinking of you 💗',
      body: 'Tap back to let them know.',
      importance: Importance.high,
      vibrationPattern: Int64List.fromList([0, 80, 120, 80]),
      playSound: false,
    );
  }
}

Future<void> _handleUnpaired() async {
  final previousPath = await _read(WidgetKeys.latestPath);
  await HomeWidget.saveWidgetData<bool>(WidgetKeys.paired, false);
  for (final key in [
    WidgetKeys.latestPath,
    WidgetKeys.latestType,
    WidgetKeys.latestCaption,
    WidgetKeys.latestSentAt,
    WidgetKeys.heartUntil,
    WidgetKeys.partnerName,
    WidgetKeys.partnerMood,
  ]) {
    await HomeWidget.saveWidgetData<String>(key, '');
  }
  for (final receiver in WidgetReceivers.all) {
    await HomeWidget.updateWidget(qualifiedAndroidName: receiver);
  }
  if (previousPath != null && previousPath.isNotEmpty) {
    try {
      final old = File(previousPath);
      if (old.existsSync()) await old.delete();
    } on Object catch (_) {}
  }
}

Future<String?> _read(String key) async {
  try {
    final v = await HomeWidget.getWidgetData<Object>(key);
    return v?.toString();
  } on Object catch (_) {
    return null;
  }
}

Future<void> _download(String url, File target) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    final tmp = File('${target.path}.part');
    final sink = tmp.openWrite();
    await response.pipe(sink);
    await tmp.rename(target.path);
  } finally {
    client.close();
  }
}

final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
bool _pluginReady = false;

Future<void> _show({
  required int id,
  required String channelId,
  required String title,
  required String body,
  String? bigPicturePath,
  Importance importance = Importance.defaultImportance,
  bool vibrate = true,
  Int64List? vibrationPattern,
  bool playSound = true,
}) async {
  try {
    if (!_pluginReady) {
      // Background isolate only: the main isolate initialises the plugin
      // itself (with its tap callback), so we never re-initialise there.
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(_notificationIcon),
        ),
      );
      _pluginReady = true;
    }
    final details = AndroidNotificationDetails(
      channelId,
      CloserChannels.names[channelId] ?? channelId,
      icon: _notificationIcon,
      importance: importance,
      priority: importance == Importance.high
          ? Priority.high
          : Priority.defaultPriority,
      enableVibration: vibrate,
      vibrationPattern: vibrationPattern,
      playSound: playSound,
      category: AndroidNotificationCategory.social,
      styleInformation: bigPicturePath == null
          ? null
          : BigPictureStyleInformation(
              FilePathAndroidBitmap(bigPicturePath),
              hideExpandedLargeIcon: true,
            ),
    );
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: details),
      payload: _replyPayload,
    );
  } on Object catch (e) {
    debugPrint('Closer FCM: local notification failed: $e');
  }
}
