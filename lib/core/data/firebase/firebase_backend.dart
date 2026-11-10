// FirebaseBackend: CloserBackend on Firestore / Storage / Functions / FCM.
//
// Server contract: functions/src/*.ts (callables in europe-west1) and
// firestore.rules. Anything with a limit, reward or secret is decided by a
// callable; the app writes only its own profile, countdowns and a few pair
// settings (widgetTheme[self], questionPack, timezone).

import 'dart:async';
import 'dart:io';

import 'package:closer_app/core/config.dart';
import 'package:closer_app/core/data/closer_backend.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Limits the app maps to [LimitReachedException] (shows the paywall).
const _paywallLimits = {'sends', 'countdowns', 'plus', 'packs'};

class FirebaseBackend implements CloserBackend {
  // Classic constructor syntax, kept for readability.
  // ignore: unnecessary_type_name_in_constructor
  FirebaseBackend({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseFunctions? functions,
  })  : _authOverride = auth,
        _dbOverride = firestore,
        _storageOverride = storage,
        _functionsOverride = functions;

  static const region = 'europe-west1';

  final FirebaseAuth? _authOverride;
  final FirebaseFirestore? _dbOverride;
  final FirebaseStorage? _storageOverride;
  final FirebaseFunctions? _functionsOverride;

  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;
  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;
  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;
  FirebaseFunctions get _functions =>
      _functionsOverride ?? FirebaseFunctions.instanceFor(region: region);

  Future<void>? _googleInit;
  // Lives as long as the backend (app lifetime).
  // ignore: cancel_subscriptions
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  StreamSubscription<String>? _tokenSub;

  /// Cached current pair id (from the signed-in user's doc).
  String? _pairId;

  /// Date key of the latest daily question seen by [watchTodayQuestion].
  String? _latestQuestionDate;
  String? _fcmToken;
  final Map<String, Future<String?>> _urlCache = {};

  @override
  String get name => 'firebase';

  @override
  bool get isSimulated => false;

  // ------------------------------------------------------------------ init

  @override
  Future<void> init() async {
    if (Firebase.apps.isEmpty) {
      // TODO(setup): main() should call Firebase.initializeApp(options:
      // DefaultFirebaseOptions.currentPlatform) from `flutterfire configure`.
      await Firebase.initializeApp();
    }
    _authSub ??= _auth.authStateChanges().listen(_onAuthChanged);
  }

  void _onAuthChanged(User? user) {
    unawaited(_userSub?.cancel());
    _userSub = null;
    _pairId = null;
    if (user == null) return;
    _userSub = _db.doc('users/${user.uid}').snapshots().listen(
      (snap) => _pairId = snap.data()?['pairId'] as String?,
      onError: (Object e) => debugPrint('FirebaseBackend user stream: $e'),
    );
  }

  Future<void> _ensureGoogle() =>
      _googleInit ??= GoogleSignIn.instance.initialize();

  // ------------------------------------------------------------------ auth

  @override
  Stream<String?> authState() => _auth.authStateChanges().map((u) => u?.uid);

  @override
  String? get currentUid => _auth.currentUser?.uid;

  String get _uid {
    final uid = currentUid;
    if (uid == null) throw const CloserException('Please sign in first.');
    return uid;
  }

