import 'package:closer_app/core/data/closer_backend.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatMessage', () {
    test('round-trips with a reply and reactions', () {
      final m = ChatMessage(
        id: 'm',
        senderId: 'a',
        createdAt: DateTime(2026, 11, 15, 21, 30),
        text: 'Hi you',
        replyTo: const ReplyRef(id: 'x', senderId: 'b', preview: 'Hey'),
        reactions: const {'b': '❤️'},
      );
      final back = ChatMessage.fromJson('m', m.toJson());
      expect(back.type, MessageType.text);
      expect(back.replyTo?.preview, 'Hey');
      expect(back.reactions['b'], '❤️');
      expect(back.isDeleted, isFalse);
    });

    test('previews', () {
      final at = DateTime(2026);
      expect(ChatMessage(id: '', senderId: 'a', createdAt: at, type: MessageType.voice).preview, '🎤 Voice message');
      expect(ChatMessage(id: '', senderId: 'a', createdAt: at, type: MessageType.photo).preview, '📷 Photo');
      expect(ChatMessage(id: '', senderId: 'a', createdAt: at, text: 'x', deletedAt: at).preview, 'Deleted message');
      expect(ChatMessage(id: '', senderId: 'a', createdAt: at, text: 'a' * 100).preview.length, 80);
    });

    test('pending server timestamps read as now', () {
      final m = ChatMessage.fromJson('m', {'senderId': 'a', 'type': 'text', 'text': 'hi', 'createdAt': null}, pending: true);
      expect(m.pending, isTrue);
      expect(DateTime.now().difference(m.createdAt).inSeconds, lessThan(5));
    });

    test('checkMessage', () {
      expect(() => checkMessage(const ChatDraft(text: '  ')), throwsA(isA<CloserException>()));
      expect(() => checkMessage(const ChatDraft(type: MessageType.voice, localPath: '/a.m4a', durationMs: 200)), throwsA(isA<CloserException>()));
      expect(
        () => checkMessage(const ChatDraft(type: MessageType.voice, localPath: '/a.m4a', durationMs: ChatMessage.maxVoiceMs + 1)),
        throwsA(isA<CloserException>()),
      );
      checkMessage(const ChatDraft(type: MessageType.voice, localPath: '/a.m4a', durationMs: 3000));
      checkMessage(const ChatDraft(type: MessageType.photo, localPath: '/a.jpg'));
    });
  });

  group('ChatState', () {
    test('typing expires', () {
      final s = ChatState(typingUntil: DateTime(2026, 1, 1, 12, 0, 6));
      expect(s.isTyping(DateTime(2026, 1, 1, 12)), isTrue);
      expect(s.isTyping(DateTime(2026, 1, 1, 12, 0, 7)), isFalse);
      expect(const ChatState().isTyping(DateTime(2026)), isFalse);
    });
  });

  group('Goodnight', () {
    test('nights start in the evening; after midnight is still the same night', () {
      expect(Goodnight.keyFor(DateTime(2026, 11, 15, 22)), '2026-11-15');
      expect(Goodnight.keyFor(DateTime(2026, 11, 16, 1, 30)), '2026-11-15');
      expect(Goodnight.keyFor(DateTime(2026, 11, 16, 9)), '2026-11-16');
      expect(Goodnight.isEvening(DateTime(2026, 1, 1, 19)), isTrue);
      expect(Goodnight.isEvening(DateTime(2026, 1, 1, 3)), isTrue);
      expect(Goodnight.isEvening(DateTime(2026, 1, 1, 12)), isFalse);
    });

    test('round-trips and knows when both are done', () {
      final g = Goodnight(
        night: '2026-11-15',
        entries: {
          'a': GoodnightEntry(message: 'Night!', kiss: true, sentAt: DateTime(2026, 11, 15, 23)),
        },
      );
      final back = Goodnight.fromJson('2026-11-15', g.toJson());
      expect(back.doneBy('a'), isTrue);
      expect(back.doneBy('b'), isFalse);
      expect(back.complete(['a', 'b']), isFalse);
      expect(back.entries['a']!.kiss, isTrue);
    });

    test('an empty goodnight is rejected', () {
      expect(() => checkGoodnight(const GoodnightEntry()), throwsA(isA<CloserException>()));
      checkGoodnight(const GoodnightEntry(kiss: true));
    });
  });

  test('chat notification preference defaults on and round-trips', () {
    expect(const NotificationPrefs().chat, isTrue);
    expect(NotificationPrefs.fromJson(const NotificationPrefs(chat: false).toJson()).chat, isFalse);
  });
}
