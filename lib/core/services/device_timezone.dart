import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

/// The phone's IANA timezone ("Europe/Berlin", "America/New_York",
/// "Asia/Kolkata"), which the server uses for local days: streaks, the daily
/// question, reminders and quiet hours. Unlike a UTC offset it follows
/// daylight saving and half-hour zones.
Future<String> deviceTimezone() async {
  try {
    final id = (await FlutterTimezone.getLocalTimezone()).identifier;
    if (id.isNotEmpty && id.length <= 64) return id;
  } on Object catch (e) {
    debugPrint('deviceTimezone: $e');
  }
  return timezoneFromOffset(DateTime.now().timeZoneOffset);
}

/// Fallback when the platform can't say: a fixed-offset zone, or UTC when
/// the offset isn't whole hours (no Etc/ zone exists for those).
@visibleForTesting
String timezoneFromOffset(Duration offset) {
  if (offset.inMinutes % 60 != 0) return 'UTC';
  final h = offset.inHours;
  if (h == 0) return 'UTC';
  // Etc/ zones have inverted signs: UTC+6 is Etc/GMT-6.
  return h > 0 ? 'Etc/GMT-$h' : 'Etc/GMT+${-h}';
}
