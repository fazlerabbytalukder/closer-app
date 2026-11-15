// Core data models for Closer.
//
// These mirror the Firestore data model in the design plan (section 6).
// They are hand-written immutable classes with fromJson/toJson so they work
// identically for the local on-device backend and the Firebase backend.
// Dates are serialised as milliseconds since epoch (int).

import 'package:flutter/foundation.dart';

DateTime? _date(Object? v) {
  if (v == null) return null;
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is String) return DateTime.tryParse(v);
  // Firestore Timestamp (duck-typed so models stay Firebase-free).
  try {
    return (v as dynamic).toDate() as DateTime;
  } on Object {
    return null;
  }
}

int? _ms(DateTime? d) => d?.millisecondsSinceEpoch;

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

enum PairMode {
  couple,
  friends;

  static PairMode parse(Object? v) =>
      v == 'friends' ? PairMode.friends : PairMode.couple;
}

/// What one person calls the other ("my girlfriend", "my best friend").
/// Each member picks their own label for the partner.
@immutable
class RelationLabel {
  const RelationLabel(this.id, this.title, this.emoji, this.mode);

  final String id;
  final String title;
  final String emoji;
  final PairMode mode;

  static const all = <RelationLabel>[
    RelationLabel('girlfriend', 'Girlfriend', '💕', PairMode.couple),
    RelationLabel('boyfriend', 'Boyfriend', '💙', PairMode.couple),
    RelationLabel('partner', 'Partner', '💞', PairMode.couple),
    RelationLabel('wife', 'Wife', '💍', PairMode.couple),
    RelationLabel('husband', 'Husband', '💍', PairMode.couple),
    RelationLabel('fiance', 'Fiancé(e)', '💎', PairMode.couple),
    RelationLabel('best_friend', 'Best friend', '👯', PairMode.friends),
    RelationLabel('bff', 'BFF', '✨', PairMode.friends),
    RelationLabel('bestie', 'Bestie', '🫶', PairMode.friends),
    RelationLabel('sibling', 'Sibling', '🧡', PairMode.friends),
  ];

  static List<RelationLabel> forMode(PairMode mode) =>
      all.where((l) => l.mode == mode).toList();

  static RelationLabel? byId(String? id) {
    for (final l in all) {
      if (l.id == id) return l;
    }
    return null;
  }

  /// A label only makes sense for its own mode (a "girlfriend" in a
  /// best-friends pair is dropped).
  static String? validFor(String? id, PairMode mode) {
    final l = byId(id);
    return l != null && l.mode == mode ? l.id : null;
  }
}

enum ItemType {
  photo,
  note,
  doodle,

  /// Camera photo stamped with where it was taken (see [GeoTag]).
  location;

  static ItemType parse(Object? v) =>
      ItemType.values.firstWhere((t) => t.name == v, orElse: () => photo);
}

@immutable
class Mood {
  const Mood({required this.emoji, required this.label, required this.updatedAt});

  factory Mood.fromJson(Map<String, dynamic> j) => Mood(
        emoji: j['emoji'] as String? ?? '🙂',
        label: j['label'] as String? ?? '',
        updatedAt: _date(j['updatedAt']) ?? DateTime.now(),
      );

  final String emoji;
  final String label;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() =>
      {'emoji': emoji, 'label': label, 'updatedAt': _ms(updatedAt)};
}

@immutable
class StatusText {
  const StatusText({required this.text, required this.updatedAt});

  factory StatusText.fromJson(Map<String, dynamic> j) => StatusText(
        text: j['text'] as String? ?? '',
        updatedAt: _date(j['updatedAt']) ?? DateTime.now(),
      );

  final String text;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {'text': text, 'updatedAt': _ms(updatedAt)};
}

@immutable
class NotificationPrefs {
  const NotificationPrefs({
    this.taps = true,
    this.questions = true,
    this.reminders = true,
    this.chat = true,
    this.quietStart,
    this.quietEnd,
  });

  factory NotificationPrefs.fromJson(Map<String, dynamic> j) {
    final quiet = _map(j['quietHours']);
    return NotificationPrefs(
      taps: j['taps'] as bool? ?? true,
      questions: j['questions'] as bool? ?? true,
      reminders: j['reminders'] as bool? ?? true,
      chat: j['chat'] as bool? ?? true,
      quietStart: quiet['start'] as int?,
      quietEnd: quiet['end'] as int?,
    );
  }

  final bool taps;
  final bool questions;
  final bool reminders;

  /// Chat messages and goodnights.
  final bool chat;

  /// Quiet hours as hour-of-day (0-23), both null when disabled.
  final int? quietStart;
  final int? quietEnd;

  NotificationPrefs copyWith({
    bool? taps,
    bool? questions,
    bool? reminders,
    bool? chat,
    int? Function()? quietStart,
    int? Function()? quietEnd,
  }) =>
      NotificationPrefs(
        taps: taps ?? this.taps,
        questions: questions ?? this.questions,
        reminders: reminders ?? this.reminders,
        chat: chat ?? this.chat,
        quietStart: quietStart != null ? quietStart() : this.quietStart,
        quietEnd: quietEnd != null ? quietEnd() : this.quietEnd,
      );

  Map<String, dynamic> toJson() => {
        'taps': taps,
        'questions': questions,
        'reminders': reminders,
        'chat': chat,
        'quietHours': {'start': quietStart, 'end': quietEnd},
      };
}

@immutable
class AppUser {
  const AppUser({
    required this.uid,
    required this.displayName,
    required this.createdAt,
    this.photoUrl,
    this.pairId,
    this.mood,
    this.status,
    this.ageConfirmed18 = false,
    this.notificationPrefs = const NotificationPrefs(),
    this.locale = 'en',
    this.timezone = 'UTC',
    this.pendingMode,
    this.pendingLabel,
  });

  factory AppUser.fromJson(String uid, Map<String, dynamic> j) => AppUser(
        uid: uid,
        displayName: j['displayName'] as String? ?? '',
        photoUrl: j['photoUrl'] as String?,
        pairId: j['pairId'] as String?,
        mood: j['mood'] == null ? null : Mood.fromJson(_map(j['mood'])),
        status:
            j['status'] == null ? null : StatusText.fromJson(_map(j['status'])),
        ageConfirmed18: j['ageConfirmed18'] as bool? ?? false,
        notificationPrefs:
            NotificationPrefs.fromJson(_map(j['notificationPrefs'])),
        locale: j['locale'] as String? ?? 'en',
        timezone: j['timezone'] as String? ?? 'UTC',
        pendingMode:
            j['pendingMode'] == null ? null : PairMode.parse(j['pendingMode']),
        pendingLabel: j['pendingLabel'] as String?,
        createdAt: _date(j['createdAt']) ?? DateTime.now(),
      );

  final String uid;
  final String displayName;

  /// Remote URL (Firebase) or local file path (local backend).
  final String? photoUrl;
  final String? pairId;
  final Mood? mood;
  final StatusText? status;
  final bool ageConfirmed18;
  final NotificationPrefs notificationPrefs;
  final String locale;
  final String timezone;

  /// Mode chosen during onboarding, before the pair exists.
  final PairMode? pendingMode;

  /// [RelationLabel] id chosen during onboarding ("they are my …"), copied
  /// into [Pair.relationLabels] when the pair is created.
  final String? pendingLabel;
  final DateTime createdAt;

  bool get hasProfile => displayName.trim().isNotEmpty;
  bool get isPaired => pairId != null;

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'photoUrl': photoUrl,
        'pairId': pairId,
        'mood': mood?.toJson(),
        'status': status?.toJson(),
        'ageConfirmed18': ageConfirmed18,
        'notificationPrefs': notificationPrefs.toJson(),
        'locale': locale,
        'timezone': timezone,
        'pendingMode': pendingMode?.name,
        'pendingLabel': pendingLabel,
        'createdAt': _ms(createdAt),
      };
}

@immutable
class Invite {
  const Invite({
    required this.code,
    required this.inviterUid,
    required this.mode,
    required this.expiresAt,
    this.usedBy,
  });

  factory Invite.fromJson(String code, Map<String, dynamic> j) => Invite(
        code: code,
        inviterUid: j['inviterUid'] as String? ?? '',
        mode: PairMode.parse(j['mode']),
        expiresAt: _date(j['expiresAt']) ?? DateTime.now(),
        usedBy: j['usedBy'] as String?,
      );

  final String code;
  final String inviterUid;
  final PairMode mode;
  final DateTime expiresAt;
  final String? usedBy;

  /// Public invite link (Android App Link on our own domain).
  String get link => 'https://closer.app/i/$code';

  Map<String, dynamic> toJson() => {
        'inviterUid': inviterUid,
        'mode': mode.name,
        'expiresAt': _ms(expiresAt),
        'usedBy': usedBy,
      };
}

@immutable
class LatestItem {
  const LatestItem({
    required this.itemId,
    required this.type,
    required this.sentAt,
    this.thumbPath,
    this.caption = '',
    this.secret = false,
  });

  factory LatestItem.fromJson(Map<String, dynamic> j) => LatestItem(
        itemId: j['itemId'] as String? ?? '',
        type: ItemType.parse(j['type']),
        thumbPath: j['thumbPath'] as String?,
        caption: j['caption'] as String? ?? '',
        secret: j['secret'] as bool? ?? false,
        sentAt: _date(j['sentAt']) ?? DateTime.now(),
      );

  final String itemId;
  final ItemType type;
  final String? thumbPath;
  final String caption;

  /// Sent by a secret admirer and not revealed yet.
  final bool secret;
  final DateTime sentAt;

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'type': type.name,
        'thumbPath': thumbPath,
        'caption': caption,
        'secret': secret,
        'sentAt': _ms(sentAt),
      };
}

@immutable
class Streak {
  const Streak({
    this.count = 0,
    this.best = 0,
    this.lastBothActiveDate,
    this.freezesLeft = 1,
    this.freezesMonth,
    this.activeToday = const [],
    this.activeDate,
    this.checkedThrough,
    this.lastFrozeDate,
    this.lostCount = 0,
    this.brokeDate,
  });

