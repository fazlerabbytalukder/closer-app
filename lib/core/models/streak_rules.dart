import 'dart:math';

import 'package:closer_app/core/models/models.dart';

/// The streak + plant rules (plan F8), as pure functions.
///
/// This mirrors `settle` / `markActivity` in functions/src/streaks.ts, which
/// is the source of truth in production; the local backend runs this copy
/// and the unit tests pin the behaviour down.
///
/// 1. A day is a calendar day in the pair's timezone (yyyy-mm-dd keys).
/// 2. A day counts when BOTH members interact: send something, heart tap,
///    or answer the daily question. The streak grows by one, once per day.
/// 3. The plant grows a stage at 1, 3, 7, 14, 30, 60, 100, 365 days and
///    never shrinks.
/// 4. A missed day spends a freeze automatically: the streak is kept (not
///    increased). Freezes refill on the 1st: 1 a month, 3 with Plus.
/// 5. With no freeze left the streak resets to 0 and the plant wilts but
///    keeps its size. Both showing up again revives it (streak 1).
/// 6. After 365 days the plant is in full bloom; every further full year
///    of streak earns a bloom year (count ~/ 365).
abstract final class StreakRules {
  /// Settles every finished day up to yesterday: refills monthly freezes,
  /// resets the "today" list, spends freezes on missed days or breaks the
  /// streak.
  static SettleResult settle(Streak s, Plant plant, String today, {required bool plus}) {
    var streak = s;
    var p = plant;
    var broke = false;
    var frozeDays = 0;

    final month = today.substring(0, 7);
    if (streak.freezesMonth != month) {
      streak = streak.copyWith(freezesMonth: month, freezesLeft: Streak.monthlyFreezes(plus: plus));
    }
    if (streak.activeDate != today) {
      streak = streak.copyWith(activeDate: today, activeToday: const []);
    }

    final yesterday = addDays(today, -1);
    final checked = streak.checkedThrough;
    if (checked != null && checked.compareTo(yesterday) >= 0) {
      return SettleResult(streak, p, broke: false, frozeDays: 0);
    }

    final last = streak.lastBothActiveDate;
    if (streak.count > 0 && last != null) {
      var from = last;
      if (checked != null && checked.compareTo(from) > 0) from = checked;
      final missed = max(0, daysBetween(from, yesterday));
      var left = streak.freezesLeft;
      String? frozeOn;
      String? brokeOn;
      if (missed > 400) {
        brokeOn = yesterday;
      } else {
        for (var i = 0; i < missed; i++) {
          if (left > 0) {
            left--;
            frozeDays++;
            frozeOn = addDays(from, i + 1);
          } else {
            brokeOn = addDays(from, i + 1);
            break;
          }
        }
      }
      if (brokeOn != null) {
        broke = true;
        // count resets to 0; best, stage and history are kept.
        streak = Streak(
          best: streak.best,
          lastBothActiveDate: streak.lastBothActiveDate,
          freezesLeft: left,
          freezesMonth: streak.freezesMonth,
          activeToday: streak.activeToday,
          activeDate: streak.activeDate,
          checkedThrough: streak.checkedThrough,
          lastFrozeDate: frozeOn ?? streak.lastFrozeDate,
          lostCount: streak.count,
          brokeDate: brokeOn,
        );
        p = Plant(stage: p.stage, health: PlantHealth.wilted, species: p.species);
      } else {
        streak = streak.copyWith(freezesLeft: left, lastFrozeDate: frozeOn);
      }
    }
    streak = streak.copyWith(checkedThrough: yesterday);
    return SettleResult(streak, p, broke: broke, frozeDays: frozeDays);
  }

  /// Marks [uid] active on [today]. When every member is active the streak
  /// grows (once per day), the plant revives and may reach a new stage.
  static ActivityResult markActive(
    Streak s,
    Plant plant,
    String uid,
    List<String> members,
    String today, {
    required bool plus,
  }) {
    final settled = settle(s, plant, today, plus: plus);
    var streak = settled.streak;
    var p = settled.plant;
    final active = {...streak.activeToday, uid}.toList();
    streak = streak.copyWith(activeToday: active);
    var grewTo = -1;
    var newYear = false;
    if (members.every(active.contains) && streak.lastBothActiveDate != today) {
      final count = streak.count + 1;
      streak = streak.copyWith(count: count, best: max(streak.best, count), lastBothActiveDate: today);
      final stage = max(p.stage, Plant.stageForStreak(count));
      if (stage > p.stage) grewTo = stage;
      newYear = count >= 730 && count % 365 == 0;
      p = Plant(stage: stage, species: p.species);
    }
    return ActivityResult(streak, p, grewTo: grewTo < 0 ? null : grewTo, newYear: newYear);
  }

  static DateTime _parse(String key) => DateTime.utc(
        int.parse(key.substring(0, 4)),
        int.parse(key.substring(5, 7)),
        int.parse(key.substring(8, 10)),
      );

  static String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String addDays(String key, int days) => _key(_parse(key).add(Duration(days: days)));

  static int daysBetween(String a, String b) => _parse(b).difference(_parse(a)).inDays;
}

class SettleResult {
  const SettleResult(this.streak, this.plant, {required this.broke, required this.frozeDays});

  final Streak streak;
  final Plant plant;
  final bool broke;
  final int frozeDays;
}

class ActivityResult {
  const ActivityResult(this.streak, this.plant, {this.grewTo, this.newYear = false});

  final Streak streak;
  final Plant plant;
  final int? grewTo;
  final bool newYear;
}
