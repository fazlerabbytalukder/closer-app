import 'dart:async';
import 'dart:math';

import 'package:closer_app/core/data/local/local_backend.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/note_renderer.dart';

/// Plays "your person" when running on the local backend, so the full loop
/// can be tried on one device: they join your invite, send notes back, tap
/// back, answer the daily question and take their turn in games.
class PartnerSimulator {
  PartnerSimulator(this._b, this._scale);

  final LocalBackend _b;
  final Duration _scale;
  final _rand = Random();
  final _timers = <Timer>[];

  static const partnerUid = 'sim_partner';

  Duration _s(num seconds) => Duration(milliseconds: (_scale.inMilliseconds * seconds).round());

  void _later(num seconds, void Function() fn) {
    _timers.add(
      Timer(_s(seconds), () {
        try {
          fn();
        } on Object {
          // The simulated partner must never crash the app.
        }
      }),
    );
  }

  String? get _pairId => _b.currentUid == null ? null : _b.myPairId;

  bool get _partnerInPair {
    final id = _pairId;
    return id != null && (_b.pairOf(id)?.memberIds.contains(partnerUid) ?? false);
  }

  String ensurePartner(PairMode mode) {
    if (_b.userDoc(partnerUid) == null) {
      final couple = mode == PairMode.couple;
      _b.putUser(
        AppUser(
          uid: partnerUid,
          displayName: couple ? 'Sam' : 'Alex',
          createdAt: DateTime.now(),
          mood: Mood(emoji: '🥰', label: couple ? 'Missing you' : 'Hyped', updatedAt: DateTime.now()),
          status: StatusText(text: 'Thinking of you 💭', updatedAt: DateTime.now()),
        ),
      );
    } else {
      _b.patchUser(partnerUid, {'pairId': null});
    }
    // What the simulated partner calls you.
    _b.patchUser(partnerUid, {'pendingLabel': mode == PairMode.couple ? 'partner' : 'best_friend'});
    return partnerUid;
  }

  /// Called on app start: finish anything that was pending.
  void resume() {
    final id = _pairId;
    if (id == null || !_partnerInPair) return;
    onNewQuestion(id, dayKey(DateTime.now()));
    // Pairs made before the love features existed get them too.
    if (_b.simState['seededLove'] != true) _later(3, () => _seedLove(id));
    if (_b.simState['seededPlan'] != true) _later(4, () => _seedPlan(id));
    if (_b.simState['seededMoods'] != true) _later(5, () => _seedMoods(id));
    // They look after the pet once a day too.
    _later(30, () => onPetChanged(id));
  }

  void onInviteCreated(Invite invite) {
    // Partner "opens the link" a few seconds after the invite is shown.
    _later(6, () {
      final me = _b.currentUid;
      if (me == null || _b.myPairId != null) return;
      final raw = _b.simState['joinedInvite'];
      if (raw == invite.code) return;
      _b.simState['joinedInvite'] = invite.code;
      ensurePartner(invite.mode);
      _b.createPair(me, partnerUid, invite.mode);
    });
  }

  void onPaired(String pairId) {
    if (!_partnerInPair) return;
    _later(8, () => _sendNote(pairId, _pick(_hello)));
    // A game where the partner already answered, so it's your turn to guess.
    _later(20, () {
      final g = _b.createGame(pairId, partnerUid);
      _b.applyGameAnswers(pairId, g.id, partnerUid, [for (final q in g.questions) _rand.nextInt(q.options.length)]);
    });
    _later(12, () => _b.writeTap(pairId, partnerUid, 'heart'));
    _later(15, () => _seedLove(pairId));
    _later(18, () => _seedPlan(pairId));
    _later(20, () => _seedMoods(pairId));
    _later(10, () => _b.writeMessage(pairId, partnerUid, const ChatDraft(text: 'Hiii 👋 we have our own chat now!')));
    // A secret-admirer note that gets revealed a minute later.
    _later(35, () async {
      try {
        final item = await _sendNote(pairId, 'Someone here thinks you’re amazing 👀', secret: true);
        if (item != null) _later(60, () => _b.revealItem(pairId, item.id, partnerUid));
      } on Object {
        // The simulated partner must never crash the app.
      }
    });
  }