  @override
  Future<void> signInWithGoogle() async {
    await _ensureGoogle();
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const CloserException('Sign-in was cancelled.');
      }
      throw CloserException('Google sign-in failed (${e.code.name}).');
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const CloserException('Google sign-in returned no ID token.');
    }
    final cred = await _auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );
    final user = cred.user;
    if (user == null) throw const CloserException('Sign-in failed.');
    await _ensureUserDoc(user, account);
  }

  Future<void> _ensureUserDoc(User user, GoogleSignInAccount account) async {
    final ref = _db.doc('users/${user.uid}');
    final snap = await ref.get();
    if (snap.exists) {
      await ref.update({'timezone': _timezoneGuess()});
      return;
    }
    await ref.set({
      'displayName': _clip(user.displayName ?? account.displayName ?? '', 40),
      'photoUrl': user.photoURL ?? account.photoUrl,
      'pairId': null,
      'ageConfirmed18': false,
      'notificationPrefs': const NotificationPrefs().toJson(),
      'locale': PlatformDispatcher.instance.locale.languageCode,
      'timezone': _timezoneGuess(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> signOut() async {
    final token = _fcmToken;
    if (token != null) {
      try {
        await _call('registerFcmToken', {'token': token, 'remove': true});
      } on Object catch (_) {}
    }
    await _tokenSub?.cancel();
    _tokenSub = null;
    _fcmToken = null;
    _urlCache.clear();
    try {
      await _ensureGoogle();
      await GoogleSignIn.instance.signOut();
    } on Object catch (_) {}
    await _auth.signOut();
  }

  // ----------------------------------------------------------------- users

  @override
  Stream<AppUser?> watchUser(String uid) => _db
      .doc('users/$uid')
      .snapshots()
      .map((s) => s.exists ? AppUser.fromJson(uid, s.data()!) : null)
      .transform(_nullOnPermissionDenied());

  @override
  Future<void> updateProfile({String? displayName, String? photoFilePath}) async {
    final uid = _uid;
    final update = <String, Object?>{'updatedAt': FieldValue.serverTimestamp()};
    if (displayName != null) update['displayName'] = _clip(displayName.trim(), 40);
    if (photoFilePath != null) {
      final ref = _storage.ref('users/$uid/avatar.jpg');
      await ref.putFile(
        File(photoFilePath),
        SettableMetadata(contentType: _contentType(photoFilePath)),
      );
      update['photoUrl'] = await ref.getDownloadURL();
    }
    await _db.doc('users/$uid').set(update, SetOptions(merge: true));
  }

  @override
  Future<void> setPendingMode(PairMode mode, {String? label}) => _updateMe({
        'pendingMode': mode.name,
        'pendingLabel': RelationLabel.validFor(label, mode),
      });

  @override
  Future<void> updateMood(Mood mood) => _updateMe({
        'mood': {
          'emoji': mood.emoji,
          'label': _clip(mood.label, 40),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      });

  @override
  Future<void> updateStatus(StatusText status) => _updateMe({
        'status': {
          'text': _clip(status.text, 80),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      });

  @override
  Future<void> setAgeConfirmed({required bool confirmed}) =>
      _updateMe({'ageConfirmed18': confirmed});

  @override
  Future<void> updateNotificationPrefs(NotificationPrefs prefs) =>
      _updateMe({'notificationPrefs': prefs.toJson()});

  Future<void> _updateMe(Map<String, Object?> data) =>
      _db.doc('users/$_uid').set(data, SetOptions(merge: true));

  // --------------------------------------------------------------- pairing

  @override
  Future<Invite> createInvite(PairMode mode) async {
    final data = await _call('createInvite', {'mode': mode.name});
    return Invite.fromJson(data['code'] as String, data);
  }

  @override
  Future<void> acceptInvite(String code) async {
    final data = await _call('acceptInvite', {'code': code});
    _pairId = data['pairId'] as String? ?? _pairId;
  }

  @override
  Future<void> unpair() async {
    await _call('unpair', {});
    _pairId = null;
  }

  @override
  Future<void> deleteAccount() async {
    await _call('deleteAccount', {});
    _pairId = null;
    // The Auth user is deleted server-side; clear local session state.
    await signOut();
  }

  @override
  Future<String> exportMemories() async {
    final data = await _call('exportMemories', {});
    return data['url'] as String;
  }

  @override
  Stream<Pair?> watchPair(String pairId) => _db
      .doc('pairs/$pairId')
      .snapshots()
      .map((s) => s.exists ? Pair.fromJson(s.id, s.data()!) : null)
      .transform(_nullOnPermissionDenied());

  /// Members may edit these pair fields directly (see firestore.rules):
  /// `mode`, `anniversary`, and their own entry in `relationLabels` /
  /// `nicknames`.
  @override
  Future<void> updateRelationship({
    PairMode? mode,
    DateTime? anniversary,
    bool clearAnniversary = false,
    String? label,
    String? nickname,
  }) async {
    final pairId = await _requirePairId();
    final ref = _db.doc('pairs/$pairId');
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final pair = Pair.fromJson(snap.id, snap.data() ?? {});
      final newMode = mode ?? pair.mode;
      final update = <String, Object?>{};
      if (mode != null && mode != pair.mode) {
        update['mode'] = mode.name;
        for (final e in pair.relationLabels.entries) {
          if (RelationLabel.validFor(e.value, newMode) == null) {
            update['relationLabels.${e.key}'] = FieldValue.delete();
          }
        }
      }
      if (label != null) {
        final valid = RelationLabel.validFor(label, newMode);
        if (valid == null) {
          throw const CloserException('That label doesn’t match your relationship type');
        }
        update['relationLabels.$_uid'] = valid;
      }
      if (nickname != null) {
        final n = nickname.trim();
        update['nicknames.$_uid'] =
            n.isEmpty ? FieldValue.delete() : (n.length > 24 ? n.substring(0, 24) : n);
      }
      if (clearAnniversary) {
        update['anniversary'] = FieldValue.delete();
      } else if (anniversary != null) {
        if (anniversary.isAfter(DateTime.now())) {
          throw const CloserException('Pick a date in the past');
        }
        update['anniversary'] = Timestamp.fromDate(
          DateTime(anniversary.year, anniversary.month, anniversary.day),
        );
      }
      if (update.isNotEmpty) tx.update(ref, update);
    });
  }

  // ----------------------------------------------------------------- items

  @override
  Future<Item> sendItem(SendRequest request) async {
    final pairId = await _requirePairId();
    final itemId = _db.collection('pairs/$pairId/items').doc().id;
    final ref = _storage.ref('pairs/$pairId/raw/$itemId.jpg');
    try {
      await ref.putFile(
        File(request.imagePath),
        SettableMetadata(contentType: _contentType(request.imagePath)),
      );
    } on FirebaseException catch (e) {
      throw CloserException('Upload failed (${e.code}). Check your connection.');
    }
    final data = await _call('sendItem', {
      'pairId': pairId,
      'itemId': itemId,
      'type': request.type.name,
      'caption': _clip(request.caption, Item.maxCaption),
      'text': request.text,
      'noteStyle': request.noteStyle?.toJson(),
      'geo': request.geo?.toJson(),
      'saveToMemories': request.saveToMemories,
    });
    return Item.fromJson(data['id'] as String? ?? itemId, data);
  }

  @override
  Stream<List<Item>> watchItems(String pairId, {int limit = 200}) => _db
      .collection('pairs/$pairId/items')
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((q) => q.docs.map((d) => Item.fromJson(d.id, d.data())).toList());

  /// Reads the caller's latest usage doc (`usage/{uid}_{date}`); it carries
  /// `expiresAt` = next local midnight in the pair's timezone, so the app
  /// never has to compute the server's day boundary.
  @override
  Stream<int> watchSendsToday() {
    final uid = currentUid;
    if (uid == null) return Stream.value(0);
    return _db
        .collection('usage')
        .where('uid', isEqualTo: uid)
        .orderBy('expiresAt', descending: true)
        .limit(1)
        .snapshots()
        .map((q) {
      if (q.docs.isEmpty) return 0;
      final d = q.docs.first.data();
      final expires = d['expiresAt'];
      if (expires is Timestamp && expires.toDate().isBefore(DateTime.now())) {
        return 0;
      }
      return (d['sends'] as num?)?.toInt() ?? 0;
    });
  }

  @override
  Future<void> grantRewardedSends() async {
    await _call('grantRewardedSends', {});
  }

  @override
  Future<String?> resolveImage(String? ref) {
    if (ref == null || ref.isEmpty) return Future.value();
    if (ref.startsWith('http://') || ref.startsWith('https://')) {
      return Future.value(ref);
    }
    if (File(ref).isAbsolute && File(ref).existsSync()) return Future.value(ref);
    return _urlCache.putIfAbsent(ref, () async {
      try {
        return await _storage.ref(ref).getDownloadURL();
      } on Object catch (e) {
        debugPrint('resolveImage($ref) failed: $e');
        unawaited(Future<void>(() => _urlCache.remove(ref)));
        return null;
      }
    });
  }

  // ------------------------------------------------------------------ taps

  @override
  Future<void> sendTap({String kind = 'heart'}) async {
    await _call('sendTap', {'kind': kind});
  }

  @override
  Stream<Tap?> watchLatestTap(String pairId) => _db
      .collection('pairs/$pairId/taps')
      .orderBy('createdAt', descending: true)
      .limit(1)
      .snapshots()
      .map(
        (q) => q.docs.isEmpty
            ? null
            : Tap.fromJson(q.docs.first.id, q.docs.first.data()),
      );

  // -------------------------------------------------------- daily question

  /// The latest assigned question (the server assigns at 07:00 pair-local
  /// time), merged with the caller's private answer.
  @override
  Stream<DailyQuestion?> watchTodayQuestion(String pairId) {
    late StreamController<DailyQuestion?> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? qSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? aSub;
    DailyQuestion? question;
    String? myAnswer;
    String? privateFor;

    void emit() {
      if (controller.isClosed) return;
      controller.add(question?.withMyAnswer(myAnswer));
    }

    controller = StreamController<DailyQuestion?>(
      onListen: () {
        qSub = _db
            .collection('pairs/$pairId/dailyQuestions')
            .orderBy('assignedAt', descending: true)
            .limit(1)
            .snapshots()
            .listen(
          (q) {
            if (q.docs.isEmpty) {
              question = null;
              emit();
              return;
            }
            final doc = q.docs.first;
            question = DailyQuestion.fromJson(doc.id, doc.data());
            _latestQuestionDate = doc.id;
            final uid = currentUid;
            if (uid != null && privateFor != doc.id) {
              privateFor = doc.id;
              myAnswer = null;
              unawaited(aSub?.cancel());
              aSub = doc.reference.collection('private').doc(uid).snapshots().listen(
                (a) {
                  myAnswer = a.data()?['answer'] as String?;
                  emit();
                },
                onError: (Object e) => debugPrint('private answer: $e'),
              );
            }
            emit();
          },
          onError: (Object e, StackTrace st) {
            if (_isPermissionDenied(e)) {
              question = null;
              emit();
            } else {
              controller.addError(e, st);
            }
          },
        );
      },
      onCancel: () async {
        await qSub?.cancel();
        await aSub?.cancel();
      },
    );
    return controller.stream;
  }

  /// Revealed questions, newest first (includes today's once revealed).
  @override
  Stream<List<DailyQuestion>> watchPastQuestions(String pairId) => _db
      .collection('pairs/$pairId/dailyQuestions')
      .orderBy('assignedAt', descending: true)
      .limit(120)
      .snapshots()
      .map(
        (q) => q.docs
            .map((d) => DailyQuestion.fromJson(d.id, d.data()))
            .where((d) => d.revealed)
            .toList(),
      );

  @override
  Future<void> submitAnswer(String text) async {
    await _call('submitAnswer', {
      'answer': text,
      if (_latestQuestionDate != null) 'date': _latestQuestionDate,
    });
  }

  @override
  Future<void> setQuestionPack(String packId) async {
    final pairId = await _requirePairId();
    await _db.doc('pairs/$pairId').update({'questionPack': packId});
  }

  // ------------------------------------------------------------ countdowns

  @override
  Stream<List<Countdown>> watchCountdowns(String pairId) => _db
      .collection('pairs/$pairId/countdowns')
      .orderBy('date')
      .snapshots()
      .map(
        (q) => q.docs.map((d) => Countdown.fromJson(d.id, d.data())).toList(),
      );

  /// The free limit is enforced here (Firestore rules can't count docs).
  @override
  Future<void> saveCountdown(Countdown countdown) async {
    final pairId = await _requirePairId();
    final col = _db.collection('pairs/$pairId/countdowns');
    final isNew = countdown.id.isEmpty || !(await col.doc(countdown.id).get()).exists;
    if (isNew && AppConfig.monetizationEnabled) {
      final pair = await _db.doc('pairs/$pairId').get();
      final premium = Pair.fromJson(pair.id, pair.data() ?? {}).premium.active;
      if (!premium) {
        final count = (await col.count().get()).count ?? 0;
        if (count >= FreeLimits.countdowns) {
          throw const LimitReachedException('countdowns');
        }
      }
    }
    final ref = countdown.id.isEmpty ? col.doc() : col.doc(countdown.id);
    final d = countdown.date;
    final day = DateTime(d.year, d.month, d.day);
    final moment = countdown.hasTime ? DateTime(d.year, d.month, d.day, d.hour, d.minute) : day;
    final remindAt = countdown.hasTime ? countdown.nextReminderAt(DateTime.now()) : null;
    await ref.set({
      'title': _clip(countdown.title, 60),
      'date': Timestamp.fromDate(moment),
      'dateKey': '${day.year.toString().padLeft(4, '0')}-'
          '${day.month.toString().padLeft(2, '0')}-'
          '${day.day.toString().padLeft(2, '0')}',
      'emoji': countdown.emoji,
      'repeatsYearly': countdown.repeatsYearly,
      'hasTime': countdown.hasTime,
      'remindMinutesBefore': countdown.remindMinutesBefore.clamp(0, Countdown.maxRemindMinutes),
      'remindDaysBefore': countdown.remindDaysBefore.clamp(0, 60),
      // The minute-level reminder job picks docs up by this instant.
      if (remindAt != null) 'nextRemindAt': Timestamp.fromDate(remindAt),
      'createdBy': countdown.createdBy.isEmpty ? _uid : countdown.createdBy,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> deleteCountdown(String id) async {
    final pairId = await _requirePairId();
    await _db.doc('pairs/$pairId/countdowns/$id').delete();
  }

  // ----------------------------------------------------------------- games

  @override
  Stream<List<Game>> watchGames(String pairId) => _db
      .collection('pairs/$pairId/games')
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((q) => q.docs.map((d) => Game.fromJson(d.id, d.data())).toList());

  @override
  Future<Game> startGame({String packId = 'starter'}) async {
    final data = await _call('startGame', {'packId': packId});
    return Game.fromJson(data['id'] as String, data);
  }

  @override
  Future<void> submitGameAnswers(String gameId, List<int> answers) async {
    await _call('submitGameAnswers', {'gameId': gameId, 'answers': answers});
  }

  // ------------------------------------------------------ themes & premium

  @override
  Future<void> setWidgetTheme(String themeId) async {
    final pairId = await _requirePairId();
    try {
      await _db.doc('pairs/$pairId').update({'widgetTheme.$_uid': themeId});
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const LimitReachedException('plus', 'This theme is part of Closer Plus.');
      }
      rethrow;
    }
  }

  @override
  Future<void> debugSetPremium({required bool active}) {
    throw UnsupportedError(
      'Premium is set by the RevenueCat webhook on the Firebase backend.',
    );
  }

  // ------------------------------------------------------------------- FCM

  @override
  Future<void> registerDevice() async {
    if (currentUid == null) return;
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    // Classic registration tokens: the functions send with sendEachForMulticast.
    // ignore: deprecated_member_use
    final token = await messaging.getToken();
    if (token != null) await _registerToken(token);
    // Token refresh for the same classic-token flow as above.
    // ignore: deprecated_member_use
    _tokenSub ??= messaging.onTokenRefresh.listen(
      (t) => unawaited(_registerToken(t).catchError((Object e) {
        debugPrint('registerFcmToken failed: $e');
      })),
    );
  }

  Future<void> _registerToken(String token) async {
    if (currentUid == null) return;
    _fcmToken = token;
    await _call('registerFcmToken', {'token': token});
  }

  // --------------------------------------------------------------- helpers

  Future<String> _requirePairId() async {
    final cached = _pairId;
    if (cached != null) return cached;
    final snap = await _db.doc('users/$_uid').get();
    final pairId = snap.data()?['pairId'] as String?;
    if (pairId == null) {
      throw const CloserException("You're not connected to anyone yet.");
    }
    return _pairId = pairId;
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, Object?> data,
  ) async {
    try {
      final result = await _functions.httpsCallable(name).call<Object?>(data);
      final value = _deep(result.data);
      return value is Map<String, dynamic> ? value : <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      throw _mapError(e);
    }
  }

  Exception _mapError(FirebaseFunctionsException e) {
    final details = _deep(e.details);
    final map = details is Map<String, dynamic> ? details : const <String, dynamic>{};
    final message = e.message ?? 'Something went wrong.';
    final limit = map['limit'] as String?;
    if (e.code == 'resource-exhausted' && limit != null) {
      return _paywallLimits.contains(limit)
          ? LimitReachedException(limit, message)
          : CloserException(message);
    }
    switch (e.code) {
      case 'unavailable':
      case 'deadline-exceeded':
        return const CloserException('No connection. Please try again.');
      case 'unauthenticated':
        return const CloserException('Please sign in again.');
      case 'internal':
        return const CloserException('Something went wrong. Please try again.');
      default:
        return CloserException(message);
    }
  }

  static Object? _deep(Object? v) {
    if (v is Map) {
      return v.map<String, dynamic>((k, x) => MapEntry('$k', _deep(x)));
    }
    if (v is List) return v.map(_deep).toList();
    return v;
  }

  static bool _isPermissionDenied(Object e) =>
      e is FirebaseException && e.code == 'permission-denied';

  /// After unpairing (or before a doc exists) listeners can be denied; turn
  /// that into `null` instead of an error.
  static StreamTransformer<T?, T?> _nullOnPermissionDenied<T>() =>
      StreamTransformer<T?, T?>.fromHandlers(
        handleError: (e, st, sink) {
          if (_isPermissionDenied(e)) {
            sink.add(null);
          } else {
            sink.addError(e, st);
          }
        },
      );

  static String _clip(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);

  static String _contentType(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  /// Best-effort IANA zone from the UTC offset (Dart has no IANA name API).
  /// Whole-hour offsets map to Etc/GMT±N (note the inverted sign); DST is
  /// not tracked. TODO: use the flutter_timezone package for real zones.
  static String _timezoneGuess() {
    final offset = DateTime.now().timeZoneOffset;
    if (offset.inMinutes % 60 != 0) return 'UTC';
    final h = offset.inHours;
    if (h == 0) return 'UTC';
    return h > 0 ? 'Etc/GMT-$h' : 'Etc/GMT+${-h}';
  }
}