  factory Streak.fromJson(Map<String, dynamic> j) => Streak(
        count: j['count'] as int? ?? 0,
        best: j['best'] as int? ?? 0,
        lastBothActiveDate: j['lastBothActiveDate'] as String?,
        freezesLeft: j['freezesLeft'] as int? ?? 1,
        freezesMonth: j['freezesMonth'] as String?,
        activeToday: (j['activeToday'] as List?)?.cast<String>() ?? const [],
        activeDate: j['activeDate'] as String?,
        checkedThrough: j['checkedThrough'] as String?,
        lastFrozeDate: j['lastFrozeDate'] as String?,
        lostCount: j['lostCount'] as int? ?? 0,
        brokeDate: j['brokeDate'] as String?,
      );

  /// Freezes granted each month (they don't carry over).
  static int monthlyFreezes({required bool plus}) => plus ? 3 : 1;

  final int count;
  final int best;

  /// yyyy-mm-dd in the pair's timezone.
  final String? lastBothActiveDate;
  final int freezesLeft;

  /// yyyy-mm the freezes were last refilled.
  final String? freezesMonth;

  /// Member uids who interacted on [activeDate].
  final List<String> activeToday;

  /// The day [activeToday] belongs to. Older docs may not have it.
  final String? activeDate;

  /// Last finished day the rules have settled (yyyy-mm-dd).
  final String? checkedThrough;

  /// Most recent missed day a freeze covered.
  final String? lastFrozeDate;

  /// Length of the streak that last broke, and the day it broke.
  final int lostCount;
  final String? brokeDate;

  /// Who has shown up on [today]; empty if [activeToday] is from another day.
  List<String> activeOn(String today) => activeDate == null || activeDate == today ? activeToday : const [];

  bool bothActiveOn(String today) => lastBothActiveDate == today;

  /// Full years of daily streak ("blooms") after the plant is fully grown.
  int get years => count ~/ 365;

  Streak copyWith({
    int? count,
    int? best,
    String? lastBothActiveDate,
    int? freezesLeft,
    String? freezesMonth,
    List<String>? activeToday,
    String? activeDate,
    String? checkedThrough,
    String? lastFrozeDate,
    int? lostCount,
    String? brokeDate,
  }) =>
      Streak(
        count: count ?? this.count,
        best: best ?? this.best,
        lastBothActiveDate: lastBothActiveDate ?? this.lastBothActiveDate,
        freezesLeft: freezesLeft ?? this.freezesLeft,
        freezesMonth: freezesMonth ?? this.freezesMonth,
        activeToday: activeToday ?? this.activeToday,
        activeDate: activeDate ?? this.activeDate,
        checkedThrough: checkedThrough ?? this.checkedThrough,
        lastFrozeDate: lastFrozeDate ?? this.lastFrozeDate,
        lostCount: lostCount ?? this.lostCount,
        brokeDate: brokeDate ?? this.brokeDate,
      );

  Map<String, dynamic> toJson() => {
        'count': count,
        'best': best,
        'lastBothActiveDate': lastBothActiveDate,
        'freezesLeft': freezesLeft,
        'freezesMonth': freezesMonth,
        'activeToday': activeToday,
        'activeDate': activeDate,
        'checkedThrough': checkedThrough,
        'lastFrozeDate': lastFrozeDate,
        'lostCount': lostCount,
        'brokeDate': brokeDate,
      };
}

enum PlantHealth {
  healthy,
  wilted;

  static PlantHealth parse(Object? v) =>
      v == 'wilted' ? PlantHealth.wilted : PlantHealth.healthy;
}

@immutable
class Plant {
  const Plant({
    this.stage = 0,
    this.health = PlantHealth.healthy,
    this.species = 'sprout',
  });

  factory Plant.fromJson(Map<String, dynamic> j) => Plant(
        stage: j['stage'] as int? ?? 0,
        health: PlantHealth.parse(j['health']),
        species: j['species'] as String? ?? 'sprout',
      );

  /// Streak milestones at which the plant grows one stage (plan F8).
  static const milestones = [1, 3, 7, 14, 30, 60, 100, 365];
  static const maxStage = 8;

  static int stageForStreak(int streak) =>
      milestones.where((m) => streak >= m).length;

  /// Stage names shown under the plant.
  static const stageNames = [
    'Seed',
    'Sprout',
    'Seedling',
    'Young plant',
    'Growing plant',
    'Leafy plant',
    'Budding plant',
    'Flowering plant',
    'Full bloom',
  ];

  final int stage;
  final PlantHealth health;
  final String species;

  bool get fullyGrown => stage >= maxStage;

  /// Streak length needed for the next stage. The plant never shrinks, so
  /// after a break it grows again only once the streak passes the milestone
  /// of its current stage. Null when fully grown.
  int? get nextGrowthAt => fullyGrown ? null : milestones[stage];

  Map<String, dynamic> toJson() =>
      {'stage': stage, 'health': health.name, 'species': species};
}

@immutable
class Premium {
  const Premium({this.active = false, this.ownerUid, this.expiresAt});

  factory Premium.fromJson(Map<String, dynamic> j) => Premium(
        active: j['active'] as bool? ?? false,
        ownerUid: j['ownerUid'] as String?,
        expiresAt: _date(j['expiresAt']),
      );

  final bool active;
  final String? ownerUid;
  final DateTime? expiresAt;

  Map<String, dynamic> toJson() => {
        'active': active,
        'source': 'subscription',
        'ownerUid': ownerUid,
        'expiresAt': _ms(expiresAt),
      };
}

@immutable
class PairStats {
  const PairStats({
    this.itemsSent = 0,
    this.questionsAnswered = 0,
    this.tapsSent = 0,
  });

  factory PairStats.fromJson(Map<String, dynamic> j) => PairStats(
        itemsSent: j['itemsSent'] as int? ?? 0,
        questionsAnswered: j['questionsAnswered'] as int? ?? 0,
        tapsSent: j['tapsSent'] as int? ?? 0,
      );

  final int itemsSent;
  final int questionsAnswered;
  final int tapsSent;

  Map<String, dynamic> toJson() => {
        'itemsSent': itemsSent,
        'questionsAnswered': questionsAnswered,
        'tapsSent': tapsSent,
      };
}

@immutable
class Pair {
  const Pair({
    required this.id,
    required this.memberIds,
    required this.mode,
    required this.pairedAt,
    this.latestItemByUser = const {},
    this.streak = const Streak(),
    this.plant = const Plant(),
    this.premium = const Premium(),
    this.widgetTheme = const {},
    this.stats = const PairStats(),
    this.timezone = 'UTC',
    this.anniversary,
    this.relationLabels = const {},
    this.nicknames = const {},
    this.lastMetAt,
    this.dateGoal,
    this.pet,
    this.home = const PetHome(),
  });

  factory Pair.fromJson(String id, Map<String, dynamic> j) => Pair(
        id: id,
        memberIds: (j['memberIds'] as List?)?.cast<String>() ?? const [],
        mode: PairMode.parse(j['mode']),
        pairedAt: _date(j['pairedAt']) ?? DateTime.now(),
        latestItemByUser: _map(j['latestItemByUser']).map(
          (k, v) => MapEntry(k, LatestItem.fromJson(_map(v))),
        ),
        streak: Streak.fromJson(_map(j['streak'])),
        plant: Plant.fromJson(_map(j['plant'])),
        premium: Premium.fromJson(_map(j['premium'])),
        widgetTheme: _map(j['widgetTheme']).cast<String, String>(),
        stats: PairStats.fromJson(_map(j['stats'])),
        timezone: j['timezone'] as String? ?? 'UTC',
        anniversary: _date(j['anniversary']),
        relationLabels: _map(j['relationLabels']).cast<String, String>(),
        nicknames: _map(j['nicknames']).cast<String, String>(),
        lastMetAt: _date(j['lastMetAt']),
        dateGoal: j['dateGoal'] == null ? null : DateGoal.fromJson(_map(j['dateGoal'])),
        pet: j['pet'] == null ? null : Pet.fromJson(_map(j['pet'])),
        home: PetHome.fromJson(_map(j['home'])),
      );

  final String id;
  final List<String> memberIds;
  final PairMode mode;
  final DateTime pairedAt;
  final Map<String, LatestItem> latestItemByUser;
  final Streak streak;
  final Plant plant;
  final Premium premium;
  final Map<String, String> widgetTheme;
  final PairStats stats;
  final String timezone;

  /// "Together since" (couples) / "Friends since" date, set by either member.
  final DateTime? anniversary;

  /// uid → [RelationLabel] id: what that member calls their partner.
  final Map<String, String> relationLabels;

  /// uid → the nickname that member uses for their partner ("Babe").
  final Map<String, String> nicknames;

  /// When the two last saw each other in person (set by either member,
  /// shown on the "Always with me" widget).
  final DateTime? lastMetAt;

  /// "2 dates a month" — shared, set by either member.
  final DateGoal? dateGoal;

  /// The pet that hatched from your plant (null until it hatches).
  final Pet? pet;

  /// The pet's shared home: wallpaper, decorations, love points spent.
  final PetHome home;

  /// Love points earned so far, from the server-written stats, the best
  /// streak and the plant (so they can't be made up on the device).
  int get lovePointsEarned =>
      stats.itemsSent * 3 + stats.tapsSent + stats.questionsAnswered * 5 + streak.best * 10 + plant.stage * 25;

  int get lovePoints => (lovePointsEarned - home.spent).clamp(0, 1 << 30);

  String partnerOf(String uid) =>
      memberIds.firstWhere((m) => m != uid, orElse: () => '');

  /// What [uid] calls their partner, valid for the current mode.
  RelationLabel? labelBy(String uid) =>
      RelationLabel.byId(RelationLabel.validFor(relationLabels[uid], mode));