  void onUnpaired() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  void onMyItem(Item item) {
    final id = _pairId;
    if (id == null || !_partnerInPair) return;
    _later(4, () => _b.writeTap(id, partnerUid, 'heart'));
    _later(7, () => _b.setReaction(id, item.id, partnerUid, _pick(reactionEmojis)));
    // Reply with a note now and then, not to every single item.
    final last = _b.simState['lastReply'] as int? ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - last > const Duration(seconds: 90).inMilliseconds) {
      _b.simState['lastReply'] = now;
      _later(10, () => _sendNote(id, _pick(_replies)));
    }
  }

  void onMyTap(TapKind kind) {
    final id = _pairId;
    if (id == null || !_partnerInPair) return;
    // Answer a "miss you" with a "miss you", anything else with a heart.
    final back = switch (kind.id) {
      'miss' => 'miss',
      'thinking' => 'love',
      'hug' => 'hug',
      'kiss' => 'kiss',
      _ => 'heart',
    };
    _later(5, () => _b.writeTap(id, partnerUid, back));
  }

  /// Reasons, a letter that opens in a few minutes, a surprise gift and a
  /// shrine, so every love feature has something in it.
  void _seedLove(String pairId) {
    if (!_partnerInPair || _b.simState['seededLove'] == true) return;
    _b.simState['seededLove'] = true;
    final now = DateTime.now();
    for (final text in _reasons.take(4)) {
      final mine = _b.pairOf(pairId) == null ? const <Capsule>[] : _partnerCapsules(pairId);
      _b.writeCapsule(
        pairId,
        partnerUid,
        Capsule(
          id: '',
          kind: CapsuleKind.reason,
          authorId: partnerUid,
          forUid: '',
          createdAt: now,
          unlockAt: Capsule.nextReasonUnlock(mine, now),
        ),
        CapsuleContent(text: text),
      );
    }
    _b
      ..writeCapsule(
        pairId,
        partnerUid,
        Capsule(
          id: '',
          kind: CapsuleKind.letter,
          authorId: partnerUid,
          forUid: '',
          title: 'Open when you miss me',
          createdAt: now,
          unlockAt: now.add(_s(180)),
        ),
        const CapsuleContent(
          text:
              'Hey you,\n\nIf you’re reading this, you probably miss me a little. I miss you too — '
              'way more than a little.\n\nClose your eyes for a second and imagine the biggest hug. '
              'That one’s from me. Talk soon? 💗',
        ),
      )
      ..writeCapsule(
        pairId,
        partnerUid,
        Capsule(
          id: '',
          kind: CapsuleKind.letter,
          authorId: partnerUid,
          forUid: '',
          title: 'Open on our next anniversary',
          createdAt: now,
          unlockAt: now.add(const Duration(days: 60)),
        ),
        const CapsuleContent(text: 'No peeking until then! 🙈'),
      )
      ..writeCapsule(
        pairId,
        partnerUid,
        Capsule(
          id: '',
          kind: CapsuleKind.surprise,
          authorId: partnerUid,
          forUid: '',
          surpriseType: SurpriseType.gift,
          createdAt: now,
          unlockAt: now.add(_s(45)),
        ),
        const CapsuleContent(text: 'Because you deserve flowers today 🌷', giftId: 'bouquet'),
      )
      ..putShrine(
        pairId,
        partnerUid,
        const Shrine(
          ownerUid: partnerUid,
          title: 'Everything I love about you',
          theme: 'lavender',
          favorites: [
            ShrineFavorite('Song', 'The one we danced to in the kitchen'),
            ShrineFavorite('Food', 'Your terrible-but-amazing pancakes'),
            ShrineFavorite('Thing about you', 'How you laugh at your own jokes'),
            ShrineFavorite('Place', 'Anywhere next to you'),
          ],
          messages: ['You make the hard days easier.', 'I’m so lucky I found you ✨'],
        ),
      );
  }

  List<Capsule> _partnerCapsules(String pairId) => [
    for (final e in _b.simStateCapsules(pairId).entries)
      if ((e.value as Map)['authorId'] == partnerUid)
        Capsule.fromJson(e.key, Map<String, dynamic>.from(e.value as Map)),
  ];

  void onMyCapsule(Capsule c) {
    final id = _pairId;
    if (id == null || !_partnerInPair) return;
    switch (c.kind) {
      case CapsuleKind.surprise:
        // A surprise back, a little later.
        _later(25, () {
          final now = DateTime.now();
          _b.writeCapsule(
            id,
            partnerUid,
            Capsule(
              id: '',
              kind: CapsuleKind.surprise,
              authorId: partnerUid,
              forUid: '',
              surpriseType: SurpriseType.compliment,
              createdAt: now,
              unlockAt: now,
            ),
            CapsuleContent(text: _pick(compliments)),
          );
        });
      case CapsuleKind.reason:
        // Answer every reason with one of their own (while they last).
        final used = _b.simState['reasonsUsed'] as int? ?? 4;
        if (used >= _reasons.length) return;
        _b.simState['reasonsUsed'] = used + 1;
        _later(10, () {
          final now = DateTime.now();
          _b.writeCapsule(
            id,
            partnerUid,
            Capsule(
              id: '',
              kind: CapsuleKind.reason,
              authorId: partnerUid,
              forUid: '',
              createdAt: now,
              unlockAt: Capsule.nextReasonUnlock(_partnerCapsules(id), now),
            ),
            CapsuleContent(text: _reasons[used]),
          );
        });
      case CapsuleKind.letter:
        break;
    }
  }

  void onCapsuleOpened(Capsule c) {
    final id = _pairId;
    if (id == null || !_partnerInPair) return;
    if (c.kind == CapsuleKind.letter) _later(8, () => _b.writeTap(id, partnerUid, 'love'));
  }

  /// A date in the calendar, a shared to-do list and a few wishes.
  void _seedPlan(String pairId) {
    if (!_partnerInPair || _b.simState['seededPlan'] == true) return;
    _b.simState['seededPlan'] = true;
    final me = _b.currentUid;
    final now = DateTime.now();
    final inFive = DateTime(now.year, now.month, now.day + 5, 19, 30);
    _b.putEvent(
      pairId,
      partnerUid,
      Countdown(
        id: '',
        title: 'Movie night',
        date: inFive,
        hasTime: true,
        emoji: '🎬',
        category: EventCategory.date,
        isVirtual: true,
        showAsCountdown: false,
        remindMinutesBefore: 60,
        createdBy: partnerUid,
      ),
    );
    final list = _b.putTodoList(
      pairId,
      partnerUid,
      const TodoList(id: '', title: 'This weekend', emoji: '🧺', createdBy: partnerUid),
    );
    _b
      ..putTodo(
        pairId,
        partnerUid,
        Todo(
          id: '',
          listId: list,
          text: 'Book the restaurant for Saturday',
          assignee: me,
          due: now.add(const Duration(days: 2)),
          createdBy: partnerUid,
        ),
      )
      ..putTodo(
        pairId,
        partnerUid,
        Todo(id: '', listId: list, text: 'Pick a movie for movie night', createdBy: partnerUid),
      )
      ..putTodo(
        pairId,
        partnerUid,
        Todo(id: '', listId: list, text: 'Buy snacks 🍿', assignee: partnerUid, createdBy: partnerUid),
      )
      ..putWish(
        pairId,
        partnerUid,
        const Wish(
          id: '',
          title: 'Fluffy winter socks',
          category: WishCategory.gift,
          note: 'The really soft ones 🧦',
          price: '€12',
          createdBy: partnerUid,
        ),
      )
      ..putWish(
        pairId,
        partnerUid,
        const Wish(id: '', title: 'Sunset picnic by the lake', category: WishCategory.date, createdBy: partnerUid),
      )
      ..putWish(
        pairId,
        partnerUid,
        const Wish(
          id: '',
          title: 'Weekend in Lisbon',
          category: WishCategory.travel,
          note: 'Pastéis de nata tour!',
          createdBy: partnerUid,
        ),
      );
  }

  void onMyEvent(Countdown c) {
    final id = _pairId;
    if (id == null || !_partnerInPair) return;
    if (c.isDate) _later(6, () => _b.writeTap(id, partnerUid, 'love'));
  }

  void onMyTodo(Todo t) {
    final id = _pairId;
    if (id == null || !_partnerInPair || t.assignee != partnerUid) return;
    // They get to it after a while.
    _later(20, () => _b.markTodo(id, partnerUid, t.id, done: true));
  }

  /// Types for a moment, then answers (and sometimes reacts first).
  void onMyMessage(ChatMessage m) {
    final id = _pairId;
    if (id == null || !_partnerInPair) return;
    _later(2, () => _b.markChatReadFor(id, partnerUid));
    // "After viewing" messages go once they've read it and closed the chat.
    if (m.ttl == ChatTtl.viewed) _later(15, () => _b.clearViewedFor(id, partnerUid));
    if (m.isEvent) return;
    if (m.isSnap) {
      // They open it (each allowed time), and sometimes screenshot it.
      for (var i = 0; i < m.viewLimit; i++) {
        _later(3 + i * 6, () => _b.openSnapFor(id, partnerUid, m.id));
      }
      if (_rand.nextDouble() < 0.4) {
        _later(
          5,
          () => _b.writeMessage(
            id,
            partnerUid,
            ChatDraft(
              type: MessageType.event,
              event: ChatEvent.screenshot,
              replyTo: ReplyRef(id: m.id, senderId: m.senderId, preview: m.preview),
            ),
          ),
        );
      }
    } else if (m.type == MessageType.photo || _rand.nextDouble() < 0.3) {
      _later(3, () => _b.setMessageReaction(id, partnerUid, m.id, _pick(const ['❤️', '😍', '😂', '🥹'])));
    }
    // Answer a burst of messages once, not each one.
    final last = _b.simState['lastChatReply'] as int? ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - last < const Duration(seconds: 8).inMilliseconds) return;
    _b.simState['lastChatReply'] = now;
    _later(4, () => _b.setTypingFor(id, partnerUid, typing: true));
    _later(8, () {
      final text = switch (m.type) {
        MessageType.photo => _pick(const ['Omg this is so cute 😍', 'Where is this?? 👀', 'Saving this one 📌']),
        MessageType.voice => _pick(const ['I love hearing your voice 🥹', 'Haha, play it again 😂', 'Aww, miss you']),
        MessageType.snap => _pick(const ['Snap back incoming 👻', 'Hahaha that face 😂', 'Cutie 🥹']),
        MessageType.text || MessageType.event => _pick(_chatReplies),
      };
      _b.writeMessage(
        id,
        partnerUid,
        ChatDraft(
          text: text,
          replyTo: _rand.nextDouble() < 0.25 ? ReplyRef(id: m.id, senderId: m.senderId, preview: m.preview) : null,
        ),
      );
    });
  }

  void onMyGoodnight(String pairId) {
    if (!_partnerInPair) return;
    _later(10, () {
      final tonight = _b.readTonight(pairId);
      if (tonight == null || tonight.doneBy(partnerUid)) return;
      _b.writeGoodnight(
        pairId,
        partnerUid,
        GoodnightEntry(
          message: _pick(const [
            'Goodnight, sleep tight 🌙',
            'Sweet dreams! Talk tomorrow 💤',
            'Night night, love you ✨',
          ]),
          moment: _pick(const [
            'Getting your message this morning ☀️',
            'The sunset on my way home 🌇',
            'Laughing at our chat at lunch 😂',
          ]),
          kiss: true,
        ),
      );
    });
  }

  /// Two weeks of moods for the partner, so insights have a trend to show.
  void _seedMoods(String pairId) {
    if (!_partnerInPair || _b.simState['seededMoods'] == true) return;
    _b.simState['seededMoods'] = true;
    const pool = [
      ('😊', 'Happy'),
      ('🥰', 'Loved'),
      ('😌', 'Calm'),
      ('🤯', 'Busy'),
      ('😴', 'Sleepy'),
      ('🥳', 'Excited'),
      ('🫠', 'Tired'),
    ];
    final now = DateTime.now();
    for (var i = 13; i >= 0; i--) {
      final (emoji, label) = pool[_rand.nextInt(pool.length)];
      _b.logMood(
        pairId,
        partnerUid,
        Mood(emoji: emoji, label: label, updatedAt: now),
        dayKey(now.subtract(Duration(days: i))),
      );
    }
  }

  void onPetChanged(String pairId) {
    if (!_partnerInPair) return;
    _later(12, () {
      final pet = _b.pairOf(pairId)?.pet;
      final now = DateTime.now();
      if (pet == null) return;
      if (!pet.fedBy(partnerUid, now)) _b.petCare(pairId, partnerUid, 'feed');
      if (!pet.playedBy(partnerUid, now)) _later(20, () => _b.petCare(pairId, partnerUid, 'play'));
    });
  }

  void onMyReaction(Item item) {
    // Nothing to do: the partner just enjoys it.
  }

  void onMyMissMeter(String pairId) {
    if (!_partnerInPair) return;
    _later(8, () {
      final m = _b.readTodayMissMeter(pairId);
      if (m == null || m.answeredBy.contains(partnerUid) || m.revealed) return;
      _b.answerMissMeter(pairId, partnerUid, 40 + _rand.nextInt(61));
    });
  }

  void onMyMood(Mood mood) {
    final id = _pairId;
    if (id == null || !_partnerInPair) return;
    if (const ['😢', '🤒', '😤', '🫠'].contains(mood.emoji)) {
      _later(6, () => _sendNote(id, 'Sending you the biggest hug 🤗'));
    }
  }

  void onNewQuestion(String pairId, String date) {
    if (!_partnerInPair) return;
    // Partner answers on their own after a while.
    _later(40 + _rand.nextInt(40), () => _answer(pairId));
  }

  void onMyAnswer(String pairId) {
    if (!_partnerInPair) return;
    _later(6, () => _answer(pairId));
  }

  void _answer(String pairId) {
    final today = dayKey(DateTime.now());
    final q = _b.pairOf(pairId) == null ? null : _b.readTodayQuestion(pairId);
    if (q == null || q.answeredBy.contains(partnerUid) || q.date != today) return;
    _b.answerQuestion(pairId, partnerUid, _pick(_answers));
  }

  void onMyGameMove(String pairId, String gameId) {
    if (!_partnerInPair) return;
    _later(7, () {
      final g = _b.readGame(pairId, gameId);
      if (g == null || g.status != GameStatus.guesserTurn || g.guesserUid != partnerUid) return;
      // Guess right ~60% of the time.
      final guesses = [
        for (var i = 0; i < g.questions.length; i++)
          _rand.nextDouble() < 0.6 ? g.subjectAnswers[i] : _rand.nextInt(g.questions[i].options.length),
      ];
      _b.applyGameAnswers(pairId, gameId, partnerUid, guesses);
    });
  }

  Future<Item?> _sendNote(String pairId, String text, {bool secret = false}) async {
    if (!_partnerInPair) return null;
    final style = NoteStyle(bg: noteBackgrounds[_rand.nextInt(noteBackgrounds.length)].id, font: 'rounded');
    final path = '${_b.mediaDir.path}/sim_${DateTime.now().millisecondsSinceEpoch}.png';
    await NoteRenderer.renderToFile(text: text, style: style, path: path);
    return await _b.storeItem(
      pairId: pairId,
      senderId: partnerUid,
      type: ItemType.note,
      sourcePath: path,
      text: text,
      noteStyle: style,
      secret: secret,
    );
  }

  T _pick<T>(List<T> list) => list[_rand.nextInt(list.length)];

  void dispose() => onUnpaired();

  static const _hello = [
    'Hi you 👋 Found you on my home screen!',
    'We’re connected! 💕',
    'Look at us, all paired up ✨',
  ];

  static const _replies = [
    'This made my day 🥹',
    'Miss you already 💕',
    'Haha I love this 😂',
    'Can’t wait to see you!',
    'You’re the best ✨',
    'Saving this forever 📌',
    'Ok this is adorable',
  ];

  static const _chatReplies = [
    'Haha yes 😂',
    'Aww 🥹',
    'Tell me more!',
    'Same here, honestly',
    'Miss you 💕',
    'Wait, really?? 👀',
    'Love that',
    'Can’t wait to see you!',
  ];

  static const _reasons = [
    'The way you text me good morning, every single day.',
    'You remember the tiny things I say.',
    'Your laugh is contagious.',
    'You make me feel safe.',
    'You always know how to cheer me up.',
    'You’re ridiculously good at hugs.',
    'You believe in me, even when I don’t.',
    'You make boring errands fun.',
    'You’re kind to everyone, even strangers.',
    'Your terrible puns. Yes, really.',
  ];

  static const _answers = [
    'Honestly? Just being with you, doing nothing special.',
    'Pizza on the balcony and our playlist on repeat.',
    'Somewhere warm with a really good view 🌅',
    'I’ve been thinking about that a lot lately… let’s talk tonight!',
    'Coffee. Always coffee ☕',
    'That time we got completely lost and it turned out great.',
  ];
}
