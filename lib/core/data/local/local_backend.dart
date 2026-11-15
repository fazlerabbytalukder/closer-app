import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:closer_app/core/config.dart';
import 'package:closer_app/core/data/closer_backend.dart';
import 'package:closer_app/core/data/content.dart';
import 'package:closer_app/core/data/local/partner_simulator.dart';
import 'package:closer_app/core/data/local/text_repair.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/models/streak_rules.dart';
import 'package:closer_app/core/services/note_renderer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Fully on-device implementation of [CloserBackend].
///
/// Data lives in one JSON file in the app support directory; media files sit
/// next to it. A [PartnerSimulator] plays the role of the other person so
/// the whole product (pairing, widget updates, question reveals, games,
/// streaks) can be used on a single emulator without any cloud setup.
///
/// It mirrors the server rules from the plan: limits, reveal-when-both and
/// streak logic are enforced here exactly where Cloud Functions would do it.
class LocalBackend implements CloserBackend {
  LocalBackend({Duration simulatorScale = const Duration(seconds: 1), this.dbFileName = 'closer_local_db.json'})
      : _scale = simulatorScale;

  final Duration _scale;

  /// Separate file names keep test runs away from real local data.
  final String dbFileName;
  final _uuid = const Uuid();
  final _rand = Random();
  final _changes = StreamController<void>.broadcast();
  late final PartnerSimulator _sim = PartnerSimulator(this, _scale);

  late Directory _dir;
  late File _dbFile;
  Map<String, dynamic> _db = {};
  Timer? _saveDebounce;
  Timer? _dayTimer;

  @override
  String get name => 'local';

  @override
  bool get isSimulated => true;

  Directory get mediaDir => Directory('${_dir.path}/media');

  // ------------------------------------------------------------ storage
  @override
  Future<void> init() async {
    _dir = await getApplicationSupportDirectory();
    _dbFile = File('${_dir.path}/$dbFileName');
    await mediaDir.create(recursive: true);
    if (_dbFile.existsSync()) {
      try {
        _db = Map<String, dynamic>.from(
          jsonDecode(await _dbFile.readAsString()) as Map,
        );
      } on Object catch (e) {
        debugPrint('Local DB corrupt, starting fresh: $e');
        _db = {};
      }
    }
    if (_db['textRepaired'] != true) await _repairSavedText();
    _rollDay();
    // Day rollover check (streaks + daily question), like the hourly jobs.
    _dayTimer = Timer.periodic(const Duration(minutes: 1), (_) => _rollDay());
    _sim.resume();
  }

  /// One-time fix for demo data an early build saved with broken emoji
  /// ("ðŸ¥°"): repairs the stored text and re-draws the simulated
  /// partner's note images from the repaired text.
  Future<void> _repairSavedText() async {
    try {
      final changed = repairJsonTree(_db);
      if (changed > 0) {
        for (final items in _col('items').values) {
          for (final raw in (items as Map).values) {
            final item = Item.fromJson('', Map<String, dynamic>.from(raw as Map));
            final path = item.storagePath;
            if (item.type != ItemType.note || item.text == null || path == null || !path.endsWith('.png')) continue;
            await NoteRenderer.renderToFile(
              text: item.text!,
              style: item.noteStyle ?? const NoteStyle(bg: 'blush', font: 'rounded'),
              path: path,
            );
            if (item.thumbPath != null && item.thumbPath != path) {
              await FlutterImageCompress.compressAndGetFile(path, item.thumbPath!, minWidth: 600, minHeight: 600, quality: 80);
            }
          }
        }
        // Make the home-screen widget pick up the re-drawn image.
        final widgetDir = Directory('${_dir.path}/widget');
        if (widgetDir.existsSync()) await widgetDir.delete(recursive: true);
        debugPrint('Repaired $changed saved text values');
      }
    } on Object catch (e) {
      debugPrint('Text repair skipped: $e');
    }
    _db['textRepaired'] = true;
    _commit();
  }

  Map<String, dynamic> _col(String name) =>
      (_db[name] ??= <String, dynamic>{}) as Map<String, dynamic>;

  Map<String, dynamic> _sub(String name, String key) =>
      (_col(name)[key] ??= <String, dynamic>{}) as Map<String, dynamic>;