  /// Whole days since [anniversary] (null when not set).
  int? daysTogether(DateTime now) {
    final a = anniversary;
    if (a == null) return null;
    final start = DateTime(a.year, a.month, a.day);
    final today = DateTime(now.year, now.month, now.day);
    return today.difference(start).inDays;
  }

  Map<String, dynamic> toJson() => {
        'memberIds': memberIds,
        'mode': mode.name,
        'pairedAt': _ms(pairedAt),
        'latestItemByUser':
            latestItemByUser.map((k, v) => MapEntry(k, v.toJson())),
        'streak': streak.toJson(),
        'plant': plant.toJson(),
        'premium': premium.toJson(),
        'widgetTheme': widgetTheme,
        'stats': stats.toJson(),
        'timezone': timezone,
        'anniversary': _ms(anniversary),
        'relationLabels': relationLabels,
        'nicknames': nicknames,
        'lastMetAt': _ms(lastMetAt),
        'dateGoal': dateGoal?.toJson(),
        'pet': pet?.toJson(),
        'home': home.toJson(),
      };
}

/// Where a location item was taken. [place] is a human-readable name from
/// reverse geocoding (may be empty when offline).
@immutable
class GeoTag {
  const GeoTag({required this.lat, required this.lng, this.place = ''});

  factory GeoTag.fromJson(Map<String, dynamic> j) => GeoTag(
        lat: (j['lat'] as num?)?.toDouble() ?? 0,
        lng: (j['lng'] as num?)?.toDouble() ?? 0,
        place: j['place'] as String? ?? '',
      );

  static const maxPlace = 80;

  final double lat;
  final double lng;
  final String place;

  /// e.g. "23.81032° N, 90.41254° E".
  String get coords =>
      '${lat.abs().toStringAsFixed(5)}° ${lat >= 0 ? 'N' : 'S'}, '
      '${lng.abs().toStringAsFixed(5)}° ${lng >= 0 ? 'E' : 'W'}';

  Uri get mapsUri => Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'place': place};
}

@immutable
class NoteStyle {
  const NoteStyle({required this.bg, required this.font});

  factory NoteStyle.fromJson(Map<String, dynamic> j) => NoteStyle(
        bg: j['bg'] as String? ?? 'blush',
        font: j['font'] as String? ?? 'rounded',
      );

  final String bg;
  final String font;

  Map<String, dynamic> toJson() => {'bg': bg, 'font': font};
}

@immutable
class Item {
  const Item({
    required this.id,
    required this.type,
    required this.senderId,
    required this.createdAt,
    this.storagePath,
    this.thumbPath,
    this.caption = '',
    this.text,
    this.noteStyle,
    this.geo,
    this.saveToMemories = true,
    this.reactions = const {},
    this.secret = false,
    this.revealedAt,
  });

  factory Item.fromJson(String id, Map<String, dynamic> j) => Item(
        id: id,
        type: ItemType.parse(j['type']),
        senderId: j['senderId'] as String? ?? '',
        storagePath: j['storagePath'] as String?,
        thumbPath: j['thumbPath'] as String?,
        caption: j['caption'] as String? ?? '',
        text: j['text'] as String?,
        noteStyle: j['noteStyle'] == null
            ? null
            : NoteStyle.fromJson(_map(j['noteStyle'])),
        geo: j['geo'] == null ? null : GeoTag.fromJson(_map(j['geo'])),
        saveToMemories: j['saveToMemories'] as bool? ?? true,
        reactions: _map(j['reactions']).map((k, v) => MapEntry(k, '$v')),
        secret: j['secret'] as bool? ?? false,
        revealedAt: _date(j['revealedAt']),
        createdAt: _date(j['createdAt']) ?? DateTime.now(),
      );

  static const maxCaption = 40;

  final String id;
  final ItemType type;
  final String senderId;

  /// Full image: storage path (Firebase) or absolute local file (local).
  final String? storagePath;

  /// Widget-size thumbnail: storage path or absolute local file.
  final String? thumbPath;
  final String caption;

  /// Note text (notes are also rendered to an image for the widget).
  final String? text;
  final NoteStyle? noteStyle;

  /// Set for [ItemType.location] items.
  final GeoTag? geo;
  final bool saveToMemories;

  /// uid → one of [reactionEmojis].
  final Map<String, String> reactions;

  /// Sent by a "secret admirer": the receiver sees no name until the sender
  /// reveals it ([revealedAt]). With only two people in a pair this is a
  /// playful game, not real anonymity.
  final bool secret;
  final DateTime? revealedAt;
  final DateTime createdAt;

  /// Whether the sender should be hidden from [viewerUid].
  bool hidesSenderFrom(String? viewerUid) =>
      secret && revealedAt == null && senderId != viewerUid;

  Item copyWith({Map<String, String>? reactions, DateTime? revealedAt}) => Item(
        id: id,
        type: type,
        senderId: senderId,
        storagePath: storagePath,
        thumbPath: thumbPath,
        caption: caption,
        text: text,
        noteStyle: noteStyle,
        geo: geo,
        saveToMemories: saveToMemories,
        reactions: reactions ?? this.reactions,
        secret: secret,
        revealedAt: revealedAt ?? this.revealedAt,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'senderId': senderId,
        'storagePath': storagePath,
        'thumbPath': thumbPath,
        'caption': caption,
        'text': text,
        'noteStyle': noteStyle?.toJson(),
        'geo': geo?.toJson(),
        'saveToMemories': saveToMemories,
        'reactions': reactions,
        'secret': secret,
        'revealedAt': _ms(revealedAt),
        'createdAt': _ms(createdAt),
      };
}

/// One-tap affectionate messages ("I can't stop thinking about you").
/// [Tap.kind] stores the [id]. Keep ids in sync with `TAP_KINDS` in
/// functions/src/items.ts.
@immutable
class TapKind {
  const TapKind(this.id, this.emoji, this.label, this.message);

  final String id;
  final String emoji;

  /// Short button label ("Thinking of you").
  final String label;

  /// What the partner reads ("can't stop thinking about you").
  final String message;

  static const heart = TapKind('heart', '💗', 'Heart', 'is thinking of you');

  static const all = [
    heart,
    TapKind('thinking', '💭', 'Thinking of you', 'can’t stop thinking about you'),
    TapKind('miss', '🥺', 'Miss you', 'misses you so much'),
    TapKind('hug', '🤗', 'Hug', 'sent you a big warm hug'),
    TapKind('kiss', '😘', 'Kiss', 'sent you a kiss'),
    TapKind('proud', '🌟', 'Proud of you', 'is so proud of you'),
    TapKind('love', '❤️', 'Love you', 'loves you'),
  ];

  static TapKind byId(String? id) =>
      all.firstWhere((k) => k.id == id, orElse: () => heart);
}

/// Emoji people can react to photos, notes and doodles with.
const reactionEmojis = ['❤️', '😍', '🥹', '😂', '😘', '🔥', '👏'];

@immutable
class Tap {
  const Tap({
    required this.id,
    required this.senderId,
    required this.createdAt,
    this.kind = 'heart',
  });

  factory Tap.fromJson(String id, Map<String, dynamic> j) => Tap(
        id: id,
        senderId: j['senderId'] as String? ?? '',
        kind: j['kind'] as String? ?? 'heart',
        createdAt: _date(j['createdAt']) ?? DateTime.now(),
      );

  final String id;
  final String senderId;
  final String kind;
  final DateTime createdAt;

  TapKind get info => TapKind.byId(kind);

  Map<String, dynamic> toJson() =>
      {'senderId': senderId, 'kind': kind, 'createdAt': _ms(createdAt)};
}

/// "How much do you miss me?" for one day: each person picks 0..100 in
/// private; both values are revealed together once both answered.
@immutable
class MissMeter {
  const MissMeter({
    required this.date,
    this.answeredBy = const [],
    this.revealed = false,
    this.values = const {},
    this.myValue,
  });

  factory MissMeter.fromJson(String date, Map<String, dynamic> j) => MissMeter(
        date: date,
        answeredBy: (j['answeredBy'] as List?)?.cast<String>() ?? const [],
        revealed: j['revealed'] as bool? ?? false,
        values: _map(j['values']).map((k, v) => MapEntry(k, (v as num).toInt())),
      );

  static const max = 100;

  /// yyyy-mm-dd
  final String date;
  final List<String> answeredBy;
  final bool revealed;

  /// uid → 0..100. Only filled once both answered (written by the server).
  final Map<String, int> values;

  /// The current user's private value (from `private/{uid}`).
  final int? myValue;

  MissMeter withMyValue(int? v) => MissMeter(
        date: date,
        answeredBy: answeredBy,
        revealed: revealed,
        values: values,
        myValue: v,
      );

  /// Word for a value, used on the slider and in the reveal.
  static String describe(int v) => switch (v) {
        < 15 => 'A tiny bit 🙂',
        < 35 => 'Quite a lot 🥲',
        < 60 => 'So much 🥺',
        < 85 => 'Like crazy 😭',
        _ => 'To the moon and back 🚀',
      };

  Map<String, dynamic> toJson() => {
        'answeredBy': answeredBy,
        'revealed': revealed,
        'values': values,
      };
}

@immutable
class DailyQuestion {
  const DailyQuestion({
    required this.date,
    required this.questionId,
    required this.text,
    this.packId = 'everyday',
    this.answeredBy = const [],
    this.revealed = false,
    this.answers = const {},
    this.myAnswer,
  });

  factory DailyQuestion.fromJson(String date, Map<String, dynamic> j) =>
      DailyQuestion(
        date: date,
        questionId: j['questionId'] as String? ?? '',
        text: j['text'] as String? ?? '',
        packId: j['packId'] as String? ?? 'everyday',
        answeredBy: (j['answeredBy'] as List?)?.cast<String>() ?? const [],
        revealed: j['revealed'] as bool? ?? false,
        answers: _map(j['answers']).cast<String, String>(),
      );

  /// yyyy-mm-dd
  final String date;
  final String questionId;
  final String text;
  final String packId;
  final List<String> answeredBy;
  final bool revealed;

