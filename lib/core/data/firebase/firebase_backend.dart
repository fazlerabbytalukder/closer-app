// FirebaseBackend: CloserBackend on Firestore / Storage / Functions / FCM.
//
// Server contract: functions/src/*.ts (callables in europe-west1) and
// firestore.rules. Anything with a limit, reward or secret is decided by a
// callable; the app writes only its own profile, countdowns and a few pair
// settings (widgetTheme[self], questionPack, timezone).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:closer_app/core/config.dart';
import 'package:closer_app/core/data/closer_backend.dart';
import 'package:closer_app/core/data/firebase/firebase_setup.dart';
import 'package:closer_app/core/data/firebase/send_queue.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/device_timezone.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Limits the app maps to [LimitReachedException] (shows the paywall).
const _paywallLimits = {'sends', 'countdowns', 'plus', 'packs'};

class FirebaseBackend implements CloserBackend {
  // Classic constructor syntax, kept for readability.
  FirebaseBackend({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseFunctions? functions,
  }) : _authOverride = auth,
       _dbOverride = firestore,
       _storageOverride = storage,
       _functionsOverride = functions;

  static const region = firebaseRegion;

  final FirebaseAuth? _authOverride;
  final FirebaseFirestore? _dbOverride;
  final FirebaseStorage? _storageOverride;
  final FirebaseFunctions? _functionsOverride;

  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;
  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;
  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;
  FirebaseFunctions get _functions => _functionsOverride ?? FirebaseFunctions.instanceFor(region: region);

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

  /// Capsule content never changes once written.
  final Map<String, CapsuleContent> _capsuleCache = {};

  /// Sends made offline, delivered by [_flushQueue].
  final SendQueue _queue = SendQueue();
  Future<void>? _flushing;
  Timer? _retryTimer;
  // Live as long as the backend (app lifetime).
  // ignore: cancel_subscriptions
  StreamSubscription<List<ConnectivityResult>>? _netSub;
  AppLifecycleListener? _lifecycle;

  @override
  String get name => 'firebase';

  @override
  bool get isSimulated => false;

  // ------------------------------------------------------------------ init

  @override
  Future<void> init() async {
    await initCloserFirebase();
    // Fail a stalled upload in 30 s (default 10 min) so it can be queued.
    _storage.setMaxUploadRetryTime(const Duration(seconds: 30));
    _authSub ??= _auth.authStateChanges().listen(_onAuthChanged);
    // Offline queue: retry when the network comes back or the app returns.
    _netSub ??= Connectivity().onConnectivityChanged.listen((r) {
      if (_isOnline(r)) unawaited(_flushQueue());
    });
    _lifecycle ??= AppLifecycleListener(onResume: () => unawaited(_flushQueue()));
  }

  void _onAuthChanged(User? user) {
    unawaited(_userSub?.cancel());
    _userSub = null;
    _pairId = null;
    if (user == null) return;
    _userSub = _db
        .doc('users/${user.uid}')
        .snapshots()
        .listen(
          (snap) {
            final first = _pairId == null;
            _pairId = snap.data()?['pairId'] as String?;
            // Sends queued in an earlier session go out once we know the pair.
            if (first && _pairId != null) unawaited(_flushQueue());
          },
          onError: (Object e) => debugPrint('FirebaseBackend user stream: $e'),
        );
  }

