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

  Duration _s(num seconds) =>
      Duration(milliseconds: (_scale.inMilliseconds * seconds).round());

  void _later(num seconds, void Function() fn) {
    _timers.add(Timer(_s(seconds), () {
      try {
        fn();
      } on Object {
        // The simulated partner must never crash the app.
      }
    }));
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
    // Reply with a note now and then, not to every single item.
    final last = _b.simState['lastReply'] as int? ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - last > const Duration(seconds: 90).inMilliseconds) {
      _b.simState['lastReply'] = now;
      _later(10, () => _sendNote(id, _pick(_replies)));
    }
  }

  void onMyTap() {
    final id = _pairId;
    if (id == null || !_partnerInPair) return;
    _later(5, () => _b.writeTap(id, partnerUid, 'heart'));
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

  Future<void> _sendNote(String pairId, String text) async {
    if (!_partnerInPair) return;
    final style = NoteStyle(
      bg: noteBackgrounds[_rand.nextInt(noteBackgrounds.length)].id,
      font: 'rounded',
    );
    final path = '${_b.mediaDir.path}/sim_${DateTime.now().millisecondsSinceEpoch}.png';
    await NoteRenderer.renderToFile(text: text, style: style, path: path);
    await _b.storeItem(
      pairId: pairId,
      senderId: partnerUid,
      type: ItemType.note,
      sourcePath: path,
      text: text,
      noteStyle: style,
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

  static const _answers = [
    'Honestly? Just being with you, doing nothing special.',
    'Pizza on the balcony and our playlist on repeat.',
    'Somewhere warm with a really good view 🌅',
    'I’ve been thinking about that a lot lately… let’s talk tonight!',
    'Coffee. Always coffee ☕',
    'That time we got completely lost and it turned out great.',
  ];
}