  /// Only filled once both answered (written by the server).
  final Map<String, String> answers;

  /// The current user's private answer (from `private/{uid}`).
  final String? myAnswer;

  DailyQuestion withMyAnswer(String? a) => DailyQuestion(
        date: date,
        questionId: questionId,
        text: text,
        packId: packId,
        answeredBy: answeredBy,
        revealed: revealed,
        answers: answers,
        myAnswer: a,
      );

  Map<String, dynamic> toJson() => {
        'questionId': questionId,
        'text': text,
        'packId': packId,
        'answeredBy': answeredBy,
        'revealed': revealed,
        'answers': answers,
      };
}

/// What a calendar event is about. Picks the default emoji and colour.
enum EventCategory {
  date('💑', 'Date'),
  meetup('🤗', 'Meet-up'),
  trip('✈️', 'Trip'),
  call('📞', 'Call'),
  birthday('🎂', 'Birthday'),
  anniversary('💍', 'Anniversary'),
  other('📅', 'Other');

  EventCategory(this.emoji, this.label);

  final String emoji;
  final String label;

  static EventCategory parse(Object? v) =>
      EventCategory.values.firstWhere((c) => c.name == v, orElse: () => other);
}

/// A shared calendar event. Countdowns are events with [showAsCountdown]
/// (shown big on Home and on the countdown widget). Dates planned in the
/// date planner are events with [EventCategory.date].
///
/// Stored in `pairs/{pairId}/countdowns/{id}` (the collection kept its name
/// so reminders and older app versions keep working).
@immutable
class Countdown {
  const Countdown({
    required this.id,
    required this.title,
    required this.date,
    required this.createdBy,
    this.emoji = '📅',
    this.repeatsYearly = false,
    this.hasTime = false,
    int? remindMinutesBefore,
    int remindDaysBefore = 1,
    this.category = EventCategory.other,
    this.endDate,
    this.note = '',
    this.place = '',
    this.isVirtual = false,
    this.showAsCountdown = true,
    this.done = false,
    this.ratings = const {},
  }) : remindMinutesBefore = remindMinutesBefore ?? remindDaysBefore * minutesPerDay;

  factory Countdown.fromJson(String id, Map<String, dynamic> j) => Countdown(
        id: id,
        title: j['title'] as String? ?? '',
        date: _date(j['date']) ?? DateTime.now(),
        emoji: j['emoji'] as String? ?? '📅',
        repeatsYearly: j['repeatsYearly'] as bool? ?? false,
        hasTime: j['hasTime'] as bool? ?? false,
        remindMinutesBefore: j['remindMinutesBefore'] as int?,
        remindDaysBefore: j['remindDaysBefore'] as int? ?? 1,
        createdBy: j['createdBy'] as String? ?? '',
        category: EventCategory.parse(j['category']),
        endDate: _date(j['endDate']),
        note: j['note'] as String? ?? '',
        place: j['place'] as String? ?? '',
        isVirtual: j['isVirtual'] as bool? ?? false,
        // Everything made before the calendar existed was a countdown.
        showAsCountdown: j['showAsCountdown'] as bool? ?? true,
        done: j['done'] as bool? ?? false,
        ratings: _map(j['ratings']).map((k, v) => MapEntry(k, (v as num).toInt())),
      );

  static const maxTitle = 60;
  static const maxNote = 500;
  static const maxPlace = 120;

  static const freeLimit = 3;
  static const minutesPerDay = 24 * 60;

  /// Longest reminder lead time allowed (60 days), matching the rules.
  static const maxRemindMinutes = 60 * minutesPerDay;

  final String id;
  final String title;

  /// The moment being counted down to. Only the date part matters when
  /// [hasTime] is false (countdowns made before times were added).
  final DateTime date;
  final String emoji;
  final bool repeatsYearly;
  final bool hasTime;

  /// How long before [date] to send the reminder; 0 = only at the time.
  final int remindMinutesBefore;
  final String createdBy;

  final EventCategory category;

  /// Last day of a multi-day event (a trip). Null for single-day events.
  final DateTime? endDate;
  final String note;

  /// Where (an address, a restaurant) or a call link.
  final String place;

  /// A virtual date / call rather than meeting in person.
  final bool isVirtual;

  /// Shown on Home, the countdown widget and the countdown list.
  final bool showAsCountdown;

  /// Dates: it happened (set when either of you rates it).
  final bool done;

  /// Dates: uid → 1..5 hearts.
  final Map<String, int> ratings;

  bool get isDate => category == EventCategory.date;

  /// Whether the event covers [day] (date only), including yearly repeats
  /// and multi-day ranges.
  bool occursOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final start = DateTime(date.year, date.month, date.day);
    final end = endDate == null ? start : DateTime(endDate!.year, endDate!.month, endDate!.day);
    if (repeatsYearly) {
      if (d.isBefore(start)) return false;
      final s = DateTime(d.year, start.month, start.day);
      final e = s.add(end.difference(start));
      return !d.isBefore(s) && !d.isAfter(e);
    }
    return !d.isBefore(start) && !d.isAfter(end);
  }

  /// Has this (one-off) event finished?
  bool isPast(DateTime now) {
    if (repeatsYearly) return false;
    final last = endDate ?? date;
    final end = hasTime && endDate == null ? last : DateTime(last.year, last.month, last.day, 23, 59);
    return end.isBefore(now);
  }

  Countdown copyWith({bool? done, Map<String, int>? ratings, bool? showAsCountdown}) => Countdown(
        id: id,
        title: title,
        date: date,
        createdBy: createdBy,
        emoji: emoji,
        repeatsYearly: repeatsYearly,
        hasTime: hasTime,
        remindMinutesBefore: remindMinutesBefore,
        category: category,
        endDate: endDate,
        note: note,
        place: place,
        isVirtual: isVirtual,
        showAsCountdown: showAsCountdown ?? this.showAsCountdown,
        done: done ?? this.done,
        ratings: ratings ?? this.ratings,
      );

  /// Whole days, kept in sync for older app versions and the daily job.
  int get remindDaysBefore => remindMinutesBefore ~/ minutesPerDay;

  /// Next occurrence (date-only), rolling yearly dates forward.
  DateTime nextOccurrence(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    var d = DateTime(date.year, date.month, date.day);
    if (repeatsYearly) {
      while (d.isBefore(today)) {
        d = DateTime(d.year + 1, d.month, d.day);
      }
    }
    return d;
  }

  /// Next occurrence including the time of day.
  DateTime nextMoment(DateTime now) {
    final d = nextOccurrence(now);
    return DateTime(d.year, d.month, d.day, date.hour, date.minute);
  }

  int daysLeft(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return nextOccurrence(now).difference(today).inDays;
  }

  /// When the next notification is due: the reminder before the moment,
  /// else the moment itself, rolling yearly countdowns forward. Null once a
  /// one-off countdown has passed.
  DateTime? nextReminderAt(DateTime now) {
    final first = nextMoment(now);
    final moments = [
      first,
      if (repeatsYearly) DateTime(first.year + 1, first.month, first.day, first.hour, first.minute),
    ];
    for (final m in moments) {
      final before = m.subtract(Duration(minutes: remindMinutesBefore));
      if (remindMinutesBefore > 0 && before.isAfter(now)) return before;
      if (m.isAfter(now)) return m;
    }
    return null;
  }

  /// "On the day", "15 minutes before", "2 hours before", "3 days before"...
  static String describeRemind(int minutes, {bool hasTime = true}) {
    if (minutes <= 0) return hasTime ? 'At the time' : 'On the day';
    String unit(int n, String w) => '$n $w${n == 1 ? '' : 's'} before';
    if (minutes % (7 * minutesPerDay) == 0) return unit(minutes ~/ (7 * minutesPerDay), 'week');
    if (minutes % minutesPerDay == 0) return unit(minutes ~/ minutesPerDay, 'day');
    if (minutes % 60 == 0) return unit(minutes ~/ 60, 'hour');
    return unit(minutes, 'minute');
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'date': _ms(date),
        'emoji': emoji,
        'repeatsYearly': repeatsYearly,
        'hasTime': hasTime,
        'remindMinutesBefore': remindMinutesBefore,
        'remindDaysBefore': remindDaysBefore,
        'createdBy': createdBy,
        'category': category.name,
        'endDate': _ms(endDate),
        'note': note,
        'place': place,
        'isVirtual': isVirtual,
        'showAsCountdown': showAsCountdown,
        'done': done,
        'ratings': ratings,
      };
}

@immutable
class GameQuestion {
  const GameQuestion({required this.text, required this.options});

  factory GameQuestion.fromJson(Map<String, dynamic> j) => GameQuestion(
        text: j['text'] as String? ?? '',
        options: (j['options'] as List?)?.cast<String>() ?? const [],
      );

  final String text;
  final List<String> options;

  Map<String, dynamic> toJson() => {'text': text, 'options': options};
}

enum GameStatus {
  /// Waiting for the subject to answer about themselves.
  subjectTurn,

  /// Waiting for the partner to guess.
  guesserTurn,
  done;

  static GameStatus parse(Object? v) => GameStatus.values
      .firstWhere((s) => s.name == v, orElse: () => subjectTurn);
}

/// "How well do you know me?" — one answers about themselves, the other
/// guesses.
@immutable
class Game {
  const Game({
    required this.id,
    required this.subjectUid,
    required this.guesserUid,
    required this.questions,
    required this.createdAt,
    this.type = 'know-me',
    this.packId = 'starter',
    this.subjectAnswers = const [],
    this.guesses = const [],
    this.status = GameStatus.subjectTurn,
  });

  factory Game.fromJson(String id, Map<String, dynamic> j) {
    final answers = _map(j['answers']);
    return Game(
      id: id,
      type: j['type'] as String? ?? 'know-me',
      packId: j['packId'] as String? ?? 'starter',
      subjectUid: j['subjectUid'] as String? ?? '',
      guesserUid: j['guesserUid'] as String? ?? '',
      questions: ((j['questions'] as List?) ?? const [])
          .map((q) => GameQuestion.fromJson(_map(q)))
          .toList(),
      subjectAnswers: (answers['subject'] as List?)?.cast<int>() ?? const [],
      guesses: (answers['guesser'] as List?)?.cast<int>() ?? const [],
      status: GameStatus.parse(j['status']),
      createdAt: _date(j['createdAt']) ?? DateTime.now(),
    );
  }

