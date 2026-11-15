import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/always_with_me.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TapKind', () {
    test('unknown kinds fall back to the heart', () {
      expect(TapKind.byId('nope'), TapKind.heart);
      expect(TapKind.byId(null), TapKind.heart);
      expect(TapKind.byId('miss').emoji, '🥺');
    });

    test('ids are unique', () {
      expect(TapKind.all.map((k) => k.id).toSet().length, TapKind.all.length);
    });
  });

  group('Item reactions and secret admirer', () {
    final item = Item(
      id: 'i',
      type: ItemType.note,
      senderId: 'a',
      createdAt: DateTime(2026, 11, 1),
      reactions: const {'b': '❤️'},
      secret: true,
    );

    test('round-trips through JSON', () {
      final back = Item.fromJson('i', item.toJson());
      expect(back.reactions, {'b': '❤️'});
      expect(back.secret, isTrue);
      expect(back.revealedAt, isNull);
    });

    test('old items without the new fields still parse', () {
      final old = Item.fromJson('i', {'type': 'photo', 'senderId': 'a', 'createdAt': 0});
      expect(old.reactions, isEmpty);
      expect(old.secret, isFalse);
    });

    test('sender is hidden only from the receiver until revealed', () {
      expect(item.hidesSenderFrom('b'), isTrue);
      expect(item.hidesSenderFrom('a'), isFalse);
      expect(item.copyWith(revealedAt: DateTime(2026, 11, 2)).hidesSenderFrom('b'), isFalse);
    });

    test('latest item keeps the secret flag', () {
      final l = LatestItem.fromJson(LatestItem(itemId: 'i', type: ItemType.note, sentAt: DateTime(2026), secret: true).toJson());
      expect(l.secret, isTrue);
    });
  });

  group('MissMeter', () {
    test('parses revealed values', () {
      final m = MissMeter.fromJson('2026-11-15', {
        'answeredBy': ['a', 'b'],
        'revealed': true,
        'values': {'a': 80, 'b': 95},
      });
      expect(m.values['b'], 95);
      expect(m.withMyValue(80).myValue, 80);
      expect(m.withMyValue(80).values['a'], 80);
    });

    test('describes the scale', () {
      expect(MissMeter.describe(0), contains('tiny'));
      expect(MissMeter.describe(100), contains('moon'));
    });
  });

  group('Pair.lastMetAt', () {
    test('round-trips', () {
      final p = Pair(id: 'p', memberIds: const ['a', 'b'], mode: PairMode.couple, pairedAt: DateTime(2026), lastMetAt: DateTime(2026, 11, 10, 18));
      expect(Pair.fromJson('p', p.toJson()).lastMetAt, DateTime(2026, 11, 10, 18));
    });
  });

  group('AlwaysWithMe', () {
    final now = DateTime(2026, 11, 15, 20);

    test('time since you met', () {
      expect(AlwaysWithMe.sinceLabel(null, now), contains('When'));
      expect(AlwaysWithMe.sinceLabel(now.subtract(const Duration(minutes: 20)), now), contains('right now'));
      expect(AlwaysWithMe.sinceLabel(now.subtract(const Duration(hours: 5)), now), 'Saw each other 5 h ago');
      expect(AlwaysWithMe.sinceLabel(now.subtract(const Duration(days: 1, hours: 2)), now), '1 day since we met');
      expect(AlwaysWithMe.sinceLabel(now.subtract(const Duration(days: 12)), now), '12 days since we met');
    });

    test('a recent partner tap becomes the message', () {
      final tap = Tap(id: 't', senderId: 'b', kind: 'miss', createdAt: now.subtract(const Duration(hours: 2)));
      expect(AlwaysWithMe.message(mode: PairMode.couple, now: now, partnerName: 'Sam', partnerTap: tap), 'Sam misses you so much 🥺');
      final old = Tap(id: 't', senderId: 'b', kind: 'miss', createdAt: now.subtract(const Duration(days: 2)));
      expect(AlwaysWithMe.message(mode: PairMode.couple, now: now, partnerTap: old), isNot(contains('misses')));
    });

    test('memory of the day prefers the partner and is stable within a day', () {
      Item photo(String id, String sender, int day) => Item(
            id: id,
            type: ItemType.photo,
            senderId: sender,
            thumbPath: '/t/$id.jpg',
            createdAt: DateTime(2026, 10, day),
          );
      final items = [photo('mine', 'a', 1), photo('p1', 'b', 2), photo('p2', 'b', 3)];
      final morning = AlwaysWithMe.memoryOfTheDay(items, partnerUid: 'b', now: DateTime(2026, 11, 15, 8));
      final night = AlwaysWithMe.memoryOfTheDay(items, partnerUid: 'b', now: DateTime(2026, 11, 15, 23));
      expect(morning?.senderId, 'b');
      expect(morning?.id, night?.id);
      expect(AlwaysWithMe.memoryOfTheDay(items, partnerUid: 'zzz', now: now), isNotNull);
      expect(AlwaysWithMe.memoryOfTheDay(const [], partnerUid: 'b', now: now), isNull);
    });
  });
}
