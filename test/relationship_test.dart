import 'package:closer_app/core/data/local/text_repair.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('repairMojibake', () {
    test('fixes emoji that were saved as cp1252 mojibake', () {
      // "🥰" (F0 9F A5 B0) and "👋" (F0 9F 91 8B) as broken by the old build.
      expect(repairMojibake('ðŸ¥° Missing you'), '🥰 Missing you');
      expect(repairMojibake('Hi you ðŸ‘‹ Found you'), 'Hi you 👋 Found you');
      expect(repairMojibake('Youâ€™re the best'), 'You’re the best');
    });

    test('leaves correct text alone', () {
      expect(repairMojibake('Plain ascii'), isNull);
      expect(repairMojibake('Fiancé'), isNull);
      expect(repairMojibake('Miss you 💕'), isNull);
    });

    test('repairs nested json in place', () {
      final db = <String, dynamic>{
        'users': {
          'sim': {'mood': {'label': 'Missing you', 'emoji': 'ðŸ¥°'}},
        },
        'list': ['ok', 'Youâ€™re'],
      };
      expect(repairJsonTree(db), 2);
      expect(((db['users'] as Map)['sim'] as Map)['mood'], {'label': 'Missing you', 'emoji': '🥰'});
      expect(db['list'], ['ok', 'You’re']);
    });
  });

  group('Relationship', () {
    test('labels are only valid for their own mode', () {
      expect(RelationLabel.validFor('girlfriend', PairMode.couple), 'girlfriend');
      expect(RelationLabel.validFor('girlfriend', PairMode.friends), isNull);
      expect(RelationLabel.validFor('bff', PairMode.friends), 'bff');
      expect(RelationLabel.validFor('nope', PairMode.couple), isNull);
      expect(RelationLabel.validFor(null, PairMode.couple), isNull);
    });

    test('pair reads labels, nicknames and days together', () {
      final pair = Pair.fromJson('p', {
        'memberIds': ['a', 'b'],
        'mode': 'couple',
        'anniversary': DateTime(2026, 11, 1).millisecondsSinceEpoch,
        'relationLabels': {'a': 'girlfriend', 'b': 'bff'},
        'nicknames': {'a': 'Babe'},
      });
      expect(pair.labelBy('a')?.title, 'Girlfriend');
      // A friends label in a couple pair is ignored.
      expect(pair.labelBy('b'), isNull);
      expect(pair.nicknames['a'], 'Babe');
      expect(pair.daysTogether(DateTime(2026, 11, 8, 23)), 7);
      expect(Pair.fromJson('q', pair.toJson()).anniversary, DateTime(2026, 11, 1));
    });
  });
}