  final String id;
  final String type;
  final String packId;
  final String subjectUid;
  final String guesserUid;
  final List<GameQuestion> questions;
  final List<int> subjectAnswers;
  final List<int> guesses;
  final GameStatus status;
  final DateTime createdAt;

  int get score {
    var s = 0;
    for (var i = 0; i < guesses.length && i < subjectAnswers.length; i++) {
      if (guesses[i] == subjectAnswers[i]) s++;
    }
    return s;
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'packId': packId,
        'subjectUid': subjectUid,
        'guesserUid': guesserUid,
        'questions': questions.map((q) => q.toJson()).toList(),
        'answers': {'subject': subjectAnswers, 'guesser': guesses},
        'score': score,
        'status': status.name,
        'createdAt': _ms(createdAt),
      };
}

/// Request to send a photo / note / doodle. All three are sent as an image
/// file (notes and doodles are rendered to PNG on device) so the home-screen
/// widget only ever has to draw a bitmap.
@immutable
class SendRequest {
  const SendRequest({
    required this.type,
    required this.imagePath,
    this.caption = '',
    this.text,
    this.noteStyle,
    this.geo,
    this.saveToMemories = true,
    this.secret = false,
  });

  final ItemType type;
  final String imagePath;
  final String caption;
  final String? text;
  final NoteStyle? noteStyle;
  final GeoTag? geo;
  final bool saveToMemories;

  /// Send as a secret admirer (see [Item.secret]).
  final bool secret;
}

/// Thrown when a free-tier limit is hit; the UI responds with the paywall.
class LimitReachedException implements Exception {
  const LimitReachedException(this.limit, [this.message = 'Limit reached']);

  final String limit;
  final String message;

  @override
  String toString() => message;
}

/// Thrown for user-facing errors (bad invite code, etc.).
class CloserException implements Exception {
  const CloserException(this.message);

  final String message;

  @override
  String toString() => message;
}

// ------------------------------------------------------------ love capsules

/// What a [Capsule] is: one of the "100 reasons", a letter from the future,
/// or a surprise (note, photo, compliment or virtual gift).
enum CapsuleKind {
  reason,
  letter,
  surprise;

  static CapsuleKind parse(Object? v) =>
      CapsuleKind.values.firstWhere((k) => k.name == v, orElse: () => letter);
}

/// Kinds of [CapsuleKind.surprise].
enum SurpriseType {
  note,
  photo,
  compliment,
  gift;

  static SurpriseType? parse(Object? v) =>
      SurpriseType.values.where((t) => t.name == v).firstOrNull;
}

/// A sealed envelope: who wrote it, for whom, and when it opens. Everyone in
/// the pair can see envelopes; the [CapsuleContent] stays locked for the
/// receiver until [unlockAt] (enforced by Firestore rules).
///
/// `pairs/{pairId}/capsules/{id}` + `capsules/{id}/content/main`.
@immutable
class Capsule {
  const Capsule({
    required this.id,
    required this.kind,
    required this.authorId,
    required this.forUid,
    required this.createdAt,
    required this.unlockAt,
    this.title = '',
    this.surpriseType,
    this.openedAt,
  });

  factory Capsule.fromJson(String id, Map<String, dynamic> j) => Capsule(
        id: id,
        kind: CapsuleKind.parse(j['kind']),
        authorId: j['authorId'] as String? ?? '',
        forUid: j['forUid'] as String? ?? '',
        title: j['title'] as String? ?? '',
        surpriseType: SurpriseType.parse(j['surpriseType']),
        createdAt: _date(j['createdAt']) ?? DateTime.now(),
        unlockAt: _date(j['unlockAt']) ?? DateTime.now(),
        openedAt: _date(j['openedAt']),
      );

  static const maxTitle = 80;
  static const maxReasons = 100;

  final String id;
  final CapsuleKind kind;
  final String authorId;
  final String forUid;

  /// Shown on the sealed envelope ("Open when you miss me").
  final String title;
  final SurpriseType? surpriseType;
  final DateTime createdAt;
  final DateTime unlockAt;

  /// Set by the receiver the first time they open it.
  final DateTime? openedAt;

  bool isUnlocked(DateTime now) => !unlockAt.isAfter(now);

  @override
  bool operator ==(Object other) => other is Capsule && other.id == id && other.unlockAt == unlockAt;

  @override
  int get hashCode => Object.hash(id, unlockAt);

  /// Unlocked for [uid] and not opened yet.
  bool isNewFor(String? uid, DateTime now) => forUid == uid && isUnlocked(now) && openedAt == null;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'authorId': authorId,
        'forUid': forUid,
        'title': title,
        'surpriseType': surpriseType?.name,
        'createdAt': _ms(createdAt),
        'unlockAt': _ms(unlockAt),
        'openedAt': _ms(openedAt),
      };

  /// When the next reason should unlock, given the author's existing
  /// capsules: one reason a day at 08:00. The first one (or the first after
  /// a gap) unlocks today.
  static DateTime nextReasonUnlock(Iterable<Capsule> mine, DateTime now) {
    final today8 = DateTime(now.year, now.month, now.day, 8);
    final asap = now.isBefore(today8) ? today8 : now;
    final reasons = mine.where((c) => c.kind == CapsuleKind.reason).toList();
    if (reasons.isEmpty) return asap;
    final last = reasons.map((c) => c.unlockAt).reduce((a, b) => a.isAfter(b) ? a : b);
    final next = DateTime(last.year, last.month, last.day + 1, 8);
    final lastDay = DateTime(last.year, last.month, last.day);
    final today = DateTime(now.year, now.month, now.day);
    // Behind schedule (nothing queued for today yet): unlock today.
    if (lastDay.isBefore(today)) return asap;
    return next;
  }
}

/// The locked part of a [Capsule].
@immutable
class CapsuleContent {
  const CapsuleContent({this.text = '', this.photoPath, this.giftId});

  factory CapsuleContent.fromJson(Map<String, dynamic> j) => CapsuleContent(
        text: j['text'] as String? ?? '',
        photoPath: j['photoPath'] as String?,
        giftId: j['giftId'] as String?,
      );

  static const maxText = 2000;
  static const maxReason = 200;

  final String text;

  /// Storage ref (Firebase) or local file (local backend).
  final String? photoPath;

  /// [VirtualGift.id] for gift surprises.
  final String? giftId;

  Map<String, dynamic> toJson() => {'text': text, 'photoPath': photoPath, 'giftId': giftId};
}

@immutable
class VirtualGift {
  const VirtualGift(this.id, this.emoji, this.name);

  final String id;
  final String emoji;
  final String name;

  static const all = [
    VirtualGift('rose', '🌹', 'A rose'),
    VirtualGift('bouquet', '💐', 'A bouquet'),
    VirtualGift('teddy', '🧸', 'A teddy bear'),
    VirtualGift('chocolate', '🍫', 'Chocolate'),
    VirtualGift('coffee', '☕', 'A coffee'),
    VirtualGift('cake', '🍰', 'A slice of cake'),
    VirtualGift('balloon', '🎈', 'A balloon'),
    VirtualGift('star', '⭐', 'A star, named after you'),
    VirtualGift('hug', '🫂', 'A long hug'),
    VirtualGift('ring', '💍', 'A promise ring'),
    VirtualGift('pizza', '🍕', 'Pizza night'),
    VirtualGift('sunflower', '🌻', 'A sunflower'),
  ];

  static VirtualGift? byId(String? id) => all.where((g) => g.id == id).firstOrNull;
}

/// Ready-made compliments for [SurpriseType.compliment].
const compliments = [
  'Your laugh is my favourite sound 😊',
  'You make everything better just by being there',
  'I’m so proud of the person you are',
  'You’re even more beautiful on the inside ✨',
  'Talking to you is the best part of my day',
  'You have the kindest heart I know 💗',
  'You make me want to be a better person',
  'Everything is more fun with you',
  'You’re smarter than you give yourself credit for',
  'Your hugs fix everything 🤗',
];

// ----------------------------------------------------------------- timeline

/// A moment on "Our love timeline". `pairs/{pairId}/timeline/{id}`.
@immutable
class TimelineEntry {
  const TimelineEntry({
    required this.id,
    required this.date,
    required this.title,
    required this.createdBy,
    this.emoji = '💞',
    this.note = '',
    this.photoPath,
    this.auto = false,
  });

  factory TimelineEntry.fromJson(String id, Map<String, dynamic> j) => TimelineEntry(
        id: id,
        date: _date(j['date']) ?? DateTime.now(),
        title: j['title'] as String? ?? '',
        emoji: j['emoji'] as String? ?? '💞',
        note: j['note'] as String? ?? '',
        photoPath: j['photoPath'] as String?,
        createdBy: j['createdBy'] as String? ?? '',
      );

  static const maxTitle = 60;
  static const maxNote = 500;

  static const presets = [
    ('💬', 'Our first conversation'),
    ('☕', 'Our first date'),
    ('💋', 'Our first kiss'),
    ('💞', 'We became official'),
    ('✈️', 'Our first trip'),
    ('🏡', 'We moved in together'),
    ('💍', 'We got engaged'),
    ('🎂', 'A birthday to remember'),
    ('🌟', 'An unforgettable day'),
  ];

  final String id;
  final DateTime date;
  final String title;
  final String emoji;
  final String note;
  final String? photoPath;
  final String createdBy;

  /// Generated by the app (the day you paired, your anniversary…), not stored.
  final bool auto;

  Map<String, dynamic> toJson() => {
        'date': _ms(date),
        'title': title,
        'emoji': emoji,
        'note': note,
        'photoPath': photoPath,
        'createdBy': createdBy,
      };
}

