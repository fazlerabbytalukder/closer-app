import 'package:closer_app/core/data/closer_backend.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ChatMessage snap({int limit = 2, int views = 0, String? media = 'pairs/p/media/u/a.jpg'}) => ChatMessage.fromJson('m', {
    'senderId': 'u',
    'type': 'snap',
    'mediaPath': media,
    'viewLimit': limit,
    'views': views,
  });

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
    final m = ChatMessage(id: 'e', senderId: 'u', type: MessageType.event, event: ChatEvent.screenshot, createdAt: DateTime(2026));
    final back = ChatMessage.fromJson('e', m.toJson());
    expect(back.isEvent, isTrue);
    expect(back.event, ChatEvent.screenshot);
  });

  test('snap drafts must open once or twice', () {
    expect(() => checkMessage(const ChatDraft(type: MessageType.snap, localPath: 'a.jpg')), throwsA(isA<CloserException>()));
    expect(() => checkMessage(const ChatDraft(type: MessageType.snap, localPath: 'a.jpg', viewLimit: 3)), throwsA(isA<CloserException>()));
    checkMessage(const ChatDraft(type: MessageType.snap, localPath: 'a.jpg', viewLimit: 1));
  });
}
