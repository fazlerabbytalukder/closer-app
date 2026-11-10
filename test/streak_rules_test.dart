import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/models/streak_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const members = ['a', 'b'];
  const healthy = Plant(stage: 3);

  Streak running(int count, {int freezes = 1, String last = '2026-11-09'}) => Streak(
        count: count,
        best: count,
        lastBothActiveDate: last,
        freezesLeft: freezes,
        freezesMonth: '2026-11',
        activeDate: last,
        checkedThrough: StreakRules.addDays(last, -1),
      );

  group('a day', () {
    test('counts only when both members show up, once per day', () {
      var r = StreakRules.markActive(running(7), healthy, 'a', members, '2026-11-10', plus: false);
      expect(r.streak.count, 7, reason: 'one member is not enough');
      r = StreakRules.markActive(r.streak, r.plant, 'b', members, '2026-11-10', plus: false);
      expect(r.streak.count, 8);
      r = StreakRules.markActive(r.streak, r.plant, 'a', members, '2026-11-10', plus: false);
      expect(r.streak.count, 8, reason: 'more activity the same day adds nothing');
    });

    test("yesterday's ticks do not show as today", () {
      final s = running(3).copyWith(activeToday: ['a']);
      expect(s.activeOn('2026-11-09'), ['a']);
      expect(s.activeOn('2026-11-10'), isEmpty);
    });

    test('plant grows at milestones and reports it', () {
      final r1 = StreakRules.markActive(running(6), healthy, 'a', members, '2026-11-10', plus: false);
      final r2 = StreakRules.markActive(r1.streak, r1.plant, 'b', members, '2026-11-10', plus: false);
      expect(r2.streak.count, 7);
      expect(r2.plant.stage, 3, reason: 'stage 3 already reached at 7');
      final r3 = StreakRules.markActive(running(13), healthy, 'a', members, '2026-11-10', plus: false);
      final r4 = StreakRules.markActive(r3.streak, r3.plant, 'b', members, '2026-11-10', plus: false);
      expect(r4.plant.stage, 4);
      expect(r4.grewTo, 4);
    });
  });

  group('missed days', () {
    test('a missed day spends a freeze and keeps the streak', () {
      // Last both-active 8 Nov, nobody on 9 Nov, now 10 Nov.
      final r = StreakRules.settle(running(12, last: '2026-11-08'), healthy, '2026-11-10', plus: false);
      expect(r.broke, isFalse);
      expect(r.frozeDays, 1);
      expect(r.streak.count, 12);
      expect(r.streak.freezesLeft, 0);
      expect(r.streak.lastFrozeDate, '2026-11-09');
      expect(r.plant.health, PlantHealth.healthy);
    });

    test('no freeze left: streak resets, plant wilts but keeps size', () {
      final r = StreakRules.settle(running(12, freezes: 0, last: '2026-11-08'), healthy, '2026-11-10', plus: false);
      expect(r.broke, isTrue);
      expect(r.streak.count, 0);
      expect(r.streak.best, 12);
      expect(r.streak.lostCount, 12);
      expect(r.streak.brokeDate, '2026-11-09');
      expect(r.plant.health, PlantHealth.wilted);
      expect(r.plant.stage, 3);
    });

    test('several missed days use freezes one by one, then break', () {
      // Plus (3 freezes), away 9..13 Nov (5 days).
      final r = StreakRules.settle(running(40, freezes: 3, last: '2026-11-08'), healthy, '2026-11-14', plus: true);
      expect(r.frozeDays, 3);
      expect(r.broke, isTrue);
      expect(r.streak.brokeDate, '2026-11-12');
      expect(r.streak.lostCount, 40);
    });

    test('settling twice changes nothing', () {
      final once = StreakRules.settle(running(12, last: '2026-11-08'), healthy, '2026-11-10', plus: false);
      final twice = StreakRules.settle(once.streak, once.plant, '2026-11-10', plus: false);
      expect(twice.frozeDays, 0);
      expect(twice.streak.toJson(), once.streak.toJson());
    });

    test('both showing up revives the plant at streak 1', () {
      final broken = StreakRules.settle(running(12, freezes: 0, last: '2026-11-08'), healthy, '2026-11-10', plus: false);
      final a = StreakRules.markActive(broken.streak, broken.plant, 'a', members, '2026-11-10', plus: false);
      final b = StreakRules.markActive(a.streak, a.plant, 'b', members, '2026-11-10', plus: false);
      expect(b.streak.count, 1);
      expect(b.plant.health, PlantHealth.healthy);
      expect(b.plant.stage, 3);
      expect(b.plant.nextGrowthAt, 14, reason: 'grows again once the new streak passes its milestone');
    });
  });

  group('freezes', () {
    test('refill on a new month, unused ones do not carry over', () {
      final s = running(5, last: '2026-11-30').copyWith(checkedThrough: '2026-11-30');
      final r = StreakRules.settle(s, healthy, '2026-12-01', plus: true);
      expect(r.streak.freezesLeft, 3);
      expect(r.streak.freezesMonth, '2026-12');
    });
  });

  group('after one year', () {
    test('day 365 reaches full bloom', () {
      final a = StreakRules.markActive(running(364), const Plant(stage: 7), 'a', members, '2026-11-10', plus: false);
      final b = StreakRules.markActive(a.streak, a.plant, 'b', members, '2026-11-10', plus: false);
      expect(b.plant.stage, 8);
      expect(b.plant.fullyGrown, isTrue);
      expect(b.plant.nextGrowthAt, isNull);
      expect(b.streak.years, 1);
    });

    test('day 730 is bloom year 2', () {
      final a = StreakRules.markActive(running(729), const Plant(stage: 8), 'a', members, '2026-11-10', plus: false);
      final b = StreakRules.markActive(a.streak, a.plant, 'b', members, '2026-11-10', plus: false);
      expect(b.streak.years, 2);
      expect(b.newYear, isTrue);
      expect(b.grewTo, isNull);
    });
  });
}