// ------------------------------------------------------------------- shrine

@immutable
class ShrineFavorite {
  const ShrineFavorite(this.label, this.value);

  factory ShrineFavorite.fromJson(Map<String, dynamic> j) =>
      ShrineFavorite(j['label'] as String? ?? '', j['value'] as String? ?? '');

  final String label;
  final String value;

  Map<String, dynamic> toJson() => {'label': label, 'value': value};
}

/// "My love shrine": a space each member builds for the other one.
/// `pairs/{pairId}/shrines/{ownerUid}` — only the owner writes it.
@immutable
class Shrine {
  const Shrine({
    required this.ownerUid,
    this.title = '',
    this.theme = 'rose',
    this.coverPath,
    this.photos = const [],
    this.favorites = const [],
    this.messages = const [],
    this.pinnedItemIds = const [],
    this.updatedAt,
  });

  factory Shrine.fromJson(String ownerUid, Map<String, dynamic> j) => Shrine(
        ownerUid: ownerUid,
        title: j['title'] as String? ?? '',
        theme: j['theme'] as String? ?? 'rose',
        coverPath: j['coverPath'] as String?,
        photos: (j['photos'] as List?)?.cast<String>() ?? const [],
        favorites: (j['favorites'] as List?)?.map((f) => ShrineFavorite.fromJson(_map(f))).toList() ?? const [],
        messages: (j['messages'] as List?)?.cast<String>() ?? const [],
        pinnedItemIds: (j['pinnedItemIds'] as List?)?.cast<String>() ?? const [],
        updatedAt: _date(j['updatedAt']),
      );

  static const maxPhotos = 9;
  static const maxFavorites = 12;
  static const maxMessages = 20;
  static const maxPinned = 12;
  static const maxTitle = 60;
  static const maxText = 300;

  static const themes = ['rose', 'lavender', 'sunset', 'midnight', 'mint'];

  static const favoriteLabels = [
    'Food',
    'Song',
    'Movie',
    'Colour',
    'Place',
    'Flower',
    'Drink',
    'Smell',
    'Memory',
    'Thing about you',
  ];

  final String ownerUid;
  final String title;
  final String theme;
  final String? coverPath;
  final List<String> photos;
  final List<ShrineFavorite> favorites;
  final List<String> messages;
  final List<String> pinnedItemIds;
  final DateTime? updatedAt;

  bool get isEmpty =>
      coverPath == null && photos.isEmpty && favorites.isEmpty && messages.isEmpty && pinnedItemIds.isEmpty;

  Shrine copyWith({
    String? title,
    String? theme,
    String? Function()? coverPath,
    List<String>? photos,
    List<ShrineFavorite>? favorites,
    List<String>? messages,
    List<String>? pinnedItemIds,
  }) =>
      Shrine(
        ownerUid: ownerUid,
        title: title ?? this.title,
        theme: theme ?? this.theme,
        coverPath: coverPath == null ? this.coverPath : coverPath(),
        photos: photos ?? this.photos,
        favorites: favorites ?? this.favorites,
        messages: messages ?? this.messages,
        pinnedItemIds: pinnedItemIds ?? this.pinnedItemIds,
        updatedAt: updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'theme': theme,
        'coverPath': coverPath,
        'photos': photos,
        'favorites': favorites.map((f) => f.toJson()).toList(),
        'messages': messages,
        'pinnedItemIds': pinnedItemIds,
        'updatedAt': _ms(updatedAt),
      };
}

// ------------------------------------------------------------- date planner

/// How many dates you want per week or month.
@immutable
class DateGoal {
  const DateGoal({required this.count, this.perMonth = false});

  factory DateGoal.fromJson(Map<String, dynamic> j) => DateGoal(
        count: (j['count'] as num?)?.toInt().clamp(1, maxCount) ?? 1,
        perMonth: j['per'] == 'month',
      );

  static const maxCount = 14;

  final int count;
  final bool perMonth;

  String get label => '$count date${count == 1 ? '' : 's'} a ${perMonth ? 'month' : 'week'}';

  /// Start of the current goal period (Monday, or the 1st of the month).
  DateTime periodStart(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return perMonth ? DateTime(now.year, now.month) : today.subtract(Duration(days: now.weekday - 1));
  }

  DateTime periodEnd(DateTime now) {
    final s = periodStart(now);
    return perMonth ? DateTime(s.year, s.month + 1) : s.add(const Duration(days: 7));
  }

  /// The period before the one that starts at [start].
  DateTime previousStart(DateTime start) =>
      perMonth ? DateTime(start.year, start.month - 1) : start.subtract(const Duration(days: 7));

  Map<String, dynamic> toJson() => {'count': count, 'per': perMonth ? 'month' : 'week'};
}

/// A date idea from the built-in catalogue.
@immutable
class DateIdea {
  const DateIdea(this.id, this.emoji, this.title, {this.virtual = false, this.vibe = 'cozy'});

  final String id;
  final String emoji;
  final String title;
  final bool virtual;

  /// cozy · active · food · creative · adventure
  final String vibe;
}

const dateIdeas = [
  DateIdea('picnic', '🧺', 'Sunset picnic'),
  DateIdea('cook', '🍝', 'Cook a new recipe together', vibe: 'food'),
  DateIdea('stargaze', '🌌', 'Stargazing night'),
  DateIdea('museum', '🖼️', 'Museum or gallery afternoon', vibe: 'creative'),
  DateIdea('hike', '🥾', 'Hike to a view', vibe: 'active'),
  DateIdea('arcade', '🕹️', 'Arcade or bowling night', vibe: 'active'),
  DateIdea('market', '🧀', 'Explore a food market', vibe: 'food'),
  DateIdea('daytrip', '🚆', 'Day trip somewhere new', vibe: 'adventure'),
  DateIdea('pottery', '🏺', 'Pottery or painting class', vibe: 'creative'),
  DateIdea('karaoke', '🎤', 'Karaoke night', vibe: 'active'),
  DateIdea('breakfast', '🥞', 'Breakfast in bed'),
  DateIdea('bikes', '🚲', 'Bike ride and ice cream', vibe: 'active'),
  DateIdea('movie_v', '🎬', 'Watch a movie in sync', virtual: true),
  DateIdea('dinner_v', '🍜', 'Dinner over video call', virtual: true, vibe: 'food'),
  DateIdea('game_v', '🎮', 'Play an online game together', virtual: true, vibe: 'active'),
  DateIdea('quiz_v', '❓', 'Play 36 questions', virtual: true),
  DateIdea('tour_v', '🌍', 'Take a virtual museum tour', virtual: true, vibe: 'creative'),
  DateIdea('cook_v', '👩‍🍳', 'Cook the same recipe on video', virtual: true, vibe: 'food'),
  DateIdea('playlist_v', '🎧', 'Make a playlist for each other', virtual: true, vibe: 'creative'),
  DateIdea('walk_v', '📞', 'Walk and talk on the phone', virtual: true, vibe: 'active'),
  DateIdea('stars_v', '✨', 'Stargaze on a call', virtual: true),
  DateIdea('letters_v', '💌', 'Write each other a letter, read it live', virtual: true, vibe: 'creative'),
];

// -------------------------------------------------------------------- to-dos

/// A shared to-do list. `pairs/{pairId}/todoLists/{id}`.
@immutable
class TodoList {
  const TodoList({required this.id, required this.title, required this.createdBy, this.emoji = '📝', this.createdAt});

  factory TodoList.fromJson(String id, Map<String, dynamic> j) => TodoList(
        id: id,
        title: j['title'] as String? ?? '',
        emoji: j['emoji'] as String? ?? '📝',
        createdBy: j['createdBy'] as String? ?? '',
        createdAt: _date(j['createdAt']),
      );

  static const maxTitle = 40;

  final String id;
  final String title;
  final String emoji;
  final String createdBy;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() => {'title': title, 'emoji': emoji, 'createdBy': createdBy, 'createdAt': _ms(createdAt)};
}

/// A shared task. `pairs/{pairId}/todos/{id}`.
@immutable
class Todo {
  const Todo({
    required this.id,
    required this.listId,
    required this.text,
    required this.createdBy,
    this.assignee,
    this.due,
    this.doneBy,
    this.doneAt,
    this.createdAt,
  });

  factory Todo.fromJson(String id, Map<String, dynamic> j) => Todo(
        id: id,
        listId: j['listId'] as String? ?? '',
        text: j['text'] as String? ?? '',
        assignee: j['assignee'] as String?,
        due: _date(j['due']),
        doneBy: j['doneBy'] as String?,
        doneAt: _date(j['doneAt']),
        createdBy: j['createdBy'] as String? ?? '',
        createdAt: _date(j['createdAt']),
      );

  static const maxText = 200;

  final String id;
  final String listId;
  final String text;

  /// uid of who should do it; null = both of you.
  final String? assignee;
  final DateTime? due;
  final String? doneBy;
  final DateTime? doneAt;
  final String createdBy;
  final DateTime? createdAt;

  bool get isDone => doneAt != null;

  bool isFor(String? uid) => assignee == null || assignee == uid;

  bool isOverdue(DateTime now) {
    final d = due;
    if (d == null || isDone) return false;
    return DateTime(d.year, d.month, d.day).isBefore(DateTime(now.year, now.month, now.day));
  }

  Map<String, dynamic> toJson() => {
        'listId': listId,
        'text': text,
        'assignee': assignee,
        'due': _ms(due),
        'doneBy': doneBy,
        'doneAt': _ms(doneAt),
        'createdBy': createdBy,
        'createdAt': _ms(createdAt),
      };
}

// ------------------------------------------------------------------ wishlist

enum WishCategory {
  gift('🎁', 'Gift'),
  date('💑', 'Date idea'),
  restaurant('🍽️', 'Restaurant'),
  travel('✈️', 'Travel'),
  experience('🎟️', 'Experience'),
  other('✨', 'Other');

  WishCategory(this.emoji, this.label);

  final String emoji;
  final String label;

