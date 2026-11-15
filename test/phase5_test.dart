import 'package:closer_app/core/data/closer_backend.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

Pair _pair({int stage = 0, int best = 0, PairStats stats = const PairStats(), Pet? pet, PetHome home = const PetHome()}) => Pair(
      id: 'p',
      memberIds: const ['a', 'b'],
      mode: PairMode.couple,
      pairedAt: DateTime(2026),
      plant: Plant(stage: stage),
      streak: Streak(best: best),
      stats: stats,
      pet: pet,
      home: home,
    );

void main() {
  final now = DateTime(2026, 11, 15, 12);

  group('Pet grows from the plant', () {
    test('life stage follows the plant', () {
      expect(Pet.lifeStage(3), 0);
      expect(Pet.lifeStage(5), 1);
      expect(Pet.lifeStage(7), 2);
      expect(Pet.lifeStage(8), 3);
    });

    test('mood: sleepy when wilted, then hungry, bored, happy, overjoyed', () {
      final pet = Pet(species: 'fox', name: 'Ziggy', hatchedAt: DateTime(2026, 11));
      const members = ['a', 'b'];
      expect(pet.mood(now, plant: PlantHealth.wilted, members: members), PetMood.sleepy);
      expect(pet.mood(now, plant: PlantHealth.healthy, members: members), PetMood.hungry);
      final fed = pet.copyWith(lastFed: {'a': now});
      expect(fed.mood(now, plant: PlantHealth.healthy, members: members), PetMood.bored);
      final played = fed.copyWith(lastPlayed: {'a': now});
      expect(played.mood(now, plant: PlantHealth.healthy, members: members), PetMood.happy);
      final both = played.copyWith(lastPlayed: {'a': now, 'b': now});
      expect(both.mood(now, plant: PlantHealth.healthy, members: members), PetMood.overjoyed);
      // Yesterday's care doesn't count today.
      final stale = pet.copyWith(lastFed: {'a': now.subtract(const Duration(days: 1))});
      expect(stale.fedToday(now), isFalse);
    });

    test('round-trips', () {
      final pet = Pet(species: 'panda', name: 'Bao', hatchedAt: DateTime(2026, 11, 2), lastFed: {'a': now});
      final back = Pet.fromJson(pet.toJson());
      expect(back.info.emoji, '🐼');
      expect(back.fedBy('a', now), isTrue);
      expect(PetSpecies.byId('unknown').id, 'bunny');
    });

    test('can only hatch once the plant has grown an egg', () {
      final pet = Pet(species: 'bunny', name: 'Bun', hatchedAt: now);
      expect(() => checkPet(pet, _pair(stage: 2)), throwsA(isA<CloserException>()));
      checkPet(pet, _pair(stage: 3));
      expect(() => checkPet(Pet(species: 'bunny', name: ' ', hatchedAt: now), _pair(stage: 4)), throwsA(isA<CloserException>()));
    });
  });

  group('Love points and the home', () {
    test('earned from stats, best streak and plant; spent is subtracted', () {
      final p = _pair(stage: 3, best: 7, stats: const PairStats(itemsSent: 10, tapsSent: 4, questionsAnswered: 2));
      expect(p.lovePointsEarned, 10 * 3 + 4 + 2 * 5 + 7 * 10 + 3 * 25);
      final spentSome = _pair(stage: 3, best: 7, stats: const PairStats(itemsSent: 10, tapsSent: 4, questionsAnswered: 2), home: const PetHome(spent: 50));
      expect(spentSome.lovePoints, p.lovePointsEarned - 50);
    });

    test('checkHome: no refunds, no overspending', () {
      final p = _pair(best: 5); // 50 points
      const before = PetHome(spent: 20);
      expect(() => checkHome(before, const PetHome(spent: 10), p), throwsA(isA<CloserException>()));
      expect(() => checkHome(before, const PetHome(spent: 60), p), throwsA(isA<CloserException>()));
      checkHome(before, const PetHome(spent: 50), p);
    });

    test('rewards unlock with the plant; wallpapers and decor round-trip', () {
      final heart = Decor.byId('heart')!;
      const home = PetHome();
      expect(home.ownsDecor(heart, 2), isFalse);
      expect(home.ownsDecor(heart, 3), isTrue);
      expect(home.ownsWallpaper(Wallpaper.byId('peach')), isTrue);
      expect(home.ownsWallpaper(Wallpaper.byId('night')), isFalse);
      final back = PetHome.fromJson(const PetHome(owned: ['sofa'], placed: [PlacedDecor('sofa', 0.4, 0.6)], spent: 60).toJson());
      expect(back.placed.single.x, 0.4);
      expect(back.ownsDecor(Decor.byId('sofa')!, 0), isTrue);
    });

    test('placed positions are clamped into the room', () {
      final p = PlacedDecor.fromJson(const {'id': 'rug', 'x': 4, 'y': -1});
      expect(p.x, 1);
      expect(p.y, 0);
    });
  });

  group('Mood log', () {
    test('scores and round-trip', () {
      expect(MoodEntry.scoreFor('Loved'), 5);
      expect(MoodEntry.scoreFor('Sad'), 1);
      expect(MoodEntry.scoreFor('Something new'), 3);
      final back = MoodEntry.fromJson(const MoodEntry(uid: 'a', date: '2026-11-15', emoji: '😊', label: 'Happy').toJson());
      expect(back.score, 4);
    });
  });
}