  Future<void> _ensureGoogle() => _googleInit ??= GoogleSignIn.instance.initialize();

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
    if (useFirebaseEmulator) {
      await _signInOnEmulator();
      return;
    }
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
    final cred = await _auth.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
    final user = cred.user;
    if (user == null) throw const CloserException('Sign-in failed.');
    await _ensureUserDoc(user, displayName: account.displayName, photoUrl: account.photoUrl);
  }

  /// Emulator only: real Google sign-in needs a real Firebase project, so
  /// sign in with a fake Google account the Auth emulator accepts. Each
  /// install keeps its own account, so two phones are two different people.
  Future<void> _signInOnEmulator() async {
    const key = 'emulator_tester_id';
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(key);
    if (id == null) {
      final rnd = Random.secure();
      id = List.generate(6, (_) => rnd.nextInt(36).toRadixString(36)).join();
      await prefs.setString(key, id);
    }
    final name = 'Tester ${id.substring(0, 4).toUpperCase()}';
    // The Auth emulator accepts an unsigned JSON "ID token".
    final fakeIdToken = jsonEncode({
      'sub': 'tester-$id',
      'email': 'tester-$id@example.com',
      'email_verified': true,
      'name': name,
    });
    final cred = await _auth.signInWithCredential(GoogleAuthProvider.credential(idToken: fakeIdToken));
    final user = cred.user;
    if (user == null) throw const CloserException('Sign-in failed.');
    await _ensureUserDoc(user, displayName: name);
  }

  Future<void> _ensureUserDoc(User user, {String? displayName, String? photoUrl}) async {
    final ref = _db.doc('users/${user.uid}');
    final snap = await ref.get();
    final timezone = await deviceTimezone();
    if (snap.exists) {
      await ref.update({'timezone': timezone});
      return;
    }
    await ref.set({
      'displayName': _clip(user.displayName ?? displayName ?? '', 40),
      'photoUrl': user.photoURL ?? photoUrl,
      'pairId': null,
      'ageConfirmed18': false,
      'notificationPrefs': const NotificationPrefs().toJson(),
      'locale': PlatformDispatcher.instance.locale.languageCode,
      'timezone': timezone,
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
    if (!useFirebaseEmulator) {
      try {
        await _ensureGoogle();
        await GoogleSignIn.instance.signOut();
      } on Object catch (_) {}
    }
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
      await ref.putFile(File(photoFilePath), SettableMetadata(contentType: _contentType(photoFilePath)));
      update['photoUrl'] = await ref.getDownloadURL();
    }
    await _db.doc('users/$uid').set(update, SetOptions(merge: true));
  }

  @override
  Future<void> setPendingMode(PairMode mode, {String? label}) =>
      _updateMe({'pendingMode': mode.name, 'pendingLabel': RelationLabel.validFor(label, mode)});

  @override
  Future<void> updateMood(Mood mood) async {
    await _updateMe({
      'mood': {'emoji': mood.emoji, 'label': _clip(mood.label, 40), 'updatedAt': FieldValue.serverTimestamp()},
    });
    // Mood history for insights (best effort; the mood itself is saved).
    final pairId = _pairId;
    if (pairId == null) return;
    final n = DateTime.now();
    final date =
        '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
    try {
      await _db.doc('pairs/$pairId/moods/${_uid}_$date').set({
        'uid': _uid,
        'date': date,
        'emoji': mood.emoji,
        'label': _clip(mood.label, 40),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on Object catch (e) {
      debugPrint('mood log: $e');
    }
  }

  @override
  Future<void> updateStatus(StatusText status) => _updateMe({
    'status': {'text': _clip(status.text, 80), 'updatedAt': FieldValue.serverTimestamp()},
  });

  @override
  Future<void> setAgeConfirmed({required bool confirmed}) => _updateMe({'ageConfirmed18': confirmed});

  @override
  Future<void> updateNotificationPrefs(NotificationPrefs prefs) => _updateMe({'notificationPrefs': prefs.toJson()});

  Future<void> _updateMe(Map<String, Object?> data) => _db.doc('users/$_uid').set(data, SetOptions(merge: true));

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
        update['nicknames.$_uid'] = n.isEmpty ? FieldValue.delete() : (n.length > 24 ? n.substring(0, 24) : n);
      }
      if (clearAnniversary) {
        update['anniversary'] = FieldValue.delete();
      } else if (anniversary != null) {
        if (anniversary.isAfter(DateTime.now())) {
          throw const CloserException('Pick a date in the past');
        }
        update['anniversary'] = Timestamp.fromDate(DateTime(anniversary.year, anniversary.month, anniversary.day));
      }
      if (update.isNotEmpty) tx.update(ref, update);
    });
  }

  /// `lastMetAt` is a member-writable pair field (see firestore.rules).
  @override
  Future<void> setLastMet(DateTime when) async {
    if (when.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      throw const CloserException('Pick a time that already happened');
    }
    final pairId = await _requirePairId();
    final now = DateTime.now();
    await _db.doc('pairs/$pairId').update({
      // Rules require lastMetAt <= request.time; clamp clock skew.
      'lastMetAt': Timestamp.fromDate(when.isAfter(now) ? now : when),
    });
  }

  // ----------------------------------------------------------------- items

  @override
  Future<Item> sendItem(SendRequest request) async {
    final uid = _uid;
    final pairId = await _requirePairId();
    final itemId = _db.collection('pairs/$pairId/items').doc().id;
    Future<Never> queue() async {
      await _queue.add(itemId: itemId, pairId: pairId, uid: uid, request: request);
      _scheduleRetry();
      throw const SendQueuedException();
    }

    if (!await _online()) await queue();
    try {
      return await _deliver(pairId, itemId, request);
    } on Object catch (e) {
      if (await _isNetworkError(e)) await queue();
      if (e is FirebaseException && e.plugin == 'firebase_storage') {
        throw CloserException('Upload failed (${e.code}). Please try again.');
      }
      rethrow;
    }
  }

  /// Uploads the image and creates the item. Safe to repeat with the same
  /// [itemId]: the server returns the existing item.
  Future<Item> _deliver(String pairId, String itemId, SendRequest request) async {
    final ref = _storage.ref('pairs/$pairId/raw/$itemId.jpg');
    await ref.putFile(File(request.imagePath), SettableMetadata(contentType: _contentType(request.imagePath)));
    final data = await _call('sendItem', {
      'pairId': pairId,
      'itemId': itemId,
      'type': request.type.name,
      'caption': _clip(request.caption, Item.maxCaption),
      'text': request.text,
      'noteStyle': request.noteStyle?.toJson(),
      'geo': request.geo?.toJson(),
      'saveToMemories': request.saveToMemories,
      'secret': request.secret,
    });
    return Item.fromJson(data['id'] as String? ?? itemId, data);
  }

  @override
  Stream<int> watchQueuedSends() {
    // Follows the latest signed-in user (asyncExpand would wait forever for
    // the previous user's never-ending count stream).
    StreamSubscription<User?>? auth;
    StreamSubscription<int>? count;
    late final StreamController<int> out;
    out = StreamController<int>(
      onListen: () {
        auth = _auth.authStateChanges().listen((u) {
          unawaited(count?.cancel());
          count = _queue.watchCount(u?.uid).listen(out.add, onError: out.addError);
        }, onError: out.addError);
      },
      onCancel: () async {
        await count?.cancel();
        await auth?.cancel();
      },
    );
    return out.stream;
  }

  /// Sends the queued items in order. Stops at the first network failure (and
  /// tries again later); drops items that fail for good (limit, unpaired).
  Future<void> _flushQueue() {
    // One flush at a time. Cleared after completion (not in a `finally`
    // inside the body: a body that returns before its first await would
    // clear it before it was set, leaving a finished future stuck here).
    final running = _flushing;
    if (running != null) return running;
    final flush = _flushOnce();
    _flushing = flush;
    unawaited(
      flush.whenComplete(() {
        if (identical(_flushing, flush)) _flushing = null;
      }),
    );
    return flush;
  }

  Future<void> _flushOnce() async {
    final uid = currentUid;
    if (uid == null || !await _online()) return;
    for (final e in await _queue.items()) {
      if (e.uid != uid) continue;
      try {
        await _deliver(e.pairId, e.itemId, e.request);
        await _queue.remove(e.itemId);
        debugPrint('Offline queue: sent ${e.itemId}');
      } on Object catch (err) {
        if (await _isNetworkError(err)) {
          debugPrint('Offline queue: still offline ($err), retrying in a minute');
          _scheduleRetry();
          return;
        }
        // Limit reached, unpaired, image rejected: it can't ever go out.
        debugPrint('Offline queue: dropping ${e.itemId}: $err');
        await _queue.remove(e.itemId);
      }
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(minutes: 1), () => unawaited(_flushQueue()));
  }

  static bool _isOnline(List<ConnectivityResult> r) => r.any((c) => c != ConnectivityResult.none);

  Future<bool> _online() async {
    try {
      return _isOnline(await Connectivity().checkConnectivity());
    } on Object catch (_) {
      return true; // can't tell: try the network
    }
  }

  Future<bool> _isNetworkError(Object e) async {
    if (e is NetworkException || e is SocketException || e is TimeoutException) return true;
    if (e is FirebaseException) {
      if (e.code == 'retry-limit-exceeded' || e.code == 'unavailable') return true;
      return !await _online();
    }
    return false;
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
      return Future.value(emulatorStorageUrl(ref));
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

  @override
  Future<void> reactToItem(String itemId, String? emoji) async {
    await _call('reactItem', {'itemId': itemId, 'emoji': emoji});
  }

  @override
  Future<void> revealSecret(String itemId) async {
    await _call('revealAdmirer', {'itemId': itemId});
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
      .map((q) => q.docs.isEmpty ? null : Tap.fromJson(q.docs.first.id, q.docs.first.data()));

  // ------------------------------------------------------------ miss meter

  /// Recent days (doc id = the pair-local date) plus the caller's private
  /// value for each, from `missMeters/{date}/private/{uid}`.
  @override
  Stream<List<MissMeter>> watchMissMeters(String pairId) {
    late StreamController<List<MissMeter>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? listSub;
    final privateSubs = <String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>{};
    final mine = <String, int?>{};
    var days = <MissMeter>[];

    void emit() {
      if (controller.isClosed) return;
      controller.add([for (final d in days) d.withMyValue(mine[d.date])]);
    }

    controller = StreamController<List<MissMeter>>(
      onListen: () {
        listSub = _db
            .collection('pairs/$pairId/missMeters')
            .orderBy('date', descending: true)
            .limit(30)
            .snapshots()
            .listen(
              (q) {
                days = q.docs.map((d) => MissMeter.fromJson(d.id, d.data())).toList();
                final uid = currentUid;
                // Only today's (newest) value can still be hidden from the
                // partner; older days carry both values once revealed.
                if (uid != null && days.isNotEmpty) {
                  final latest = days.first.date;
                  if (!privateSubs.containsKey(latest)) {
                    privateSubs[latest] = _db.doc('pairs/$pairId/missMeters/$latest/private/$uid').snapshots().listen((
                      a,
                    ) {
                      mine[latest] = (a.data()?['value'] as num?)?.toInt();
                      emit();
                    }, onError: (Object e) => debugPrint('miss meter private: $e'));
                  }
                }
                emit();
              },
              onError: (Object e, StackTrace st) {
                if (_isPermissionDenied(e)) {
                  days = [];
                  emit();
                } else {
                  controller.addError(e, st);
                }
              },
            );
      },
      onCancel: () async {
        await listSub?.cancel();
        for (final s in privateSubs.values) {
          await s.cancel();
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<void> submitMissMeter(int value) async {
    final now = DateTime.now();
    await _call('submitMissMeter', {
      'value': value.clamp(0, MissMeter.max),
      // The server accepts the device's local date if it is within a day of
      // the pair's date, so late-night answers land on the day you meant.
      'date':
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}',
    });
  }

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
                  aSub = doc.reference.collection('private').doc(uid).snapshots().listen((a) {
                    myAnswer = a.data()?['answer'] as String?;
                    emit();
                  }, onError: (Object e) => debugPrint('private answer: $e'));
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
      .map((q) => q.docs.map((d) => DailyQuestion.fromJson(d.id, d.data())).where((d) => d.revealed).toList());

  @override
  Future<void> submitAnswer(String text) async {
    await _call('submitAnswer', {'answer': text, if (_latestQuestionDate != null) 'date': _latestQuestionDate});
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
      .map((q) => q.docs.map((d) => Countdown.fromJson(d.id, d.data())).toList());

  /// Calendar events. The free countdown limit is enforced here (Firestore
  /// rules can't count docs); plain calendar events are unlimited.
  @override
  Future<void> saveCountdown(Countdown countdown) async {
    checkEvent(countdown);
    final pairId = await _requirePairId();
    final col = _db.collection('pairs/$pairId/countdowns');
    final existing = countdown.id.isEmpty ? null : await col.doc(countdown.id).get();
    final wasCountdown = existing != null && existing.exists && (existing.data()?['showAsCountdown'] as bool? ?? true);
    if (countdown.showAsCountdown && !wasCountdown && AppConfig.monetizationEnabled) {
      final pair = await _db.doc('pairs/$pairId').get();
      final premium = Pair.fromJson(pair.id, pair.data() ?? {}).premium.active;
      if (!premium) {
        final count = (await col.where('showAsCountdown', isEqualTo: true).count().get()).count ?? 0;
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
      'dateKey':
          '${day.year.toString().padLeft(4, '0')}-'
          '${day.month.toString().padLeft(2, '0')}-'
          '${day.day.toString().padLeft(2, '0')}',
      'emoji': countdown.emoji,
      'repeatsYearly': countdown.repeatsYearly,
      'hasTime': countdown.hasTime,
      'remindMinutesBefore': countdown.remindMinutesBefore.clamp(0, Countdown.maxRemindMinutes),
      'remindDaysBefore': countdown.remindDaysBefore.clamp(0, 60),
      // The minute-level reminder job picks docs up by this instant.
      if (remindAt != null) 'nextRemindAt': Timestamp.fromDate(remindAt),
      'createdBy':
          (existing?.data()?['createdBy'] as String?) ?? (countdown.createdBy.isEmpty ? _uid : countdown.createdBy),
      'updatedAt': FieldValue.serverTimestamp(),
      'category': countdown.category.name,
      'endDate': countdown.endDate == null ? null : Timestamp.fromDate(countdown.endDate!),
      'note': _clip(countdown.note.trim(), Countdown.maxNote),
      'place': _clip(countdown.place.trim(), Countdown.maxPlace),
      'isVirtual': countdown.isVirtual,
      'showAsCountdown': countdown.showAsCountdown,
      'done': countdown.done,
      'ratings': countdown.ratings,
    });
  }

  @override
  Future<void> rateDate(String eventId, int hearts) async {
    final pairId = await _requirePairId();
    await _db.doc('pairs/$pairId/countdowns/$eventId').update({
      'ratings.$_uid': hearts.clamp(1, 5),
      'done': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> setDateGoal(DateGoal? goal) async {
    final pairId = await _requirePairId();
    await _db.doc('pairs/$pairId').update({'dateGoal': goal?.toJson() ?? FieldValue.delete()});
  }

  // ---------------------------------------------------------------- to-dos

  Stream<List<T>> _watchCol<T>(
    String path,
    T Function(String id, Map<String, dynamic> data) parse, {
    String? orderBy,
    bool descending = false,
  }) {
    Query<Map<String, dynamic>> q = _db.collection(path);
    if (orderBy != null) q = q.orderBy(orderBy, descending: descending);
    return q
        .limit(500)
        .snapshots()
        .map((s) => s.docs.map((d) => parse(d.id, d.data())).toList())
        .transform(_emptyOnPermissionDenied());
  }

  @override
  Stream<List<TodoList>> watchTodoLists(String pairId) =>
      _watchCol('pairs/$pairId/todoLists', TodoList.fromJson, orderBy: 'createdAt');

  @override
  Future<String> saveTodoList(TodoList list) async {
    if (list.title.trim().isEmpty) throw const CloserException('Name the list');
    final pairId = await _requirePairId();
    final col = _db.collection('pairs/$pairId/todoLists');
    final data = {'title': _clip(list.title.trim(), TodoList.maxTitle), 'emoji': list.emoji};
    if (list.id.isEmpty) {
      final ref = await col.add({...data, 'createdBy': _uid, 'createdAt': FieldValue.serverTimestamp()});
      return ref.id;
    }
    await col.doc(list.id).update(data);
    return list.id;
  }

  @override
  Future<void> deleteTodoList(String id) async {
    final pairId = await _requirePairId();
    final todos = await _db.collection('pairs/$pairId/todos').where('listId', isEqualTo: id).get();
    final batch = _db.batch();
    for (final t in todos.docs) {
      batch.delete(t.reference);
    }
    batch.delete(_db.doc('pairs/$pairId/todoLists/$id'));
    await batch.commit();
  }

  @override
  Stream<List<Todo>> watchTodos(String pairId) => _watchCol('pairs/$pairId/todos', Todo.fromJson, orderBy: 'createdAt');

  @override
  Future<void> saveTodo(Todo todo) async {
    checkTodo(todo);
    final pairId = await _requirePairId();
    final col = _db.collection('pairs/$pairId/todos');
    final data = <String, Object?>{
      'listId': todo.listId,
      'text': _clip(todo.text.trim(), Todo.maxText),
      'assignee': todo.assignee,
      'due': todo.due == null ? null : Timestamp.fromDate(todo.due!),
    };
    if (todo.id.isEmpty) {
      await col.add({
        ...data,
        'doneBy': null,
        'doneAt': null,
        'createdBy': _uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await col.doc(todo.id).update(data);
    }
  }

  @override
  Future<void> setTodoDone(String id, {required bool done}) async {
    final pairId = await _requirePairId();
    await _db.doc('pairs/$pairId/todos/$id').update({
      'doneAt': done ? FieldValue.serverTimestamp() : null,
      'doneBy': done ? _uid : null,
    });
  }

  @override
  Future<void> deleteTodo(String id) async {
    final pairId = await _requirePairId();
    await _db.doc('pairs/$pairId/todos/$id').delete();
  }

  // -------------------------------------------------------------- wishlist

  @override
  Stream<List<Wish>> watchWishes(String pairId) =>
      _watchCol('pairs/$pairId/wishes', Wish.fromJson, orderBy: 'createdAt', descending: true);

  @override
  Future<void> saveWish(Wish wish) async {
    checkWish(wish);
    final pairId = await _requirePairId();
    final col = _db.collection('pairs/$pairId/wishes');
    final data = <String, Object?>{
      'title': wish.title.trim(),
      'category': wish.category.name,
      'note': wish.note.trim(),
      'url': wish.url.trim(),
      'price': wish.price.trim(),
      'photoPath': wish.photoPath,
    };
    if (wish.id.isEmpty) {
      await col.add({
        ...data,
        'ownerUid': wish.isGift ? _uid : null,
        'doneAt': null,
        'createdBy': _uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await col.doc(wish.id).update(data);
    }
  }

  @override
  Future<void> deleteWish(String id) async {
    final pairId = await _requirePairId();
    await _db.doc('pairs/$pairId/wishes/$id').delete();
  }

  @override
  Future<void> setWishDone(String id, {required bool done}) async {
    final pairId = await _requirePairId();
    await _db.doc('pairs/$pairId/wishes/$id').update({'doneAt': done ? FieldValue.serverTimestamp() : null});
  }

  /// Claims are readable only by whoever made them, so the person who
  /// wished for the gift never sees it was claimed.
  @override
  Stream<Set<String>> watchMyWishClaims(String pairId) {
    final uid = currentUid;
    if (uid == null) return Stream.value(const {});
    return _db
        .collection('pairs/$pairId/wishClaims')
        .where('claimedBy', isEqualTo: uid)
        .snapshots()
        .map((q) => q.docs.map((d) => d.id).toSet())
        .transform(
          StreamTransformer<Set<String>, Set<String>>.fromHandlers(
            handleError: (e, st, sink) => _isPermissionDenied(e) ? sink.add(const {}) : sink.addError(e, st),
          ),
        );
  }

  @override
  Future<void> claimWish(String wishId, {required bool claim}) async {
    final pairId = await _requirePairId();
    final ref = _db.doc('pairs/$pairId/wishClaims/$wishId');
    try {
      if (claim) {
        await ref.set({'claimedBy': _uid, 'claimedAt': FieldValue.serverTimestamp()});
      } else {
        await ref.delete();
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') throw const CloserException('Already taken care of');
      rethrow;
    }
  }

  @override
  Future<void> deleteCountdown(String id) async {
    final pairId = await _requirePairId();
    await _db.doc('pairs/$pairId/countdowns/$id').delete();
  }

  // ----------------------------------------------------------------- media

  /// Photos for capsules, the timeline and the shrine:
  /// `pairs/{pairId}/media/{uid}/{id}.jpg` (see storage.rules).
  @override
  Future<String> uploadPhoto(String localPath) async {
    final pairId = await _requirePairId();
    final id = _db.collection('pairs/$pairId/capsules').doc().id;
    final tmp = '${(await getTemporaryDirectory()).path}/upload_$id.jpg';
    final out = await FlutterImageCompress.compressAndGetFile(
      localPath,
      tmp,
      minWidth: 1600,
      minHeight: 1600,
      quality: 85,
    );
    final path = 'pairs/$pairId/media/$_uid/$id.jpg';
    try {
      await _storage.ref(path).putFile(File(out?.path ?? localPath), SettableMetadata(contentType: 'image/jpeg'));
    } on FirebaseException catch (e) {
      throw CloserException('Upload failed (${e.code}). Check your connection.');
    }
    return path;
  }

  // -------------------------------------------------------------- capsules

  @override
  Stream<List<Capsule>> watchCapsules(String pairId) => _db
      .collection('pairs/$pairId/capsules')
      .orderBy('createdAt', descending: true)
      .limit(500)
      .snapshots()
      .map((q) => q.docs.map((d) => Capsule.fromJson(d.id, d.data())).toList())
      .transform(_emptyOnPermissionDenied());

  /// Envelope and content in one batch; the rules check the content against
  /// the envelope with getAfter().
  @override
  Future<void> sendCapsule(Capsule envelope, CapsuleContent content) async {
    final pairId = await _requirePairId();
    final uid = _uid;
    final pairSnap = await _db.doc('pairs/$pairId').get();
    final pair = Pair.fromJson(pairSnap.id, pairSnap.data() ?? {});
    final col = _db.collection('pairs/$pairId/capsules');
    var written = 0;
    if (envelope.kind == CapsuleKind.reason) {
      written =
          (await col.where('authorId', isEqualTo: uid).where('kind', isEqualTo: CapsuleKind.reason.name).count().get())
              .count ??
          0;
    }
    checkCapsule(envelope, content, reasonsWritten: written);
    final ref = envelope.id.isEmpty ? col.doc() : col.doc(envelope.id);
    final batch = _db.batch()
      ..set(ref, {
        'kind': envelope.kind.name,
        'authorId': uid,
        'forUid': pair.partnerOf(uid),
        'title': _clip(envelope.title.trim(), Capsule.maxTitle),
        'surpriseType': envelope.surpriseType?.name,
        'createdAt': FieldValue.serverTimestamp(),
        'unlockAt': Timestamp.fromDate(envelope.unlockAt),
        'openedAt': null,
        'notified': false,
      })
      ..set(ref.collection('content').doc('main'), {
        'text': content.text.trim(),
        'photoPath': content.photoPath,
        'giftId': content.giftId,
      });
    await batch.commit();
  }

  @override
  Future<CapsuleContent> openCapsule(Capsule capsule) async {
    final cached = _capsuleCache[capsule.id];
    if (cached != null) return cached;
    final pairId = await _requirePairId();
    try {
      final snap = await _db.doc('pairs/$pairId/capsules/${capsule.id}/content/main').get();
      if (!snap.exists) throw const CloserException('This one is gone');
      return _capsuleCache[capsule.id] = CapsuleContent.fromJson(snap.data()!);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const CloserException('Still sealed — no peeking! 🙈');
      }
      rethrow;
    }
  }

  @override
  Future<void> markCapsuleOpened(String capsuleId) async {
    final pairId = await _requirePairId();
    try {
      await _db.doc('pairs/$pairId/capsules/$capsuleId').update({'openedAt': FieldValue.serverTimestamp()});
    } on FirebaseException catch (e) {
      // Already opened, or clock skew around the unlock time: not worth an error.
      debugPrint('markCapsuleOpened: ${e.code}');
    }
  }

  @override
  Future<void> deleteCapsule(String capsuleId) async {
    final pairId = await _requirePairId();
    final ref = _db.doc('pairs/$pairId/capsules/$capsuleId');
    await (_db.batch()
          ..delete(ref.collection('content').doc('main'))
          ..delete(ref))
        .commit();
    _capsuleCache.remove(capsuleId);
  }

  // -------------------------------------------------------------- timeline

  @override
  Stream<List<TimelineEntry>> watchTimeline(String pairId) => _db
      .collection('pairs/$pairId/timeline')
      .orderBy('date')
      .snapshots()
      .map((q) => q.docs.map((d) => TimelineEntry.fromJson(d.id, d.data())).toList())
      .transform(_emptyOnPermissionDenied());

  @override
  Future<void> saveTimelineEntry(TimelineEntry entry) async {
    checkTimelineEntry(entry);
    final pairId = await _requirePairId();
    final col = _db.collection('pairs/$pairId/timeline');
    final data = <String, Object?>{
      'date': Timestamp.fromDate(entry.date),
      'title': _clip(entry.title.trim(), TimelineEntry.maxTitle),
      'emoji': entry.emoji,
      'note': _clip(entry.note.trim(), TimelineEntry.maxNote),
      'photoPath': entry.photoPath,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (entry.id.isEmpty) {
      await col.add({...data, 'createdBy': _uid, 'createdAt': FieldValue.serverTimestamp()});
    } else {
      await col.doc(entry.id).update(data);
    }
  }

  @override
  Future<void> deleteTimelineEntry(String id) async {
    final pairId = await _requirePairId();
    await _db.doc('pairs/$pairId/timeline/$id').delete();
  }

  // ---------------------------------------------------------------- shrine

  @override
  Stream<Map<String, Shrine>> watchShrines(String pairId) => _db
      .collection('pairs/$pairId/shrines')
      .snapshots()
      .map((q) => {for (final d in q.docs) d.id: Shrine.fromJson(d.id, d.data())})
      .transform(
        StreamTransformer<Map<String, Shrine>, Map<String, Shrine>>.fromHandlers(
          handleError: (e, st, sink) => _isPermissionDenied(e) ? sink.add(const {}) : sink.addError(e, st),
        ),
      );

  @override
  Future<void> saveShrine(Shrine shrine) async {
    final pairId = await _requirePairId();
    final clean = clampShrine(shrine);
    await _db.doc('pairs/$pairId/shrines/$_uid').set({...clean.toJson(), 'updatedAt': FieldValue.serverTimestamp()});
  }

  // ------------------------------------------------------------------ chat

  @override
  Stream<List<ChatMessage>> watchMessages(String pairId, {int limit = 300}) => _db
      .collection('pairs/$pairId/messages')
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots(includeMetadataChanges: true)
      .map(
        (q) => q.docs
            .map((d) => ChatMessage.fromJson(d.id, d.data(), pending: d.metadata.hasPendingWrites))
            .toList()
            .reversed
            .toList(),
      )
      .transform(_emptyOnPermissionDenied());

  /// Messages are written directly (rules-checked) so they appear at once,
  /// even offline; a function notifies the partner.
  @override
  Future<void> sendMessage(ChatDraft draft) async {
    checkMessage(draft);
    final pairId = await _requirePairId();
    final ref = _db.collection('pairs/$pairId/messages').doc();
    String? media;
    final path = draft.localPath;
    if (path != null) media = draft.isImage ? await uploadPhoto(path) : await uploadAudio(path);
    final batch = _db.batch()
      ..set(ref, {
        'senderId': _uid,
        'type': draft.type.name,
        'text': _clip(draft.text.trim(), ChatMessage.maxText),
        'mediaPath': media,
        'durationMs': draft.durationMs,
        'replyTo': draft.replyTo?.toJson(),
        'reactions': <String, String>{},
        'deletedAt': null,
        'viewLimit': draft.type == MessageType.snap ? draft.viewLimit : 0,
        'views': 0,
        'event': draft.event?.name,
        'ttl': (draft.ttl ?? ChatTtl.fallback).name,
        'createdAt': FieldValue.serverTimestamp(),
      })
      ..set(_db.doc('pairs/$pairId/chatState/$_uid'), {
        'readAt': FieldValue.serverTimestamp(),
        'typingUntil': null,
      }, SetOptions(merge: true));
    // Don't wait for the server: the local write shows the message now.
    unawaited(batch.commit().catchError((Object e) => debugPrint('sendMessage: $e')));
  }

  @override
  Future<void> reactToMessage(String messageId, String? emoji) async {
    final pairId = await _requirePairId();
    await _db.doc('pairs/$pairId/messages/$messageId').update({'reactions.$_uid': emoji ?? FieldValue.delete()});
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    final pairId = await _requirePairId();
    await _db.doc('pairs/$pairId/messages/$messageId').update({
      'text': '',
      'mediaPath': null,
      'deletedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> openSnap(String messageId) async {
    final pairId = await _requirePairId();
    final ref = _db.doc('pairs/$pairId/messages/$messageId');
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final m = ChatMessage.fromJson(snap.id, snap.data() ?? const {});
      if (!m.isSnap || m.senderId == _uid) return;
      if (m.snapUsedUp) throw const CloserException('This snap has already been opened');
      tx.update(ref, {'views': m.views + 1});
    });
  }

  @override
  Future<void> sendChatEvent(ChatEvent event, {ReplyRef? about, ChatTtl? ttl, String text = ''}) async {
    final pairId = _pairId;
    if (currentUid == null || pairId == null) return;
    await _db.collection('pairs/$pairId/messages').add({
      'senderId': _uid,
      'type': MessageType.event.name,
      'text': text,
      'mediaPath': null,
      'durationMs': 0,
      'replyTo': about?.toJson(),
      'reactions': <String, String>{},
      'deletedAt': null,
      'viewLimit': 0,
      'views': 0,
      'event': event.name,
      'ttl': (ttl ?? ChatTtl.fallback).name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> setChatTtl(ChatTtl ttl) async {
    final pairId = await _requirePairId();
    await _db.doc('pairs/$pairId').update({'chatTtl': ttl.name});
    await sendChatEvent(ChatEvent.ttl, ttl: ttl, text: ttl.name);
  }

  @override
  Future<void> clearViewedMessages() async {
    final uid = currentUid;
    final pairId = _pairId;
    if (uid == null || pairId == null) return;
    final now = DateTime.now();
    final q = await _db.collection('pairs/$pairId/messages').where('ttl', isEqualTo: ChatTtl.viewed.name).get();
    final batch = _db.batch();
    var n = 0;
    for (final d in q.docs) {
      if (d.metadata.hasPendingWrites) continue;
      final m = ChatMessage.fromJson(d.id, d.data());
      if (m.senderId == uid || m.createdAt.isAfter(now)) continue;
      batch.delete(d.reference);
      if (++n == 450) break;
    }
    if (n > 0) await batch.commit();
  }

  @override
  Stream<Map<String, ChatState>> watchChatState(String pairId) => _db
      .collection('pairs/$pairId/chatState')
      .snapshots()
      .map((q) => {for (final d in q.docs) d.id: ChatState.fromJson(d.data())})
      .transform(
        StreamTransformer<Map<String, ChatState>, Map<String, ChatState>>.fromHandlers(
          handleError: (e, st, sink) => _isPermissionDenied(e) ? sink.add(const {}) : sink.addError(e, st),
        ),
      );

  @override
  Future<void> markChatRead() async {
    final uid = currentUid;
    final pairId = _pairId;
    if (uid == null || pairId == null) return;
    await _db.doc('pairs/$pairId/chatState/$uid').set({
      'readAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> setTyping({required bool typing}) async {
    final pairId = await _requirePairId();
    await _db.doc('pairs/$pairId/chatState/$_uid').set({
      'typingUntil': typing ? Timestamp.fromDate(DateTime.now().add(const Duration(seconds: 6))) : null,
    }, SetOptions(merge: true));
  }

  /// `pairs/{pairId}/audio/{uid}/{id}.m4a` (see storage.rules).
  @override
  Future<String> uploadAudio(String localPath) async {
    final pairId = await _requirePairId();
    final id = _db.collection('pairs/$pairId/messages').doc().id;
    final path = 'pairs/$pairId/audio/$_uid/$id.m4a';
    try {
      await _storage.ref(path).putFile(File(localPath), SettableMetadata(contentType: 'audio/mp4'));
    } on FirebaseException catch (e) {
      throw CloserException('Upload failed (${e.code}). Check your connection.');
    }
    return path;
  }

  // ------------------------------------------------------------- goodnight

  @override
  Stream<List<Goodnight>> watchGoodnights(String pairId) => _db
      .collection('pairs/$pairId/goodnights')
      .orderBy(FieldPath.documentId, descending: true)
      .limit(30)
      .snapshots()
      .map((q) => q.docs.map((d) => Goodnight.fromJson(d.id, d.data())).toList())
      .transform(_emptyOnPermissionDenied());

  @override
  Future<void> sendGoodnight(GoodnightEntry entry) async {
    checkGoodnight(entry);
    final pairId = await _requirePairId();
    final photo = entry.momentPhotoPath == null ? null : await uploadPhoto(entry.momentPhotoPath!);
    final voice = entry.voicePath == null ? null : await uploadAudio(entry.voicePath!);
    final night = Goodnight.keyFor(DateTime.now());
    await _db.doc('pairs/$pairId/goodnights/$night').set({
      'entries': {
        _uid: {
          'message': _clip(entry.message.trim(), GoodnightEntry.maxText),
          'moment': _clip(entry.moment.trim(), GoodnightEntry.maxText),
          'momentPhotoPath': photo,
          'voicePath': voice,
          'voiceMs': entry.voiceMs,
          'kiss': entry.kiss,
          'sentAt': FieldValue.serverTimestamp(),
        },
      },
    }, SetOptions(merge: true));
  }

  // ------------------------------------------------------------ pet & home

  Future<Pair> _pair() async {
    final pairId = await _requirePairId();
    final snap = await _db.doc('pairs/$pairId').get();
    return Pair.fromJson(snap.id, snap.data() ?? {});
  }

  @override
  Future<void> savePet(Pet pet) async {
    final pair = await _pair();
    checkPet(pet, pair);
    if (pair.pet != null) {
      // Renaming: only the name changes (feeding times belong to each member).
      await _db.doc('pairs/${pair.id}').update({'pet.name': _clip(pet.name.trim(), Pet.maxName)});
      return;
    }
    await _db.doc('pairs/${pair.id}').update({
      'pet': {
        'species': pet.species,
        'name': _clip(pet.name.trim(), Pet.maxName),
        'hatchedAt': Timestamp.fromDate(pet.hatchedAt),
        'lastFed': pet.lastFed.map((k, v) => MapEntry(k, Timestamp.fromDate(v))),
        'lastPlayed': pet.lastPlayed.map((k, v) => MapEntry(k, Timestamp.fromDate(v))),
      },
    });
  }

  @override
  Future<void> careForPet(String action) async {
    final pairId = await _requirePairId();
    final field = action == 'feed' ? 'lastFed' : 'lastPlayed';
    try {
      await _db.doc('pairs/$pairId').update({'pet.$field.$_uid': FieldValue.serverTimestamp()});
    } on FirebaseException catch (e) {
      if (e.code == 'not-found' || e.code == 'failed-precondition') throw const CloserException('Hatch your pet first');
      rethrow;
    }
  }

  @override
  Future<void> saveHome(PetHome home) async {
    final pair = await _pair();
    checkHome(pair.home, home, pair);
    await _db.doc('pairs/${pair.id}').update({'home': home.toJson()});
  }

  // -------------------------------------------------------------- insights

  @override
  Stream<List<MoodEntry>> watchMoodLog(String pairId) => _db
      .collection('pairs/$pairId/moods')
      .orderBy('date', descending: true)
      .limit(200)
      .snapshots()
      .map((q) => q.docs.map((d) => MoodEntry.fromJson(d.data())).toList())
      .transform(_emptyOnPermissionDenied());

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
        throw const LimitReachedException('plus', 'This theme is part of Duosy Plus.');
      }
      rethrow;
    }
  }

  @override
  Future<void> debugSetPremium({required bool active}) {
    throw UnsupportedError('Premium is set by the RevenueCat webhook on the Firebase backend.');
  }

  // ------------------------------------------------------------------- FCM

  @override
  Future<void> registerDevice() async {
    if (currentUid == null) return;
    // FCM has no emulator: the demo project can't get a push token.
    if (useFirebaseEmulator) return;
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    // Classic registration tokens: the functions send with sendEachForMulticast.
    // ignore: deprecated_member_use
    final token = await messaging.getToken();
    if (token != null) await _registerToken(token);
    // Token refresh for the same classic-token flow as above.
    // ignore: deprecated_member_use
    _tokenSub ??= messaging.onTokenRefresh.listen(
      (t) => unawaited(
        _registerToken(t).catchError((Object e) {
          debugPrint('registerFcmToken failed: $e');
        }),
      ),
    );
  }

  Future<void> _registerToken(String token) async {
    if (currentUid == null) return;
    _fcmToken = token;
    // Also refreshes the zone (travel, daylight-saving rule changes).
    await _call('registerFcmToken', {'token': token, 'timezone': await deviceTimezone()});
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

  Future<Map<String, dynamic>> _call(String name, Map<String, Object?> data) async {
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
      return _paywallLimits.contains(limit) ? LimitReachedException(limit, message) : CloserException(message);
    }
    switch (e.code) {
      case 'unavailable':
      case 'deadline-exceeded':
        return const NetworkException();
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

  static bool _isPermissionDenied(Object e) => e is FirebaseException && e.code == 'permission-denied';

  /// After unpairing (or before a doc exists) listeners can be denied; turn
  /// that into `null` instead of an error.
  static StreamTransformer<T?, T?> _nullOnPermissionDenied<T>() => StreamTransformer<T?, T?>.fromHandlers(
    handleError: (e, st, sink) {
      if (_isPermissionDenied(e)) {
        sink.add(null);
      } else {
        sink.addError(e, st);
      }
    },
  );

  /// Like [_nullOnPermissionDenied] for list streams.
  static StreamTransformer<List<T>, List<T>> _emptyOnPermissionDenied<T>() =>
      StreamTransformer<List<T>, List<T>>.fromHandlers(
        handleError: (e, st, sink) {
          if (_isPermissionDenied(e)) {
            sink.add(<T>[]);
          } else {
            sink.addError(e, st);
          }
        },
      );

  static String _clip(String s, int max) => s.length <= max ? s : s.substring(0, max);

  static String _contentType(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
