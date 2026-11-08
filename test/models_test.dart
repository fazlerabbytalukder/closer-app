import 'package:closer_app/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Plant', () {
    test('grows one stage per milestone', () {
      expect(Plant.stageForStreak(0), 0);
      expect(Plant.stageForStreak(1), 1);
      expect(Plant.stageForStreak(6), 2);
      expect(Plant.stageForStreak(7), 3);
      expect(Plant.stageForStreak(365), 8);
      expect(Plant.stageForStreak(1000), 8);
    });
  });

  group('Countdown', () {
    final now = DateTime(2026, 11, 8, 23, 30);

    test('days left ignores time of day', () {
      final c = Countdown(id: 'a', title: 'Paris', date: DateTime(2026, 11, 10), createdBy: 'u');
      expect(c.daysLeft(now), 2);
    });

    test('yearly dates roll forward', () {
      final c = Countdown(id: 'a', title: 'Anniversary', date: DateTime(2020, 3, 1), createdBy: 'u', repeatsYearly: true);
      expect(c.nextOccurrence(now), DateTime(2027, 3, 1));
    });

    test('one-off past dates stay in the past', () {
      final c = Countdown(id: 'a', title: 'Old', date: DateTime(2026, 1, 1), createdBy: 'u');
      expect(c.daysLeft(now), isNegative);
    });
  });

  group('Game', () {
    test('score counts matching guesses', () {
      final g = Game(
        id: 'g',
        subjectUid: 'a',
        guesserUid: 'b',
        questions: const [],
        createdAt: DateTime(2026),
        subjectAnswers: const [0, 1, 2, 3, 0],
        guesses: const [0, 1, 0, 3, 1],
        status: GameStatus.done,
      );
      expect(g.score, 3);
    });

    test('json round trip keeps answers and status', () {
      final g = Game(
        id: 'g',
        subjectUid: 'a',
        guesserUid: 'b',
        questions: const [GameQuestion(text: 'Q', options: ['x', 'y'])],
        createdAt: DateTime(2026, 5, 1),
        subjectAnswers: const [1],
        status: GameStatus.guesserTurn,
      );
      final back = Game.fromJson('g', g.toJson());
      expect(back.subjectAnswers, [1]);
      expect(back.status, GameStatus.guesserTurn);
      expect(back.questions.single.options, ['x', 'y']);
    });
  });

  group('Pair', () {
    test('json round trip and partnerOf', () {
      final p = Pair(
        id: 'p',
        memberIds: const ['a', 'b'],
        mode: PairMode.friends,
        pairedAt: DateTime(2026, 1, 2),
        latestItemByUser: {
          'b': LatestItem(itemId: 'i', type: ItemType.note, sentAt: DateTime(2026, 1, 3), caption: 'hi'),
        },
        streak: const Streak(count: 4, best: 9, activeToday: ['a']),
        plant: const Plant(stage: 2, health: PlantHealth.wilted),
        widgetTheme: const {'a': 'mint'},
      );
      final back = Pair.fromJson('p', p.toJson());
      expect(back.partnerOf('a'), 'b');
      expect(back.mode, PairMode.friends);
      expect(back.latestItemByUser['b']!.caption, 'hi');
      expect(back.latestItemByUser['b']!.type, ItemType.note);
      expect(back.streak.best, 9);
      expect(back.plant.health, PlantHealth.wilted);
      expect(back.widgetTheme['a'], 'mint');
    });
  });

  group('NotificationPrefs', () {
    test('copyWith can clear quiet hours', () {
      const p = NotificationPrefs(quietStart: 22, quietEnd: 8);
      final cleared = p.copyWith(quietStart: () => null, quietEnd: () => null);
      expect(cleared.quietStart, isNull);
      expect(NotificationPrefs.fromJson(p.toJson()).quietEnd, 8);
    });
  });
}
