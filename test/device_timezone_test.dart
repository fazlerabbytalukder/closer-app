import 'package:closer_app/core/services/device_timezone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('timezoneFromOffset fallback', () {
    test('UTC', () => expect(timezoneFromOffset(Duration.zero), 'UTC'));
    test('east of UTC uses the inverted Etc sign', () {
      expect(timezoneFromOffset(const Duration(hours: 6)), 'Etc/GMT-6');
    });
    test('west of UTC uses the inverted Etc sign', () {
      expect(timezoneFromOffset(const Duration(hours: -5)), 'Etc/GMT+5');
    });
    test('half-hour offsets fall back to UTC', () {
      expect(timezoneFromOffset(const Duration(hours: 5, minutes: 30)), 'UTC');
    });
  });
}