  static WishCategory parse(Object? v) =>
      WishCategory.values.firstWhere((c) => c.name == v, orElse: () => other);
}

/// Something one of you wants, or something you want to do together.
/// `pairs/{pairId}/wishes/{id}`.
///
/// Gifts belong to [ownerUid] (the person who wants it); the partner can
/// secretly claim it (`wishClaims/{wishId}`, readable only by the claimer).
/// Everything else is shared ([ownerUid] null) and can be ticked off.
@immutable
class Wish {
  const Wish({
    required this.id,
    required this.title,
    required this.createdBy,
    this.category = WishCategory.other,
    this.note = '',
    this.url = '',
    this.price = '',
    this.photoPath,
    this.ownerUid,
    this.doneAt,
    this.createdAt,
  });

  factory Wish.fromJson(String id, Map<String, dynamic> j) => Wish(
        id: id,
        title: j['title'] as String? ?? '',
        category: WishCategory.parse(j['category']),
        note: j['note'] as String? ?? '',
        url: j['url'] as String? ?? '',
        price: j['price'] as String? ?? '',
        photoPath: j['photoPath'] as String?,
        ownerUid: j['ownerUid'] as String?,
        createdBy: j['createdBy'] as String? ?? '',
        doneAt: _date(j['doneAt']),
        createdAt: _date(j['createdAt']),
      );

  static const maxTitle = 80;
  static const maxNote = 300;
  static const maxUrl = 500;
  static const maxPrice = 20;

  final String id;
  final String title;
  final WishCategory category;
  final String note;
  final String url;
  final String price;
  final String? photoPath;

  /// Gifts: who wants it. Null for shared wishes.
  final String? ownerUid;
  final String createdBy;

  /// Shared wishes: when you did it together. Gifts: when it was received.
  final DateTime? doneAt;
  final DateTime? createdAt;

  bool get isGift => category == WishCategory.gift;

  Map<String, dynamic> toJson() => {
        'title': title,
        'category': category.name,
        'note': note,
        'url': url,
        'price': price,
        'photoPath': photoPath,
        'ownerUid': ownerUid,
        'createdBy': createdBy,
        'doneAt': _ms(doneAt),
        'createdAt': _ms(createdAt),
      };
}

// --------------------------------------------------------------------- chat

enum MessageType {
  text,
  photo,
  voice;

  static MessageType parse(Object? v) => MessageType.values.firstWhere((t) => t.name == v, orElse: () => text);
}

/// What a reply points at, copied into the reply so it still shows if the
/// original is deleted.
@immutable
class ReplyRef {
  const ReplyRef({required this.id, required this.senderId, required this.preview});

  factory ReplyRef.fromJson(Map<String, dynamic> j) => ReplyRef(
        id: j['id'] as String? ?? '',
        senderId: j['senderId'] as String? ?? '',
        preview: j['preview'] as String? ?? '',
      );

  final String id;
  final String senderId;

  /// Short text: the message start, "📷 Photo" or "🎤 Voice message".
  final String preview;

  Map<String, dynamic> toJson() => {'id': id, 'senderId': senderId, 'preview': preview};
}

/// One message in the private chat. `pairs/{pairId}/messages/{id}`.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.createdAt,
    this.type = MessageType.text,
    this.text = '',
    this.mediaPath,
    this.durationMs = 0,
    this.replyTo,
    this.reactions = const {},
    this.deletedAt,
    this.pending = false,
  });

  factory ChatMessage.fromJson(String id, Map<String, dynamic> j, {bool pending = false}) => ChatMessage(
        id: id,
        senderId: j['senderId'] as String? ?? '',
        type: MessageType.parse(j['type']),
        text: j['text'] as String? ?? '',
        mediaPath: j['mediaPath'] as String?,
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        replyTo: j['replyTo'] == null ? null : ReplyRef.fromJson(_map(j['replyTo'])),
        reactions: _map(j['reactions']).map((k, v) => MapEntry(k, '$v')),
        deletedAt: _date(j['deletedAt']),
        // Server timestamps are null until written; show those as "now".
        createdAt: _date(j['createdAt']) ?? DateTime.now(),
        pending: pending,
      );

  static const maxText = 2000;

  /// Longest voice message (5 minutes).
  static const maxVoiceMs = 5 * 60 * 1000;

  final String id;
  final String senderId;
  final MessageType type;
  final String text;

  /// Photo or voice file: storage ref (Firebase) or local path.
  final String? mediaPath;
  final int durationMs;
  final ReplyRef? replyTo;

  /// uid → emoji.
  final Map<String, String> reactions;
  final DateTime? deletedAt;
  final DateTime createdAt;

  /// Not yet confirmed by the server (sent offline).
  final bool pending;

  bool get isDeleted => deletedAt != null;

  /// One-line summary for replies and notifications.
  String get preview => switch (type) {
        _ when isDeleted => 'Deleted message',
        MessageType.photo => text.isEmpty ? '📷 Photo' : '📷 $text',
        MessageType.voice => '🎤 Voice message',
        MessageType.text => text.length > 80 ? '${text.substring(0, 79)}…' : text,
      };

  Map<String, dynamic> toJson() => {
        'senderId': senderId,
        'type': type.name,
        'text': text,
        'mediaPath': mediaPath,
        'durationMs': durationMs,
        'replyTo': replyTo?.toJson(),
        'reactions': reactions,
        'deletedAt': _ms(deletedAt),
        'createdAt': _ms(createdAt),
      };
}

/// What the app needs to send a message. [localPath] is a picked photo or
/// a recorded voice file, uploaded by the backend.
@immutable
class ChatDraft {
  const ChatDraft({this.type = MessageType.text, this.text = '', this.localPath, this.durationMs = 0, this.replyTo});

  final MessageType type;
  final String text;
  final String? localPath;
  final int durationMs;
  final ReplyRef? replyTo;
}

/// Per-member chat state: last read time and "typing…".
/// `pairs/{pairId}/chatState/{uid}`.
@immutable
class ChatState {
  const ChatState({this.readAt, this.typingUntil});

  factory ChatState.fromJson(Map<String, dynamic> j) =>
      ChatState(readAt: _date(j['readAt']), typingUntil: _date(j['typingUntil']));

  final DateTime? readAt;
  final DateTime? typingUntil;

  bool isTyping(DateTime now) => typingUntil != null && typingUntil!.isAfter(now);

  Map<String, dynamic> toJson() => {'readAt': _ms(readAt), 'typingUntil': _ms(typingUntil)};
}

// ---------------------------------------------------------- goodnight ritual

/// One member's goodnight: a message, the best moment of their day, an
/// optional voice note and a kiss.
@immutable
class GoodnightEntry {
  const GoodnightEntry({
    this.message = '',
    this.moment = '',
    this.momentPhotoPath,
    this.voicePath,
    this.voiceMs = 0,
    this.kiss = false,
    this.sentAt,
  });

  factory GoodnightEntry.fromJson(Map<String, dynamic> j) => GoodnightEntry(
        message: j['message'] as String? ?? '',
        moment: j['moment'] as String? ?? '',
        momentPhotoPath: j['momentPhotoPath'] as String?,
        voicePath: j['voicePath'] as String?,
        voiceMs: (j['voiceMs'] as num?)?.toInt() ?? 0,
        kiss: j['kiss'] as bool? ?? false,
        sentAt: _date(j['sentAt']),
      );

  static const maxText = 500;

  final String message;

  /// Favourite moment of the day.
  final String moment;
  final String? momentPhotoPath;
  final String? voicePath;
  final int voiceMs;
  final bool kiss;
  final DateTime? sentAt;

  bool get isEmpty => message.trim().isEmpty && moment.trim().isEmpty && voicePath == null && !kiss;

  Map<String, dynamic> toJson() => {
        'message': message,
        'moment': moment,
        'momentPhotoPath': momentPhotoPath,
        'voicePath': voicePath,
        'voiceMs': voiceMs,
        'kiss': kiss,
        'sentAt': _ms(sentAt),
      };
}

/// The goodnight ritual for one night. `pairs/{pairId}/goodnights/{night}`
/// where night is the yyyy-mm-dd the evening started (before 05:00 still
/// counts as the night before).
@immutable
class Goodnight {
  const Goodnight({required this.night, this.entries = const {}});

  factory Goodnight.fromJson(String night, Map<String, dynamic> j) => Goodnight(
        night: night,
        entries: _map(j['entries']).map((k, v) => MapEntry(k, GoodnightEntry.fromJson(_map(v)))),
      );

  /// The ritual opens at 18:00; until 05:00 it still belongs to that night.
  static const opensAtHour = 18;
  static const nightEndsHour = 5;

  final String night;

  /// uid → entry.
  final Map<String, GoodnightEntry> entries;

  bool doneBy(String? uid) => uid != null && entries[uid] != null;

  bool complete(List<String> members) => members.isNotEmpty && members.every(doneBy);

  /// The night key for [now]: today, or yesterday before 05:00.
  static String keyFor(DateTime now) {
    final d = now.hour < nightEndsHour ? now.subtract(const Duration(days: 1)) : now;
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Evening (18:00–05:00), when the ritual is meant to happen.
  static bool isEvening(DateTime now) => now.hour >= opensAtHour || now.hour < nightEndsHour;

  Map<String, dynamic> toJson() => {'entries': entries.map((k, v) => MapEntry(k, v.toJson()))};
}

// ----------------------------------------------------------- pet & home

@immutable
class PetSpecies {
  const PetSpecies(this.id, this.emoji, this.name);

  final String id;
  final String emoji;
  final String name;

  static const all = [
    PetSpecies('bunny', '🐰', 'Bunny'),
    PetSpecies('kitten', '🐱', 'Kitten'),
    PetSpecies('puppy', '🐶', 'Puppy'),
    PetSpecies('fox', '🦊', 'Fox'),
    PetSpecies('panda', '🐼', 'Panda'),
    PetSpecies('chick', '🐥', 'Chick'),
    PetSpecies('koala', '🐨', 'Koala'),
    PetSpecies('frog', '🐸', 'Frog'),
  ];

