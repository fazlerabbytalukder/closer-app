import 'package:closer_app/core/data/closer_backend.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ChatMessage snap({int limit = 2, int views = 0, String? media = 'pairs/p/media/u/a.jpg'}) => ChatMessage.fromJson(
    'm',
    {'senderId': 'u', 'type': 'snap', 'mediaPath': media, 'viewLimit': limit, 'views': views},
  );

  test('snap counts views left and is used up at the limit', () {
    expect(snap().snapViewsLeft, 2);
    expect(snap(views: 1).snapUsedUp, isFalse);
    expect(snap(views: 2).snapUsedUp, isTrue);
    expect(snap(limit: 1, views: 1).snapUsedUp, isTrue);
  });

  test('snap with its photo deleted is used up', () {
    expect(snap(media: null).snapUsedUp, isTrue);
  });

  test('old messages without the new fields still parse', () {
    final m = ChatMessage.fromJson('m', {'senderId': 'u', 'type': 'photo', 'mediaPath': 'x'});
    expect(m.viewLimit, 0);
    expect(m.event, isNull);
    expect(m.snapUsedUp, isFalse);
  });

  test('events round-trip through json', () {
    final m = ChatMessage(
      id: 'e',
      senderId: 'u',
      type: MessageType.event,
      event: ChatEvent.screenshot,
      createdAt: DateTime(2026),
    );
    final back = ChatMessage.fromJson('e', m.toJson());
    expect(back.isEvent, isTrue);
    expect(back.event, ChatEvent.screenshot);
  });

  test('snap drafts must open once or twice', () {
    expect(
      () => checkMessage(const ChatDraft(type: MessageType.snap, localPath: 'a.jpg')),
      throwsA(isA<CloserException>()),
    );
    expect(
      () => checkMessage(const ChatDraft(type: MessageType.snap, localPath: 'a.jpg', viewLimit: 3)),
      throwsA(isA<CloserException>()),
    );
    checkMessage(const ChatDraft(type: MessageType.snap, localPath: 'a.jpg', viewLimit: 1));
  });

  group('disappearing messages', () {
    final sent = DateTime(2026, 11, 1, 12);
    ChatMessage msg(ChatTtl? ttl) => ChatMessage(id: 'm', senderId: 'u', createdAt: sent, text: 'hi', ttl: ttl);

    test('pairs default to 24 hours', () {
      expect(Pair.fromJson('p', const {}).chatTtl, ChatTtl.day);
      expect(Pair.fromJson('p', const {'chatTtl': 'week'}).chatTtl, ChatTtl.week);
    });

    test('timed messages expire after their duration', () {
      expect(msg(ChatTtl.day).isExpired(sent.add(const Duration(hours: 23))), isFalse);
      expect(msg(ChatTtl.day).isExpired(sent.add(const Duration(hours: 25))), isTrue);
      expect(msg(ChatTtl.week).expiresAt, sent.add(const Duration(days: 7)));
      expect(msg(ChatTtl.year).isExpired(sent.add(const Duration(days: 300))), isFalse);
    });

    test('never, after-viewing and older messages are not timed', () {
      final later = sent.add(const Duration(days: 9999));
      expect(msg(ChatTtl.never).isExpired(later), isFalse);
      expect(msg(ChatTtl.viewed).isExpired(later), isFalse);
      expect(msg(null).isExpired(later), isFalse);
    });

    test('ttl round-trips and old messages have none', () {
      expect(ChatMessage.fromJson('m', msg(ChatTtl.month).toJson()).ttl, ChatTtl.month);
      expect(ChatMessage.fromJson('m', const {'senderId': 'u', 'text': 'old'}).ttl, isNull);
    });

    test('a ttl event needs a known setting', () {
      expect(
        () => checkMessage(const ChatDraft(type: MessageType.event, event: ChatEvent.ttl, text: 'forever')),
        throwsA(isA<CloserException>()),
      );
      checkMessage(const ChatDraft(type: MessageType.event, event: ChatEvent.ttl, text: 'week'));
    });
  });
}
