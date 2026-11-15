import 'package:closer_app/core/data/closer_backend.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

Capsule _reason(DateTime unlockAt) => Capsule(
      id: 'r${unlockAt.millisecondsSinceEpoch}',
      kind: CapsuleKind.reason,
      authorId: 'a',
      forUid: 'b',
      createdAt: unlockAt,
      unlockAt: unlockAt,
    );

void main() {
  group('Capsule', () {
    final c = Capsule(
      id: 'c',
      kind: CapsuleKind.surprise,
      authorId: 'a',
      forUid: 'b',
      title: 'Hi',
      surpriseType: SurpriseType.gift,
      createdAt: DateTime(2026, 11, 1),
      unlockAt: DateTime(2026, 11, 2, 9),
    );

    test('round-trips through JSON', () {
      final back = Capsule.fromJson('c', c.toJson());
      expect(back.kind, CapsuleKind.surprise);
      expect(back.surpriseType, SurpriseType.gift);
      expect(back.unlockAt, DateTime(2026, 11, 2, 9));
      expect(back.openedAt, isNull);
      expect(back, c);
    });

    test('is new only for the receiver, once unlocked and unopened', () {
      expect(c.isNewFor('b', DateTime(2026, 11, 2, 8)), isFalse);
      expect(c.isNewFor('b', DateTime(2026, 11, 2, 9)), isTrue);
      expect(c.isNewFor('a', DateTime(2026, 11, 3)), isFalse);
    });
  });

  group('nextReasonUnlock', () {
    test('first reason unlocks this morning, or right away after 08:00', () {
      expect(Capsule.nextReasonUnlock(const [], DateTime(2026, 11, 15, 6)), DateTime(2026, 11, 15, 8));
      final late = DateTime(2026, 11, 15, 20);
      expect(Capsule.nextReasonUnlock(const [], late), late);
    });

    test('then one a day', () {
      final now = DateTime(2026, 11, 15, 20);
      final queued = [_reason(DateTime(2026, 11, 15, 8)), _reason(DateTime(2026, 11, 16, 8)), _reason(DateTime(2026, 11, 17, 8))];
      expect(Capsule.nextReasonUnlock(queued, now), DateTime(2026, 11, 18, 8));
    });

    test('after a gap the next one unlocks today', () {
      final now = DateTime(2026, 11, 15, 7);
      expect(Capsule.nextReasonUnlock([_reason(DateTime(2026, 11, 1, 8))], now), DateTime(2026, 11, 15, 8));
    });
  });

  group('checkCapsule', () {
    Capsule env(CapsuleKind k, [SurpriseType? t]) =>
        Capsule(id: '', kind: k, authorId: '', forUid: '', surpriseType: t, createdAt: DateTime(2026), unlockAt: DateTime(2026));

    test('reasons need text and stop at 100', () {
      expect(() => checkCapsule(env(CapsuleKind.reason), const CapsuleContent(), reasonsWritten: 0), throwsA(isA<CloserException>()));
      expect(() => checkCapsule(env(CapsuleKind.reason), const CapsuleContent(text: 'x'), reasonsWritten: 100), throwsA(isA<CloserException>()));
      checkCapsule(env(CapsuleKind.reason), const CapsuleContent(text: 'You’re kind'), reasonsWritten: 99);
    });

    test('gifts need a known gift, photos need a photo', () {
      expect(
        () => checkCapsule(env(CapsuleKind.surprise, SurpriseType.gift), const CapsuleContent(giftId: 'yacht'), reasonsWritten: 0),
        throwsA(isA<CloserException>()),
      );
      checkCapsule(env(CapsuleKind.surprise, SurpriseType.gift), const CapsuleContent(giftId: 'rose'), reasonsWritten: 0);
      expect(
        () => checkCapsule(env(CapsuleKind.surprise, SurpriseType.photo), const CapsuleContent(text: 'hi'), reasonsWritten: 0),
        throwsA(isA<CloserException>()),
      );
    });
  });

  group('TimelineEntry', () {
    test('round-trips and validates', () {
      final e = TimelineEntry(id: 't', date: DateTime(2024, 2, 14), title: 'First date', emoji: '☕', createdBy: 'a');
      final back = TimelineEntry.fromJson('t', e.toJson());
      expect(back.title, 'First date');
      expect(back.date, DateTime(2024, 2, 14));
      expect(back.auto, isFalse);
      expect(() => checkTimelineEntry(TimelineEntry(id: '', date: DateTime(2024), title: ' ', createdBy: 'a')), throwsA(isA<CloserException>()));
    });
  });

  group('Shrine', () {
    test('round-trips', () {
      const s = Shrine(
        ownerUid: 'a',
        title: 'For you',
        theme: 'mint',
        favorites: [ShrineFavorite('Song', 'Ours')],
        messages: ['Hi'],
        photos: ['p1'],
      );
      final back = Shrine.fromJson('a', s.toJson());
      expect(back.favorites.single.value, 'Ours');
      expect(back.theme, 'mint');
      expect(back.isEmpty, isFalse);
      expect(const Shrine(ownerUid: 'a').isEmpty, isTrue);
    });

    test('clamp keeps limits and a known theme', () {
      final big = Shrine(
        ownerUid: 'a',
        theme: 'neon',
        photos: List.generate(20, (i) => 'p$i'),
        messages: List.generate(30, (i) => 'm$i'),
      );
      final c = clampShrine(big);
      expect(c.photos.length, Shrine.maxPhotos);
      expect(c.messages.length, Shrine.maxMessages);
      expect(c.theme, Shrine.themes.first);
    });
  });
}