  static PetSpecies byId(String? id) => all.firstWhere((s) => s.id == id, orElse: () => all.first);
}

enum PetMood {
  sleepy('😴', 'is sleepy. Water the plant together to wake them up'),
  hungry('🍎', 'is hungry'),
  bored('🎾', 'wants to play'),
  happy('😊', 'is happy'),
  overjoyed('🥰', 'is over the moon. You both took care of them today');

  PetMood(this.emoji, this.text);

  final String emoji;
  final String text;
}

/// The pet that grows from your plant. Its size follows the plant (no
/// separate rewards), its mood follows the plant's health and your care.
/// Stored on the pair as `pet`.
@immutable
class Pet {
  const Pet({
    required this.species,
    required this.name,
    required this.hatchedAt,
    this.lastFed = const {},
    this.lastPlayed = const {},
  });

  factory Pet.fromJson(Map<String, dynamic> j) => Pet(
        species: j['species'] as String? ?? 'bunny',
        name: j['name'] as String? ?? '',
        hatchedAt: _date(j['hatchedAt']) ?? DateTime.now(),
        lastFed: _map(j['lastFed']).map((k, v) => MapEntry(k, _date(v) ?? DateTime(0))),
        lastPlayed: _map(j['lastPlayed']).map((k, v) => MapEntry(k, _date(v) ?? DateTime(0))),
      );

  /// The plant grows an egg at this stage (a 7-day streak).
  static const hatchStage = 3;
  static const maxName = 20;

  final String species;
  final String name;
  final DateTime hatchedAt;

  /// uid → when they last fed / played.
  final Map<String, DateTime> lastFed;
  final Map<String, DateTime> lastPlayed;

  PetSpecies get info => PetSpecies.byId(species);

  /// 0 baby · 1 little · 2 grown · 3 legendary, from the plant's stage.
  static int lifeStage(int plantStage) => switch (plantStage) {
        < 5 => 0,
        < 7 => 1,
        < 8 => 2,
        _ => 3,
      };

  static const lifeStageNames = ['Baby', 'Little', 'Grown', 'Legendary'];

  static bool _today(DateTime? t, DateTime now) =>
      t != null && t.year == now.year && t.month == now.month && t.day == now.day;

  bool fedToday(DateTime now) => lastFed.values.any((t) => _today(t, now));
  bool playedToday(DateTime now) => lastPlayed.values.any((t) => _today(t, now));
  bool fedBy(String uid, DateTime now) => _today(lastFed[uid], now);
  bool playedBy(String uid, DateTime now) => _today(lastPlayed[uid], now);

  PetMood mood(DateTime now, {required PlantHealth plant, required List<String> members}) {
    if (plant == PlantHealth.wilted) return PetMood.sleepy;
    if (!fedToday(now)) return PetMood.hungry;
    if (!playedToday(now)) return PetMood.bored;
    final both = members.isNotEmpty &&
        members.every((m) => _today(lastFed[m], now) || _today(lastPlayed[m], now));
    return both ? PetMood.overjoyed : PetMood.happy;
  }

  Pet copyWith({String? name, Map<String, DateTime>? lastFed, Map<String, DateTime>? lastPlayed}) => Pet(
        species: species,
        name: name ?? this.name,
        hatchedAt: hatchedAt,
        lastFed: lastFed ?? this.lastFed,
        lastPlayed: lastPlayed ?? this.lastPlayed,
      );

  Map<String, dynamic> toJson() => {
        'species': species,
        'name': name,
        'hatchedAt': _ms(hatchedAt),
        'lastFed': lastFed.map((k, v) => MapEntry(k, _ms(v))),
        'lastPlayed': lastPlayed.map((k, v) => MapEntry(k, _ms(v))),
      };
}

/// A decoration for the pet's home. [unlockStage] > 0 means it's a reward:
/// free once your plant reaches that stage.
@immutable
class Decor {
  const Decor(this.id, this.emoji, this.name, {this.cost = 0, this.unlockStage = 0});

  final String id;
  final String emoji;
  final String name;
  final int cost;
  final int unlockStage;

  bool get isReward => unlockStage > 0;

  static const all = [
    Decor('rug', '🧶', 'Cozy rug', cost: 30),
    Decor('sofa', '🛋️', 'Sofa', cost: 60),
    Decor('bed', '🛏️', 'Pet bed', cost: 50),
    Decor('lamp', '🪔', 'Lamp', cost: 30),
    Decor('books', '📚', 'Bookshelf', cost: 40),
    Decor('painting', '🖼️', 'Painting', cost: 50),
    Decor('candles', '🕯️', 'Candles', cost: 25),
    Decor('teddy', '🧸', 'Teddy', cost: 35),
    Decor('guitar', '🎸', 'Guitar', cost: 70),
    Decor('aquarium', '🐠', 'Aquarium', cost: 90),
    Decor('balloons', '🎈', 'Balloons', cost: 20),
    Decor('disco', '🪩', 'Disco ball', cost: 120),
    Decor('lantern', '🏮', 'Lantern', cost: 45),
    Decor('cactus', '🌵', 'Cactus', cost: 20),
    Decor('tree', '🎄', 'Little tree', cost: 80),
    Decor('heart', '💝', 'Heart box', unlockStage: 3),
    Decor('rainbow', '🌈', 'Rainbow', unlockStage: 5),
    Decor('crown', '👑', 'Crown', unlockStage: 7),
    Decor('castle', '🏰', 'Castle', unlockStage: 8),
  ];

  static Decor? byId(String id) => all.where((d) => d.id == id).firstOrNull;
}

@immutable
class Wallpaper {
  const Wallpaper(this.id, this.name, this.top, this.bottom, {this.cost = 0});

  final String id;
  final String name;

  /// ARGB colours.
  final int top;
  final int bottom;
  final int cost;

  static const all = [
    Wallpaper('peach', 'Peach', 0xFFFFE3D3, 0xFFFFF4EC),
    Wallpaper('lavender', 'Lavender dream', 0xFFE6E0FF, 0xFFF6F3FF, cost: 40),
    Wallpaper('mint', 'Mint', 0xFFD6F5E6, 0xFFF0FBF5, cost: 40),
    Wallpaper('sky', 'Blue sky', 0xFFCFE6FF, 0xFFF0F7FF, cost: 50),
    Wallpaper('sunset', 'Sunset', 0xFFFFC2A8, 0xFFFFE6D6, cost: 70),
    Wallpaper('night', 'Starry night', 0xFF2D2760, 0xFF5A3F84, cost: 100),
  ];

  static Wallpaper byId(String? id) => all.firstWhere((w) => w.id == id, orElse: () => all.first);
}

@immutable
class PlacedDecor {
  const PlacedDecor(this.id, this.x, this.y);

  factory PlacedDecor.fromJson(Map<String, dynamic> j) => PlacedDecor(
        j['id'] as String? ?? '',
        ((j['x'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0),
        ((j['y'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0),
      );

  final String id;

  /// Position in the room, 0..1 from the left / top.
  final double x;
  final double y;

  Map<String, dynamic> toJson() => {'id': id, 'x': x, 'y': y};
}

/// The pet's home, shared by both. Stored on the pair as `home`.
@immutable
class PetHome {
  const PetHome({this.wallpaper = 'peach', this.owned = const [], this.placed = const [], this.spent = 0});

  factory PetHome.fromJson(Map<String, dynamic> j) => PetHome(
        wallpaper: j['wallpaper'] as String? ?? 'peach',
        owned: (j['owned'] as List?)?.cast<String>() ?? const [],
        placed: (j['placed'] as List?)?.map((p) => PlacedDecor.fromJson(_map(p))).toList() ?? const [],
        spent: (j['spent'] as num?)?.toInt() ?? 0,
      );

  static const maxPlaced = 30;

  final String wallpaper;

  /// Bought decorations and wallpapers (ids).
  final List<String> owned;
  final List<PlacedDecor> placed;

  /// Love points spent so far (only ever goes up).
  final int spent;

  bool ownsDecor(Decor d, int plantStage) =>
      owned.contains(d.id) || (d.isReward && plantStage >= d.unlockStage);

  bool ownsWallpaper(Wallpaper w) => w.cost == 0 || owned.contains(w.id);

  PetHome copyWith({String? wallpaper, List<String>? owned, List<PlacedDecor>? placed, int? spent}) => PetHome(
        wallpaper: wallpaper ?? this.wallpaper,
        owned: owned ?? this.owned,
        placed: placed ?? this.placed,
        spent: spent ?? this.spent,
      );

  Map<String, dynamic> toJson() => {
        'wallpaper': wallpaper,
        'owned': owned,
        'placed': placed.map((p) => p.toJson()).toList(),
        'spent': spent,
      };
}

// --------------------------------------------------------------- mood log

/// One day's mood for one member. `pairs/{pairId}/moods/{uid}_{yyyy-mm-dd}`
/// (the last mood set that day wins).
@immutable
class MoodEntry {
  const MoodEntry({required this.uid, required this.date, required this.emoji, required this.label});

  factory MoodEntry.fromJson(Map<String, dynamic> j) => MoodEntry(
        uid: j['uid'] as String? ?? '',
        date: j['date'] as String? ?? '',
        emoji: j['emoji'] as String? ?? '🙂',
        label: j['label'] as String? ?? '',
      );

  final String uid;

  /// yyyy-mm-dd
  final String date;
  final String emoji;
  final String label;

  /// 1 (low) .. 5 (great), for the mood trend.
  int get score => scoreFor(label);

  static int scoreFor(String label) => switch (label.toLowerCase()) {
        'loved' || 'excited' => 5,
        'happy' || 'calm' => 4,
        'sleepy' || 'hungry' || 'cold' => 3,
        'stressed' || 'busy' || 'tired' => 2,
        'sad' || 'sick' => 1,
        _ => 3,
      };

  Map<String, dynamic> toJson() => {'uid': uid, 'date': date, 'emoji': emoji, 'label': label};
}