  void _commit() {
    if (!_changes.isClosed) _changes.add(null);
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        await _dbFile.writeAsString(jsonEncode(_db));
      } on Object catch (e) {
        debugPrint('Local DB save failed: $e');
      }
    });
  }

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changes.stream) {
      yield read();
    }
  }

  // ------------------------------------------------------------- helpers
  String get _me {
    final uid = currentUid;
    if (uid == null) throw const CloserException('Not signed in');
    return uid;
  }

  Map<String, dynamic>? userDoc(String uid) =>
      _col('users')[uid] as Map<String, dynamic>?;

  String? get myPairId => userDoc(_me)?['pairId'] as String?;

  String get _pairId {
    final id = myPairId;
    if (id == null) throw const CloserException('You are not paired yet');
    return id;
  }

  Map<String, dynamic>? pairDoc(String pairId) =>
      _col('pairs')[pairId] as Map<String, dynamic>?;

  Pair? pairOf(String pairId) {
    final d = pairDoc(pairId);
    return d == null ? null : Pair.fromJson(pairId, d);
  }

  bool _isPlus(String pairId) =>
      !AppConfig.monetizationEnabled ||
      (pairDoc(pairId)?['premium'] as Map?)?['active'] == true;

  String partnerUidOf(String uid) {
    final pair = pairOf(userDoc(uid)?['pairId'] as String? ?? '');
    return pair?.partnerOf(uid) ?? '';
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;
  String get _today => dayKey(DateTime.now());

  // ---------------------------------------------------------------- auth
  @override
  String? get currentUid => _db['currentUid'] as String?;

  @override
  Stream<String?> authState() => _watch(() => currentUid);

  @override
  Future<void> signInWithGoogle() async {
    // Local stand-in for Google sign-in: one device account.
    final uid = _db['deviceUid'] as String? ?? 'me_${_uuid.v4().substring(0, 8)}';
    _db['deviceUid'] = uid;
    _col('users').putIfAbsent(
      uid,
      () => AppUser(
        uid: uid,
        displayName: '',
        createdAt: DateTime.now(),
        timezone: DateTime.now().timeZoneName,
      ).toJson(),
    );
    _db['currentUid'] = uid;
    _commit();
  }

  @override
  Future<void> signOut() async {
    _db['currentUid'] = null;
    _commit();
  }

  // --------------------------------------------------------------- users
  @override
  Stream<AppUser?> watchUser(String uid) => _watch(() {
        final d = userDoc(uid);
        return d == null ? null : AppUser.fromJson(uid, d);
      });

  @override
  Future<void> updateProfile({String? displayName, String? photoFilePath}) async {
    final u = userDoc(_me)!;
    if (displayName != null) u['displayName'] = displayName.trim();
    if (photoFilePath != null) {
      final target = '${mediaDir.path}/avatar_${_me}_$_now.jpg';
      final out = await FlutterImageCompress.compressAndGetFile(
        photoFilePath,
        target,
        minWidth: 400,
        minHeight: 400,
        quality: 85,
      );
      u['photoUrl'] = out?.path ?? photoFilePath;
    }
    _commit();
  }

  @override
  Future<void> setPendingMode(PairMode mode, {String? label}) async {
    userDoc(_me)!
      ..['pendingMode'] = mode.name
      ..['pendingLabel'] = RelationLabel.validFor(label, mode);
    _commit();
  }

  @override
  Future<void> updateMood(Mood mood) async {
    userDoc(_me)!['mood'] = mood.toJson();
    final pairId = myPairId;
    if (pairId != null) logMood(pairId, _me, mood, _today);
    _commit();
    _sim.onMyMood(mood);
  }

  /// Mood history for insights: one entry per member per day.
  void logMood(String pairId, String uid, Mood mood, String date) {
    _sub('moodLog', pairId)['${uid}_$date'] =
        MoodEntry(uid: uid, date: date, emoji: mood.emoji, label: mood.label).toJson();
    _commit();
  }

  @override
  Future<void> updateStatus(StatusText status) async {
    userDoc(_me)!['status'] = status.toJson();
    _commit();
  }

  @override
  Future<void> setAgeConfirmed({required bool confirmed}) async {
    userDoc(_me)!['ageConfirmed18'] = confirmed;
    _commit();
  }

  @override
  Future<void> updateNotificationPrefs(NotificationPrefs prefs) async {
    userDoc(_me)!['notificationPrefs'] = prefs.toJson();
    _commit();
  }

  // ------------------------------------------------------------- pairing
  static const _codeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  String _newCode() =>
      List.generate(6, (_) => _codeChars[_rand.nextInt(_codeChars.length)]).join();

  @override
  Future<Invite> createInvite(PairMode mode) async {
    if (myPairId != null) throw const CloserException('You are already paired');
    // Reuse a still-valid invite so the code doesn't change on every visit.
    for (final e in _col('invites').entries) {
      final inv = Invite.fromJson(e.key, Map<String, dynamic>.from(e.value as Map));
      if (inv.inviterUid == _me &&
          inv.usedBy == null &&
          inv.mode == mode &&
          inv.expiresAt.isAfter(DateTime.now())) {
        _sim.onInviteCreated(inv);
        return inv;
      }
    }
    final invite = Invite(
      code: _newCode(),
      inviterUid: _me,
      mode: mode,
      expiresAt: DateTime.now().add(const Duration(hours: 48)),
    );
    _col('invites')[invite.code] = invite.toJson();
    _commit();
    _sim.onInviteCreated(invite);
    return invite;
  }

  @override
  Future<void> acceptInvite(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    if (code.length != 6) throw const CloserException('Codes have 6 characters');
    if (myPairId != null) throw const CloserException('You are already paired');
    final raw = _col('invites')[code];
    if (raw != null) {
      final inv = Invite.fromJson(code, Map<String, dynamic>.from(raw as Map));
      if (inv.inviterUid == _me) {
        throw const CloserException("That's your own code — send it to your person!");
      }
      if (inv.usedBy != null) throw const CloserException('This code was already used');
      if (inv.expiresAt.isBefore(DateTime.now())) {
        throw const CloserException('This code has expired — ask for a new one');
      }
      createPair(inv.inviterUid, _me, inv.mode);
      (_col('invites')[code] as Map)['usedBy'] = _me;
      _commit();
      return;
    }
    // Local mode: any unknown code is treated as the simulated partner's
    // invite so pairing can be tried on one device.
    final mode = PairMode.parse(userDoc(_me)?['pendingMode']);
    final partner = _sim.ensurePartner(mode);
    createPair(partner, _me, mode);
  }

  /// Creates the pair document and links both users (acceptInvite's
  /// transaction in Cloud Functions).
  void createPair(String inviter, String joiner, PairMode mode) {
    final id = 'pair_${_uuid.v4().substring(0, 8)}';
    // Each member's onboarding choice ("they are my girlfriend") carries
    // over if it fits the invite's mode.
    final labels = <String, String>{
      for (final uid in [inviter, joiner])
        uid: ?RelationLabel.validFor(userDoc(uid)?['pendingLabel'] as String?, mode),
    };
    final pair = Pair(
      id: id,
      memberIds: [inviter, joiner],
      mode: mode,
      pairedAt: DateTime.now(),
      timezone: DateTime.now().timeZoneName,
      relationLabels: labels,
    );
    _col('pairs')[id] = pair.toJson();
    for (final uid in [inviter, joiner]) {
      userDoc(uid)!
        ..['pairId'] = id
        ..['pendingLabel'] = null;
    }
    _ensureTodayQuestion(id);
    _commit();
    _sim.onPaired(id);
  }

  @override
  Future<void> unpair() async {
    final pairId = _pairId;
    final pair = pairOf(pairId)!;
    for (final m in pair.memberIds) {
      userDoc(m)?['pairId'] = null;
    }
    // Plan: data deleted after the export window — locally, immediately.
    for (final c in ['pairs', 'items', 'taps', 'questions', 'privateAnswers', 'countdowns', 'games', 'questionPack', 'missMeters', 'missPrivate',
                    'capsules', 'capsuleContent', 'timeline', 'shrines',
                    'todoLists', 'todos', 'wishes', 'wishClaims',
                    'messages', 'chatState', 'goodnights', 'moodLog']) {
      _col(c).remove(pairId);
    }
    _sim.onUnpaired();
    _commit();
  }

  @override
  Future<void> deleteAccount() async {
    final uid = _me;
    if (myPairId != null) await unpair();
    _col('users').remove(uid);
    _db
      ..remove('deviceUid')
      ..['currentUid'] = null;
    _col('invites').removeWhere((_, v) => (v as Map)['inviterUid'] == uid);
    if (mediaDir.existsSync()) {
      await mediaDir.delete(recursive: true);
      await mediaDir.create(recursive: true);
    }
    _commit();
  }

  @override
  Future<String> exportMemories() async {
    final pairId = _pairId;
    final docs = await getApplicationDocumentsDirectory();
    final out = Directory('${docs.path}/closer_export_$_today');
    await out.create(recursive: true);
    final items = _sub('items', pairId);
    final list = <Map<String, dynamic>>[];
    for (final e in items.entries) {
      final item = Item.fromJson(e.key, Map<String, dynamic>.from(e.value as Map));
      final src = item.storagePath;
      String? copied;
      if (src != null && File(src).existsSync()) {
        copied = '${out.path}/${item.id}${src.substring(src.lastIndexOf('.'))}';
        await File(src).copy(copied);
      }
      list.add({...item.toJson(), 'id': item.id, 'file': copied?.split(Platform.pathSeparator).last});
    }
    await File('${out.path}/memories.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(list));
    return out.path;
  }

  @override
  Stream<Pair?> watchPair(String pairId) => _watch(() => pairOf(pairId));

  @override
  Future<void> updateRelationship({
    PairMode? mode,
    DateTime? anniversary,
    bool clearAnniversary = false,
    String? label,
    String? nickname,
  }) async {
    final p = pairDoc(_pairId)!;
    final newMode = mode ?? PairMode.parse(p['mode']);
    final labels = Map<String, dynamic>.from(p['relationLabels'] as Map? ?? const {});
    if (mode != null) {
      p['mode'] = mode.name;
      // Drop labels that don't fit the new mode ("girlfriend" → friends).
      labels.removeWhere((_, v) => RelationLabel.validFor(v as String?, newMode) == null);
    }
    if (label != null) {
      final valid = RelationLabel.validFor(label, newMode);
      if (valid == null) throw const CloserException('That label doesn’t match your relationship type');
      labels[_me] = valid;
    }
    p['relationLabels'] = labels;
    if (nickname != null) {
      final nicks = Map<String, dynamic>.from(p['nicknames'] as Map? ?? const {});
      final n = nickname.trim();
      if (n.isEmpty) {
        nicks.remove(_me);
      } else {
        nicks[_me] = n.length > 24 ? n.substring(0, 24) : n;
      }
      p['nicknames'] = nicks;
    }
    if (clearAnniversary) {
      p['anniversary'] = null;
    } else if (anniversary != null) {
      if (anniversary.isAfter(DateTime.now())) {
        throw const CloserException('Pick a date in the past');
      }
      p['anniversary'] = DateTime(anniversary.year, anniversary.month, anniversary.day).millisecondsSinceEpoch;
    }
    _commit();
  }

  @override
  Future<void> setLastMet(DateTime when) async {
    if (when.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      throw const CloserException('Pick a time that already happened');
    }
    pairDoc(_pairId)!['lastMetAt'] = when.millisecondsSinceEpoch;
    _commit();
  }

  // --------------------------------------------------------------- items
  String _usageKey(String uid) => '${uid}_$_today';

  Map<String, dynamic> _usage(String uid) =>
      (_col('usage')[_usageKey(uid)] ??= <String, dynamic>{'sends': 0, 'bonus': 0})
          as Map<String, dynamic>;

  @override
  Stream<int> watchSendsToday() => _watch(() {
        final uid = currentUid;
        if (uid == null) return 0;
        final u = _col('usage')[_usageKey(uid)] as Map?;
        return (u?['sends'] as int? ?? 0) - (u?['bonus'] as int? ?? 0);
      });

  @override
  Future<void> grantRewardedSends() async {
    final u = _usage(_me);
    u['bonus'] = (u['bonus'] as int? ?? 0) + FreeLimits.rewardedExtraSends;
    _commit();
  }

  @override
  Future<Item> sendItem(SendRequest request) async {
    final pairId = _pairId;
    final uid = _me;
    final usage = _usage(uid);
    final used = (usage['sends'] as int) - (usage['bonus'] as int? ?? 0);
    if (!_isPlus(pairId) && used >= FreeLimits.sendsPerDay) {
      throw const LimitReachedException('sends', "You've used today's 10 free sends");
    }
    final item = await storeItem(
      pairId: pairId,
      senderId: uid,
      type: request.type,
      sourcePath: request.imagePath,
      caption: request.caption,
      text: request.text,
      noteStyle: request.noteStyle,
      geo: request.geo,
      saveToMemories: request.saveToMemories,
      secret: request.secret,
    );
    usage['sends'] = (usage['sends'] as int) + 1;
    _commit();
    _sim.onMyItem(item);
    return item;
  }

  /// Copies the image into app storage, makes the widget thumbnail (the
  /// `makeThumbnail` function's job) and writes the item + latestItem.
  Future<Item> storeItem({
    required String pairId,
    required String senderId,
    required ItemType type,
    required String sourcePath,
    String caption = '',
    String? text,
    NoteStyle? noteStyle,
    GeoTag? geo,
    bool saveToMemories = true,
    bool secret = false,
  }) async {
    final id = _uuid.v4();
    final isPng = sourcePath.toLowerCase().endsWith('.png');
    final full = '${mediaDir.path}/$id${isPng ? '.png' : '.jpg'}';
    final thumb = '${mediaDir.path}/${id}_thumb.jpg';
    await File(sourcePath).copy(full);
    final t = await FlutterImageCompress.compressAndGetFile(
      sourcePath,
      thumb,
      minWidth: 600,
      minHeight: 600,
      quality: 80,
    );
    final item = Item(
      id: id,
      type: type,
      senderId: senderId,
      storagePath: full,
      thumbPath: t?.path ?? full,
      caption: caption.length > Item.maxCaption ? caption.substring(0, Item.maxCaption) : caption,
      text: text,
      noteStyle: noteStyle,
      geo: geo,
      saveToMemories: saveToMemories,
      secret: secret,
      createdAt: DateTime.now(),
    );
    _sub('items', pairId)[id] = item.toJson();
    final p = pairDoc(pairId);
    if (p != null) {
      final latest = Map<String, dynamic>.from(p['latestItemByUser'] as Map? ?? const {});
      latest[senderId] = LatestItem(
        itemId: id,
        type: type,
        thumbPath: item.thumbPath,
        caption: item.caption,
        secret: secret,
        sentAt: item.createdAt,
      ).toJson();
      p['latestItemByUser'] = latest;
      final stats = PairStats.fromJson(Map<String, dynamic>.from(p['stats'] as Map? ?? {}));
      p['stats'] = PairStats(
        itemsSent: stats.itemsSent + 1,
        questionsAnswered: stats.questionsAnswered,
        tapsSent: stats.tapsSent,
      ).toJson();
    }
    markActive(pairId, senderId);
    _commit();
    return item;
  }

  @override
  Stream<List<Item>> watchItems(String pairId, {int limit = 200}) => _watch(() {
        final items = _sub('items', pairId)
            .entries
            .map((e) => Item.fromJson(e.key, Map<String, dynamic>.from(e.value as Map)))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return items.take(limit).toList();
      });

  @override
  Future<String?> resolveImage(String? ref) async => ref;

  @override
  Future<void> reactToItem(String itemId, String? emoji) async {
    final item = setReaction(_pairId, itemId, _me, emoji);
    if (emoji != null) _sim.onMyReaction(item);
  }

  /// `reactItem` function: one reaction per member per item.
  Item setReaction(String pairId, String itemId, String uid, String? emoji) {
    final raw = _sub('items', pairId)[itemId] as Map<String, dynamic>?;
    if (raw == null) throw const CloserException('That memory is gone');
    if (emoji != null && !reactionEmojis.contains(emoji)) {
      throw const CloserException('Unknown reaction');
    }
    final reactions = Map<String, dynamic>.from(raw['reactions'] as Map? ?? const {});
    if (emoji == null) {
      reactions.remove(uid);
    } else {
      reactions[uid] = emoji;
    }
    raw['reactions'] = reactions;
    _commit();
    return Item.fromJson(itemId, raw);
  }

  @override
  Future<void> revealSecret(String itemId) async => revealItem(_pairId, itemId, _me);

  /// `revealAdmirer` function: only the sender may reveal.
  void revealItem(String pairId, String itemId, String uid) {
    final raw = _sub('items', pairId)[itemId] as Map<String, dynamic>?;
    if (raw == null) throw const CloserException('That note is gone');
    if (raw['senderId'] != uid) throw const CloserException('Only the sender can reveal this');
    raw['revealedAt'] ??= _now;
    final latest = (pairDoc(pairId)?['latestItemByUser'] as Map?)?[uid] as Map?;
    if (latest != null && latest['itemId'] == itemId) latest['secret'] = false;
    _commit();
  }

  // ---------------------------------------------------------------- taps
  @override
  Future<void> sendTap({String kind = 'heart'}) async {
    final pairId = _pairId;
    final last = _col('lastTap')[_me] as int? ?? 0;
    if (_now - last < FreeLimits.tapCooldown.inMilliseconds) {
      throw const CloserException('Easy there! One tap every 10 seconds 💗');
    }
    _col('lastTap')[_me] = _now;
    final k = TapKind.byId(kind);
    writeTap(pairId, _me, k.id);
    _sim.onMyTap(k);
  }

  void writeTap(String pairId, String senderId, String kind) {
    final tap = Tap(id: _uuid.v4(), senderId: senderId, kind: kind, createdAt: DateTime.now());
    final taps = _sub('taps', pairId)..[tap.id] = tap.toJson();
    // TTL: keep 30 days.
    final cutoff = _now - const Duration(days: 30).inMilliseconds;
    taps.removeWhere((_, v) => ((v as Map)['createdAt'] as int? ?? 0) < cutoff);
    final p = pairDoc(pairId);
    if (p != null) {
      final s = PairStats.fromJson(Map<String, dynamic>.from(p['stats'] as Map? ?? {}));
      p['stats'] = PairStats(itemsSent: s.itemsSent, questionsAnswered: s.questionsAnswered, tapsSent: s.tapsSent + 1).toJson();
    }
    markActive(pairId, senderId);
    _commit();
  }

  @override
  Stream<Tap?> watchLatestTap(String pairId) => _watch(() {
        Tap? latest;
        for (final e in _sub('taps', pairId).entries) {
          final t = Tap.fromJson(e.key, Map<String, dynamic>.from(e.value as Map));
          if (latest == null || t.createdAt.isAfter(latest.createdAt)) latest = t;
        }
        return latest;
      });

  // -------------------------------------------------------- miss meter
  @override
  Stream<List<MissMeter>> watchMissMeters(String pairId) => _watch(() {
        final uid = currentUid;
        final priv = _sub('missPrivate', pairId);
        final list = _sub('missMeters', pairId)
            .entries
            .map((e) => MissMeter.fromJson(e.key, Map<String, dynamic>.from(e.value as Map))
                .withMyValue((priv[e.key] as Map?)?[uid] as int?))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        return list.take(30).toList();
      });

  @override
  Future<void> submitMissMeter(int value) async {
    answerMissMeter(_pairId, _me, value);
    _sim.onMyMissMeter(_pairId);
  }

  /// `submitMissMeter` function: private value; reveal when both answered.
  void answerMissMeter(String pairId, String uid, int value) {
    final v = value.clamp(0, MissMeter.max);
    final doc = (_sub('missMeters', pairId)[_today] ??= <String, dynamic>{}) as Map<String, dynamic>;
    if (doc['revealed'] == true) throw const CloserException('Already revealed today — come back tomorrow!');
    final priv = (_sub('missPrivate', pairId)[_today] ??= <String, dynamic>{}) as Map<String, dynamic>;
    priv[uid] = v;
    final answeredBy = (doc['answeredBy'] as List? ?? []).cast<String>().toSet()..add(uid);
    doc['answeredBy'] = answeredBy.toList();
    final members = pairOf(pairId)?.memberIds ?? const [];
    if (members.isNotEmpty && members.every(answeredBy.contains)) {
      doc
        ..['revealed'] = true
        ..['values'] = Map<String, dynamic>.from(priv);
    }
    markActive(pairId, uid);
    _commit();
  }

  MissMeter? readTodayMissMeter(String pairId) {
    final raw = _sub('missMeters', pairId)[_today];
    return raw == null ? null : MissMeter.fromJson(_today, Map<String, dynamic>.from(raw as Map));
  }

  // ----------------------------------------------------- daily question
  void _ensureTodayQuestion(String pairId) {
    final qs = _sub('questions', pairId);
    if (qs.containsKey(_today)) return;
    final packId = _col('questionPack')[pairId] as String? ?? 'everyday';
    final pack = packById(_isPlus(pairId) ? packId : 'everyday');
    final asked = qs.values.map((v) => (v as Map)['questionId']).toSet();
    final remaining = [
      for (var i = 0; i < pack.questions.length; i++)
        if (!asked.contains('${pack.id}_$i')) i,
    ];
    final idx = remaining.isEmpty
        ? _rand.nextInt(pack.questions.length)
        : remaining[_rand.nextInt(remaining.length)];
    qs[_today] = DailyQuestion(
      date: _today,
      questionId: '${pack.id}_$idx',
      text: pack.questions[idx],
      packId: pack.id,
    ).toJson();
    _sim.onNewQuestion(pairId, _today);
  }

  DailyQuestion? readTodayQuestion(String pairId) {
    final raw = _sub('questions', pairId)[_today];
    if (raw == null) return null;
    final q = DailyQuestion.fromJson(_today, Map<String, dynamic>.from(raw as Map));
    final mine = (_sub('privateAnswers', pairId)[_today] as Map?)?[currentUid] as String?;
    return q.withMyAnswer(mine);
  }

  @override
  Stream<DailyQuestion?> watchTodayQuestion(String pairId) =>
      _watch(() => readTodayQuestion(pairId));

  @override
  Stream<List<DailyQuestion>> watchPastQuestions(String pairId) => _watch(() {
        final list = _sub('questions', pairId)
            .entries
            .where((e) => e.key != _today)
            .map((e) => DailyQuestion.fromJson(e.key, Map<String, dynamic>.from(e.value as Map)))
            .where((q) => q.revealed)
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        return list;
      });

  @override
  Future<void> submitAnswer(String text) async {
    answerQuestion(_pairId, _me, text.trim());
    _sim.onMyAnswer(_pairId);
  }

  /// `submitAnswer` function: private answer; reveal when both answered.
  void answerQuestion(String pairId, String uid, String text) {
    _ensureTodayQuestion(pairId);
    final q = _sub('questions', pairId)[_today] as Map<String, dynamic>;
    final priv = (_sub('privateAnswers', pairId)[_today] ??= <String, dynamic>{}) as Map<String, dynamic>;
    priv[uid] = text;
    final answeredBy = (q['answeredBy'] as List? ?? []).cast<String>().toSet()..add(uid);
    q['answeredBy'] = answeredBy.toList();
    final members = pairOf(pairId)?.memberIds ?? const [];
    if (members.isNotEmpty && members.every(answeredBy.contains) && q['revealed'] != true) {
      q
        ..['revealed'] = true
        ..['answers'] = Map<String, dynamic>.from(priv);
      final p = pairDoc(pairId)!;
      final s = PairStats.fromJson(Map<String, dynamic>.from(p['stats'] as Map? ?? {}));
      p['stats'] = PairStats(itemsSent: s.itemsSent, questionsAnswered: s.questionsAnswered + 1, tapsSent: s.tapsSent).toJson();
    }
    markActive(pairId, uid);
    _commit();
  }

  @override
  Future<void> setQuestionPack(String packId) async {
    final pairId = _pairId;
    if (packById(packId).plus && !_isPlus(pairId)) {
      throw const LimitReachedException('packs', 'This pack is part of Closer Plus');
    }
    _col('questionPack')[pairId] = packId;
    // Swap today's question if nobody answered yet.
    final q = _sub('questions', pairId)[_today] as Map?;
    if (q != null && (q['answeredBy'] as List? ?? []).isEmpty) {
      _sub('questions', pairId).remove(_today);
      _ensureTodayQuestion(pairId);
    }
    _commit();
  }

  // ----------------------------------------------------------- countdowns
  @override
  Stream<List<Countdown>> watchCountdowns(String pairId) => _watch(() {
        final list = _sub('countdowns', pairId)
            .entries
            .map((e) => Countdown.fromJson(e.key, Map<String, dynamic>.from(e.value as Map)))
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
        return list;
      });

  @override
  Future<void> saveCountdown(Countdown countdown) async {
    final c = putEvent(_pairId, _me, countdown);
    _sim.onMyEvent(c);
  }

  /// Calendar event write (the app's direct Firestore write).
  Countdown putEvent(String pairId, String uid, Countdown countdown) {
    checkEvent(countdown);
    final all = _sub('countdowns', pairId);
    final existing = countdown.id.isEmpty ? null : all[countdown.id] as Map?;
    final wasCountdown = existing != null && (existing['showAsCountdown'] as bool? ?? true);
    if (countdown.showAsCountdown && !wasCountdown && !_isPlus(pairId)) {
      final used = all.values.where((v) => (v as Map)['showAsCountdown'] as bool? ?? true).length;
      if (used >= FreeLimits.countdowns) {
        throw const LimitReachedException('countdowns', 'Free plan includes 3 countdowns');
      }
    }
    final id = countdown.id.isEmpty ? _uuid.v4() : countdown.id;
    final saved = Countdown(
      id: id,
      title: countdown.title.trim(),
      date: countdown.date,
      emoji: countdown.emoji,
      repeatsYearly: countdown.repeatsYearly,
      hasTime: countdown.hasTime,
      remindMinutesBefore: countdown.remindMinutesBefore,
      createdBy: existing?['createdBy'] as String? ?? (countdown.createdBy.isEmpty ? uid : countdown.createdBy),
      category: countdown.category,
      endDate: countdown.endDate,
      note: countdown.note.trim(),
      place: countdown.place.trim(),
      isVirtual: countdown.isVirtual,
      showAsCountdown: countdown.showAsCountdown,
      done: countdown.done,
      ratings: countdown.ratings,
    );
    all[id] = saved.toJson();
    _commit();
    return saved;
  }

  @override
  Future<void> rateDate(String eventId, int hearts) async => setDateRating(_pairId, _me, eventId, hearts);

  void setDateRating(String pairId, String uid, String eventId, int hearts) {
    final raw = _sub('countdowns', pairId)[eventId] as Map<String, dynamic>?;
    if (raw == null) throw const CloserException('That date is gone');
    final ratings = Map<String, dynamic>.from(raw['ratings'] as Map? ?? const {});
    ratings[uid] = hearts.clamp(1, 5);
    raw
      ..['ratings'] = ratings
      ..['done'] = true;
    markActive(pairId, uid);
    _commit();
  }

  @override
  Future<void> setDateGoal(DateGoal? goal) async {
    pairDoc(_pairId)!['dateGoal'] = goal?.toJson();
    _commit();
  }

  // --------------------------------------------------------------- to-dos
  @override
  Stream<List<TodoList>> watchTodoLists(String pairId) => _watch(() {
        final list = _sub('todoLists', pairId)
            .entries
            .map((e) => TodoList.fromJson(e.key, Map<String, dynamic>.from(e.value as Map)))
            .toList()
          ..sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
        return list;
      });

  @override
  Future<String> saveTodoList(TodoList list) async => putTodoList(_pairId, _me, list);

  String putTodoList(String pairId, String uid, TodoList list) {
    if (list.title.trim().isEmpty) throw const CloserException('Name the list');
    final all = _sub('todoLists', pairId);
    final id = list.id.isEmpty ? _uuid.v4() : list.id;
    final existing = all[id] as Map?;
    all[id] = TodoList(
      id: id,
      title: list.title.trim(),
      emoji: list.emoji,
      createdBy: existing?['createdBy'] as String? ?? uid,
      createdAt: DateTime.fromMillisecondsSinceEpoch(existing?['createdAt'] as int? ?? _now),
    ).toJson();
    _commit();
    return id;
  }

  @override
  Future<void> deleteTodoList(String id) async {
    final pairId = _pairId;
    _sub('todoLists', pairId).remove(id);
    _sub('todos', pairId).removeWhere((_, v) => (v as Map)['listId'] == id);
    _commit();
  }

  @override
  Stream<List<Todo>> watchTodos(String pairId) => _watch(() {
        final list = _sub('todos', pairId)
            .entries
            .map((e) => Todo.fromJson(e.key, Map<String, dynamic>.from(e.value as Map)))
            .toList()
          ..sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
        return list;
      });

  @override
  Future<void> saveTodo(Todo todo) async {
    final t = putTodo(_pairId, _me, todo);
    _sim.onMyTodo(t);
  }

  Todo putTodo(String pairId, String uid, Todo todo) {
    checkTodo(todo);
    final all = _sub('todos', pairId);
    final id = todo.id.isEmpty ? _uuid.v4() : todo.id;
    final existing = all[id] as Map?;
    final t = Todo(
      id: id,
      listId: todo.listId,
      text: todo.text.trim(),
      assignee: todo.assignee,
      due: todo.due,
      doneBy: existing?['doneBy'] as String?,
      doneAt: existing?['doneAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch(existing!['doneAt'] as int),
      createdBy: existing?['createdBy'] as String? ?? uid,
      createdAt: DateTime.fromMillisecondsSinceEpoch(existing?['createdAt'] as int? ?? _now),
    );
    all[id] = t.toJson();
    _commit();
    return t;
  }

  @override
  Future<void> setTodoDone(String id, {required bool done}) async => markTodo(_pairId, _me, id, done: done);

  void markTodo(String pairId, String uid, String id, {required bool done}) {
    final raw = _sub('todos', pairId)[id] as Map<String, dynamic>?;
    if (raw == null) return;
    raw
      ..['doneAt'] = done ? _now : null
      ..['doneBy'] = done ? uid : null;
    if (done) markActive(pairId, uid);
    _commit();
  }

  @override
  Future<void> deleteTodo(String id) async {
    _sub('todos', _pairId).remove(id);
    _commit();
  }

  // ------------------------------------------------------------- wishlist
  @override
  Stream<List<Wish>> watchWishes(String pairId) => _watch(() {
        final list = _sub('wishes', pairId)
            .entries
            .map((e) => Wish.fromJson(e.key, Map<String, dynamic>.from(e.value as Map)))
            .toList()
          ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
        return list;
      });

  @override
  Future<void> saveWish(Wish wish) async => putWish(_pairId, _me, wish);

  void putWish(String pairId, String uid, Wish wish) {
    checkWish(wish);
    final all = _sub('wishes', pairId);
    final id = wish.id.isEmpty ? _uuid.v4() : wish.id;
    final existing = all[id] as Map?;
    all[id] = Wish(
      id: id,
      title: wish.title.trim(),
      category: wish.category,
      note: wish.note.trim(),
      url: wish.url.trim(),
      price: wish.price.trim(),
      photoPath: wish.photoPath,
      ownerUid: wish.isGift ? (existing?['ownerUid'] as String? ?? uid) : null,
      createdBy: existing?['createdBy'] as String? ?? uid,
      doneAt: existing?['doneAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch(existing!['doneAt'] as int),
      createdAt: DateTime.fromMillisecondsSinceEpoch(existing?['createdAt'] as int? ?? _now),
    ).toJson();
    _commit();
  }

  @override
  Future<void> deleteWish(String id) async {
    final pairId = _pairId;
    _sub('wishes', pairId).remove(id);
    _sub('wishClaims', pairId).remove(id);
    _commit();
  }

  @override
  Future<void> setWishDone(String id, {required bool done}) async {
    final raw = _sub('wishes', _pairId)[id] as Map<String, dynamic>?;
    if (raw == null) return;
    raw['doneAt'] = done ? _now : null;
    _commit();
  }

  @override
  Stream<Set<String>> watchMyWishClaims(String pairId) => _watch(() {
        final uid = currentUid;
        return {
          for (final e in _sub('wishClaims', pairId).entries)
            if ((e.value as Map)['claimedBy'] == uid) e.key,
        };
      });

  @override
  Future<void> claimWish(String wishId, {required bool claim}) async {
    final pairId = _pairId;
    final wish = _sub('wishes', pairId)[wishId] as Map?;
    if (wish == null) throw const CloserException('That wish is gone');
    if (wish['ownerUid'] == _me) throw const CloserException('That’s your own wish 😄');
    final claims = _sub('wishClaims', pairId);
    if (claim) {
      final other = claims[wishId] as Map?;
      if (other != null && other['claimedBy'] != _me) throw const CloserException('Already taken care of');
      claims[wishId] = {'claimedBy': _me, 'claimedAt': _now};
    } else {
      claims.remove(wishId);
    }
    _commit();
  }

  @override
  Future<void> deleteCountdown(String id) async {
    _sub('countdowns', _pairId).remove(id);
    _commit();
  }

  // -------------------------------------------------------------- media
  @override
  Future<String> uploadPhoto(String localPath) async {
    final target = '${mediaDir.path}/photo_${_uuid.v4()}.jpg';
    final out = await FlutterImageCompress.compressAndGetFile(
      localPath,
      target,
      minWidth: 1600,
      minHeight: 1600,
      quality: 85,
    );
    if (out == null) await File(localPath).copy(target);
    return target;
  }

  // ------------------------------------------------------------ capsules
  @override
  Stream<List<Capsule>> watchCapsules(String pairId) => _watch(() {
        final list = _sub('capsules', pairId)
            .entries
            .map((e) => Capsule.fromJson(e.key, Map<String, dynamic>.from(e.value as Map)))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  @override
  Future<void> sendCapsule(Capsule envelope, CapsuleContent content) async {
    final c = writeCapsule(_pairId, _me, envelope, content);
    _sim.onMyCapsule(c);
  }

  /// Envelope + locked content (the app's batched write on Firebase).
  Capsule writeCapsule(String pairId, String authorId, Capsule env, CapsuleContent content) {
    final pair = pairOf(pairId);
    if (pair == null) throw const CloserException('You are not paired yet');
    final written = _sub('capsules', pairId).values.where((v) {
      final m = v as Map;
      return m['authorId'] == authorId && m['kind'] == CapsuleKind.reason.name;
    }).length;
    checkCapsule(env, content, reasonsWritten: written);
    final id = env.id.isEmpty ? _uuid.v4() : env.id;
    final c = Capsule(
      id: id,
      kind: env.kind,
      authorId: authorId,
      forUid: pair.partnerOf(authorId),
      title: env.title.trim(),
      surpriseType: env.surpriseType,
      createdAt: DateTime.now(),
      unlockAt: env.unlockAt,
    );
    _sub('capsules', pairId)[id] = c.toJson();
    _sub('capsuleContent', pairId)[id] = CapsuleContent(
      text: content.text.trim(),
      photoPath: content.photoPath,
      giftId: content.giftId,
    ).toJson();
    markActive(pairId, authorId);
    _commit();
    return c;
  }

  @override
  Future<CapsuleContent> openCapsule(Capsule capsule) async {
    final raw = _sub('capsuleContent', _pairId)[capsule.id];
    if (raw == null) throw const CloserException('This one is gone');
    if (capsule.authorId != _me && !capsule.isUnlocked(DateTime.now())) {
      throw const CloserException('Still sealed — no peeking! 🙈');
    }
    return CapsuleContent.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  @override
  Future<void> markCapsuleOpened(String capsuleId) async {
    final raw = _sub('capsules', _pairId)[capsuleId] as Map<String, dynamic>?;
    if (raw == null) return;
    final c = Capsule.fromJson(capsuleId, raw);
    if (c.forUid != _me || !c.isUnlocked(DateTime.now()) || c.openedAt != null) return;
    raw['openedAt'] = _now;
    _commit();
    _sim.onCapsuleOpened(c);
  }

  @override
  Future<void> deleteCapsule(String capsuleId) async {
    final pairId = _pairId;
    final raw = _sub('capsules', pairId)[capsuleId] as Map?;
    if (raw == null) return;
    if (raw['authorId'] != _me) throw const CloserException('Only the writer can delete this');
    _sub('capsules', pairId).remove(capsuleId);
    _sub('capsuleContent', pairId).remove(capsuleId);
    _commit();
  }

  // ------------------------------------------------------------ timeline
  @override
  Stream<List<TimelineEntry>> watchTimeline(String pairId) => _watch(() {
        final list = _sub('timeline', pairId)
            .entries
            .map((e) => TimelineEntry.fromJson(e.key, Map<String, dynamic>.from(e.value as Map)))
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
        return list;
      });

  @override
  Future<void> saveTimelineEntry(TimelineEntry entry) async {
    checkTimelineEntry(entry);
    final all = _sub('timeline', _pairId);
    final id = entry.id.isEmpty ? _uuid.v4() : entry.id;
    final existing = all[id] as Map?;
    all[id] = TimelineEntry(
      id: id,
      date: entry.date,
      title: entry.title.trim(),
      emoji: entry.emoji,
      note: entry.note.trim(),
      photoPath: entry.photoPath,
      createdBy: existing?['createdBy'] as String? ?? _me,
    ).toJson();
    _commit();
  }

  @override
  Future<void> deleteTimelineEntry(String id) async {
    _sub('timeline', _pairId).remove(id);
    _commit();
  }

  // -------------------------------------------------------------- shrine
  @override
  Stream<Map<String, Shrine>> watchShrines(String pairId) => _watch(
        () => {
          for (final e in _sub('shrines', pairId).entries)
            e.key: Shrine.fromJson(e.key, Map<String, dynamic>.from(e.value as Map)),
        },
      );

  @override
  Future<void> saveShrine(Shrine shrine) async => putShrine(_pairId, _me, shrine);

  void putShrine(String pairId, String ownerUid, Shrine shrine) {
    final clean = clampShrine(shrine);
    _sub('shrines', pairId)[ownerUid] = {...clean.toJson(), 'updatedAt': _now};
    _commit();
  }

  // ----------------------------------------------------------------- chat
  @override
  Stream<List<ChatMessage>> watchMessages(String pairId, {int limit = 300}) => _watch(() {
        final list = _sub('messages', pairId)
            .entries
            .map((e) => ChatMessage.fromJson(e.key, Map<String, dynamic>.from(e.value as Map)))
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        return list.length > limit ? list.sublist(list.length - limit) : list;
      });

  @override
  Future<void> sendMessage(ChatDraft draft) async {
    checkMessage(draft);
    final pairId = _pairId;
    String? media;
    final path = draft.localPath;
    if (path != null) media = draft.type == MessageType.photo ? await uploadPhoto(path) : await uploadAudio(path);
    final m = writeMessage(pairId, _me, draft, mediaPath: media);
    _sim.onMyMessage(m);
  }

  ChatMessage writeMessage(String pairId, String uid, ChatDraft draft, {String? mediaPath}) {
    final m = ChatMessage(
      id: _uuid.v4(),
      senderId: uid,
      type: draft.type,
      text: draft.text.trim(),
      mediaPath: mediaPath,
      durationMs: draft.durationMs,
      replyTo: draft.replyTo,
      createdAt: DateTime.now(),
    );
    _sub('messages', pairId)[m.id] = m.toJson();
    // Sending also counts as reading.
    (_sub('chatState', pairId)[uid] ??= <String, dynamic>{}) as Map<String, dynamic>
      ..['readAt'] = _now
      ..['typingUntil'] = null;
    markActive(pairId, uid);
    _commit();
    return m;
  }

  @override
  Future<void> reactToMessage(String messageId, String? emoji) async => setMessageReaction(_pairId, _me, messageId, emoji);

  void setMessageReaction(String pairId, String uid, String messageId, String? emoji) {
    final raw = _sub('messages', pairId)[messageId] as Map<String, dynamic>?;
    if (raw == null) return;
    final r = Map<String, dynamic>.from(raw['reactions'] as Map? ?? const {});
    if (emoji == null) {
      r.remove(uid);
    } else {
      r[uid] = emoji;
    }
    raw['reactions'] = r;
    _commit();
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    final raw = _sub('messages', _pairId)[messageId] as Map<String, dynamic>?;
    if (raw == null) return;
    if (raw['senderId'] != _me) throw const CloserException('You can only delete your own messages');
    raw
      ..['text'] = ''
      ..['mediaPath'] = null
      ..['deletedAt'] = _now;
    _commit();
  }

  @override
  Stream<Map<String, ChatState>> watchChatState(String pairId) => _watch(
        () => {
          for (final e in _sub('chatState', pairId).entries)
            e.key: ChatState.fromJson(Map<String, dynamic>.from(e.value as Map)),
        },
      );

  @override
  Future<void> markChatRead() async {
    final pairId = myPairId;
    final uid = currentUid;
    if (pairId == null || uid == null) return;
    final state = (_sub('chatState', pairId)[uid] ??= <String, dynamic>{}) as Map<String, dynamic>;
    state['readAt'] = _now;
    _commit();
  }

  void markChatReadFor(String pairId, String uid) {
    final state = (_sub('chatState', pairId)[uid] ??= <String, dynamic>{}) as Map<String, dynamic>;
    state['readAt'] = _now;
    _commit();
  }

  @override
  Future<void> setTyping({required bool typing}) async => setTypingFor(_pairId, _me, typing: typing);

  void setTypingFor(String pairId, String uid, {required bool typing}) {
    final state = (_sub('chatState', pairId)[uid] ??= <String, dynamic>{}) as Map<String, dynamic>;
    state['typingUntil'] = typing ? _now + 6000 : null;
    _commit();
  }

  @override
  Future<String> uploadAudio(String localPath) async {
    final ext = localPath.contains('.') ? localPath.substring(localPath.lastIndexOf('.')) : '.m4a';
    final target = '${mediaDir.path}/voice_${_uuid.v4()}$ext';
    await File(localPath).copy(target);
    return target;
  }

  // ------------------------------------------------------------ goodnight
  @override
  Stream<List<Goodnight>> watchGoodnights(String pairId) => _watch(() {
        final list = _sub('goodnights', pairId)
            .entries
            .map((e) => Goodnight.fromJson(e.key, Map<String, dynamic>.from(e.value as Map)))
            .toList()
          ..sort((a, b) => b.night.compareTo(a.night));
        return list.take(30).toList();
      });

  @override
  Future<void> sendGoodnight(GoodnightEntry entry) async {
    checkGoodnight(entry);
    final pairId = _pairId;
    final photo = entry.momentPhotoPath == null ? null : await uploadPhoto(entry.momentPhotoPath!);
    final voice = entry.voicePath == null ? null : await uploadAudio(entry.voicePath!);
    writeGoodnight(
      pairId,
      _me,
      GoodnightEntry(
        message: entry.message.trim(),
        moment: entry.moment.trim(),
        momentPhotoPath: photo,
        voicePath: voice,
        voiceMs: entry.voiceMs,
        kiss: entry.kiss,
      ),
    );
    _sim.onMyGoodnight(pairId);
  }

  void writeGoodnight(String pairId, String uid, GoodnightEntry entry) {
    final night = Goodnight.keyFor(DateTime.now());
    final doc = (_sub('goodnights', pairId)[night] ??= <String, dynamic>{'entries': <String, dynamic>{}}) as Map<String, dynamic>;
    final entries = Map<String, dynamic>.from(doc['entries'] as Map? ?? const {});
    entries[uid] = {...entry.toJson(), 'sentAt': _now};
    doc['entries'] = entries;
    markActive(pairId, uid);
    _commit();
  }

  Goodnight? readTonight(String pairId) {
    final night = Goodnight.keyFor(DateTime.now());
    final raw = _sub('goodnights', pairId)[night];
    return raw == null ? null : Goodnight.fromJson(night, Map<String, dynamic>.from(raw as Map));
  }

  // ------------------------------------------------------------ pet & home
  @override
  Future<void> savePet(Pet pet) async {
    final pairId = _pairId;
    checkPet(pet, pairOf(pairId)!);
    putPet(pairId, Pet(species: pet.species, name: pet.name.trim(), hatchedAt: pet.hatchedAt, lastFed: pet.lastFed, lastPlayed: pet.lastPlayed));
    _sim.onPetChanged(pairId);
  }

  void putPet(String pairId, Pet pet) {
    pairDoc(pairId)!['pet'] = pet.toJson();
    _commit();
  }

  @override
  Future<void> careForPet(String action) async => petCare(_pairId, _me, action);

  void petCare(String pairId, String uid, String action) {
    final pet = pairOf(pairId)?.pet;
    if (pet == null) throw const CloserException('Hatch your pet first');
    final now = DateTime.now();
    putPet(
      pairId,
      action == 'feed'
          ? pet.copyWith(lastFed: {...pet.lastFed, uid: now})
          : pet.copyWith(lastPlayed: {...pet.lastPlayed, uid: now}),
    );
  }

  @override
  Future<void> saveHome(PetHome home) async {
    final pairId = _pairId;
    final pair = pairOf(pairId)!;
    checkHome(pair.home, home, pair);
    pairDoc(pairId)!['home'] = home.toJson();
    _commit();
  }

  // -------------------------------------------------------------- insights
  @override
  Stream<List<MoodEntry>> watchMoodLog(String pairId) => _watch(() {
        final list = _sub('moodLog', pairId).values.map((v) => MoodEntry.fromJson(Map<String, dynamic>.from(v as Map))).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        return list.take(200).toList();
      });

  // ---------------------------------------------------------------- games
  @override
  Stream<List<Game>> watchGames(String pairId) => _watch(() {
        final list = _sub('games', pairId)
            .entries
            .map((e) => Game.fromJson(e.key, Map<String, dynamic>.from(e.value as Map)))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  Game? readGame(String pairId, String gameId) {
    final raw = _sub('games', pairId)[gameId];
    return raw == null ? null : Game.fromJson(gameId, Map<String, dynamic>.from(raw as Map));
  }

  @override
  Future<Game> startGame({String packId = 'starter'}) async =>
      createGame(_pairId, _me, packId: packId);

  Game createGame(String pairId, String subjectUid, {String packId = 'starter'}) {
    final pool = [...knowMeQuestions]..shuffle(_rand);
    final game = Game(
      id: _uuid.v4(),
      packId: packId,
      subjectUid: subjectUid,
      guesserUid: pairOf(pairId)!.partnerOf(subjectUid),
      questions: pool.take(5).toList(),
      createdAt: DateTime.now(),
    );
    _sub('games', pairId)[game.id] = game.toJson();
    _commit();
    return game;
  }

  @override
  Future<void> submitGameAnswers(String gameId, List<int> answers) async {
    final pairId = _pairId;
    applyGameAnswers(pairId, gameId, _me, answers);
    _sim.onMyGameMove(pairId, gameId);
  }

  void applyGameAnswers(String pairId, String gameId, String uid, List<int> answers) {
    final raw = _sub('games', pairId)[gameId] as Map<String, dynamic>?;
    if (raw == null) throw const CloserException('Game not found');
    final game = Game.fromJson(gameId, raw);
    final ans = Map<String, dynamic>.from(raw['answers'] as Map? ?? {});
    if (game.status == GameStatus.subjectTurn && uid == game.subjectUid) {
      ans['subject'] = answers;
      raw['status'] = GameStatus.guesserTurn.name;
    } else if (game.status == GameStatus.guesserTurn && uid == game.guesserUid) {
      ans['guesser'] = answers;
      raw['status'] = GameStatus.done.name;
    } else {
      throw const CloserException("It's not your turn");
    }
    raw['answers'] = ans;
    raw['score'] = Game.fromJson(gameId, raw).score;
    markActive(pairId, uid);
    _commit();
  }

  // --------------------------------------------------- themes & premium
  @override
  Future<void> setWidgetTheme(String themeId) async {
    final p = pairDoc(_pairId)!;
    final themes = Map<String, dynamic>.from(p['widgetTheme'] as Map? ?? const {});
    themes[_me] = themeId;
    p['widgetTheme'] = themes;
    _commit();
  }

  @override
  Future<void> debugSetPremium({required bool active}) async {
    pairDoc(_pairId)!['premium'] = Premium(
      active: active,
      ownerUid: active ? _me : null,
      expiresAt: active ? DateTime.now().add(const Duration(days: 30)) : null,
    ).toJson();
    _commit();
  }

  @override
  Future<void> registerDevice() async {}

  // ----------------------------------------------------- streak + plant
  /// Marks [uid] active today; when both members are active the streak
  /// grows and the plant may grow a stage (markActivity function).
  void markActive(String pairId, String uid) {
    final p = pairDoc(pairId);
    if (p == null) return;
    final r = StreakRules.markActive(
      Streak.fromJson(Map<String, dynamic>.from(p['streak'] as Map? ?? {})),
      Plant.fromJson(Map<String, dynamic>.from(p['plant'] as Map? ?? {})),
      uid,
      (p['memberIds'] as List).cast<String>(),
      _today,
      plus: _isPlus(pairId),
    );
    p
      ..['streak'] = r.streak.toJson()
      ..['plant'] = r.plant.toJson();
  }

  /// Settles finished days for every pair (updateStreaks function): spends
  /// freezes on missed days or breaks the streak, refills monthly freezes.
  void _rollDay() {
    final today = _today;
    if (_db['lastDay'] == today) return;
    for (final e in _col('pairs').entries) {
      final p = e.value as Map<String, dynamic>;
      final r = StreakRules.settle(
        Streak.fromJson(Map<String, dynamic>.from(p['streak'] as Map? ?? {})),
        Plant.fromJson(Map<String, dynamic>.from(p['plant'] as Map? ?? {})),
        today,
        plus: _isPlus(e.key),
      );
      p
        ..['streak'] = r.streak.toJson()
        ..['plant'] = r.plant.toJson();
      _ensureTodayQuestion(e.key);
    }
    _db['lastDay'] = today;
    _commit();
  }

  // ------------------------------------------------- simulator plumbing
  void putUser(AppUser user) {
    _col('users')[user.uid] = user.toJson();
    _commit();
  }

  void patchUser(String uid, Map<String, dynamic> patch) {
    userDoc(uid)?.addAll(patch);
    _commit();
  }

  Map<String, dynamic> get simState => _col('sim');

  Map<String, dynamic> simStateCapsules(String pairId) => _sub('capsules', pairId);

  void commit() => _commit();

  void dispose() {
    _dayTimer?.cancel();
    _sim.dispose();
    unawaited(_changes.close());
  }
}

