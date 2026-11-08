import 'dart:io';

import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/widget_contract.dart';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Snapshot of everything the home-screen widgets show.
@immutable
class WidgetSnapshot {
  const WidgetSnapshot({
    required this.paired,
    this.partnerName = '',
    this.mode = PairMode.couple,
    this.latestImage,
    this.latestItemId,
    this.latestType,
    this.latestCaption = '',
    this.latestSentAt,
    this.heartUntil,
    this.partnerMood = '',
    this.themeId = WidgetThemes.classic,
    this.countdown,
    this.streak = 0,
    this.plantStage = 0,
    this.plantHealth = PlantHealth.healthy,
  });

  final bool paired;
  final String partnerName;
  final PairMode mode;

  /// Local path or URL of the partner's latest thumbnail.
  final String? latestImage;
  final String? latestItemId;
  final ItemType? latestType;
  final String latestCaption;
  final DateTime? latestSentAt;
  final DateTime? heartUntil;
  final String partnerMood;
  final String themeId;
  final Countdown? countdown;
  final int streak;
  final int plantStage;
  final PlantHealth plantHealth;
}

/// Writes widget state for the native Kotlin Glance widgets through
/// `home_widget` and asks them to redraw (plan section 5).
abstract final class WidgetBridge {
  static String? _lastFingerprint;

  static Future<Directory> _widgetDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/widget');
    await dir.create(recursive: true);
    return dir;
  }

  /// Copies (or downloads) the latest thumbnail to a widget-owned file so the
  /// widget keeps working even if the original is deleted.
  static Future<String> _stageImage(String source, String itemId) async {
    final dir = await _widgetDir();
    final target = File('${dir.path}/latest_$itemId.jpg');
    if (!target.existsSync()) {
      if (source.startsWith('http')) {
        final res = await http.get(Uri.parse(source));
        if (res.statusCode != 200) throw HttpException('thumb ${res.statusCode}');
        await target.writeAsBytes(res.bodyBytes);
      } else {
        await File(source).copy(target.path);
      }
      // Remove older thumbnails.
      for (final f in dir.listSync().whereType<File>()) {
        if (f.path != target.path && f.path.contains('latest_')) {
          try {
            f.deleteSync();
          } on Object {
            // ignore
          }
        }
      }
    }
    return target.path;
  }

  static Future<void> sync(WidgetSnapshot s) async {
    if (!Platform.isAndroid) return;
    final fingerprint = [
      s.paired, s.partnerName, s.mode, s.latestItemId, s.latestCaption,
      s.heartUntil?.millisecondsSinceEpoch, s.partnerMood, s.themeId,
      s.countdown?.id, s.countdown?.title, s.countdown?.date, s.countdown?.emoji,
      s.streak, s.plantStage, s.plantHealth,
    ].join('|');
    if (fingerprint == _lastFingerprint) return;
    _lastFingerprint = fingerprint;

    try {
      var latestPath = '';
      if (s.latestImage != null && s.latestItemId != null) {
        try {
          latestPath = await _stageImage(s.latestImage!, s.latestItemId!);
        } on Object catch (e) {
          debugPrint('Widget image staging failed: $e');
        }
      }
      final cd = s.countdown;
      final cdDate = cd == null ? null : cd.nextOccurrence(DateTime.now());
      final data = <String, Object>{
        WidgetKeys.partnerName: s.partnerName,
        WidgetKeys.mode: s.mode.name,
        WidgetKeys.latestPath: latestPath,
        WidgetKeys.latestType: s.latestType?.name ?? '',
        WidgetKeys.latestCaption: s.latestCaption,
        WidgetKeys.latestSentAt: s.latestSentAt?.millisecondsSinceEpoch.toString() ?? '',
        WidgetKeys.heartUntil: s.heartUntil?.millisecondsSinceEpoch.toString() ?? '',
        WidgetKeys.partnerMood: s.partnerMood,
        WidgetKeys.themeId: s.themeId,
        WidgetKeys.countdownTitle: cd?.title ?? '',
        WidgetKeys.countdownEmoji: cd?.emoji ?? '',
        WidgetKeys.countdownDate: cdDate == null
            ? ''
            : '${cdDate.year.toString().padLeft(4, '0')}-${cdDate.month.toString().padLeft(2, '0')}-${cdDate.day.toString().padLeft(2, '0')}',
        WidgetKeys.streakCount: s.streak.toString(),
        WidgetKeys.plantStage: s.plantStage.toString(),
        WidgetKeys.plantHealth: s.plantHealth.name,
      };
      await HomeWidget.saveWidgetData<bool>(WidgetKeys.paired, s.paired);
      for (final e in data.entries) {
        await HomeWidget.saveWidgetData<String>(e.key, e.value as String);
      }
      await updateAll();
    } on Object catch (e) {
      _lastFingerprint = null;
      debugPrint('Widget sync failed: $e');
    }
  }

  static Future<void> updateAll() async {
    for (final r in WidgetReceivers.all) {
      try {
        await HomeWidget.updateWidget(qualifiedAndroidName: r);
      } on Object catch (e) {
        debugPrint('updateWidget($r) failed: $e');
      }
    }
  }

  /// Clears widget data on sign-out / unpair (plan section 12).
  static Future<void> clear() async {
    if (!Platform.isAndroid) return;
    _lastFingerprint = null;
    await sync(const WidgetSnapshot(paired: false));
    try {
      final dir = await _widgetDir();
      if (dir.existsSync()) await dir.delete(recursive: true);
    } on Object {
      // ignore
    }
  }

  static Future<bool> canPin() async {
    if (!Platform.isAndroid) return false;
    try {
      return await HomeWidget.isRequestPinWidgetSupported() ?? false;
    } on Object {
      return false;
    }
  }

  static Future<void> requestPin(String receiver) =>
      HomeWidget.requestPinWidget(qualifiedAndroidName: receiver);

  static Future<int> installedCount() async {
    if (!Platform.isAndroid) return 0;
    try {
      return (await HomeWidget.getInstalledWidgets()).length;
    } on Object {
      return 0;
    }
  }

  static Future<Uri?> initialLaunchUri() async {
    try {
      return await HomeWidget.initiallyLaunchedFromHomeWidget();
    } on Object {
      return null;
    }
  }

  static Stream<Uri?> get clicks => HomeWidget.widgetClicked;
}
