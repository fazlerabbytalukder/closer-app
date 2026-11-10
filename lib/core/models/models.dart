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
    // ignore: avoid_dynamic_calls
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
    this.quietStart,
    this.quietEnd,
  });

  factory NotificationPrefs.fromJson(Map<String, dynamic> j) {
    final quiet = _map(j['quietHours']);
    return NotificationPrefs(
      taps: j['taps'] as bool? ?? true,
      questions: j['questions'] as bool? ?? true,
      reminders: j['reminders'] as bool? ?? true,
      quietStart: quiet['start'] as int?,
      quietEnd: quiet['end'] as int?,
    );
  }

  final bool taps;
  final bool questions;
  final bool reminders;

  /// Quiet hours as hour-of-day (0-23), both null when disabled.
  final int? quietStart;
  final int? quietEnd;

  NotificationPrefs copyWith({
    bool? taps,
    bool? questions,
    bool? reminders,
    int? Function()? quietStart,
    int? Function()? quietEnd,
  }) =>
      NotificationPrefs(
        taps: taps ?? this.taps,
        questions: questions ?? this.questions,
        reminders: reminders ?? this.reminders,
        quietStart: quietStart != null ? quietStart() : this.quietStart,
        quietEnd: quietEnd != null ? quietEnd() : this.quietEnd,
      );

  Map<String, dynamic> toJson() => {
        'taps': taps,
        'questions': questions,
        'reminders': reminders,
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
  });

  factory LatestItem.fromJson(Map<String, dynamic> j) => LatestItem(
        itemId: j['itemId'] as String? ?? '',
        type: ItemType.parse(j['type']),
        thumbPath: j['thumbPath'] as String?,
        caption: j['caption'] as String? ?? '',
        sentAt: _date(j['sentAt']) ?? DateTime.now(),
      );

  final String itemId;
  final ItemType type;
  final String? thumbPath;
  final String caption;
  final DateTime sentAt;

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'type': type.name,
        'thumbPath': thumbPath,
        'caption': caption,
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
    this.activeToday = const [],
  });

  factory Streak.fromJson(Map<String, dynamic> j) => Streak(
        count: j['count'] as int? ?? 0,
        best: j['best'] as int? ?? 0,
        lastBothActiveDate: j['lastBothActiveDate'] as String?,
        freezesLeft: j['freezesLeft'] as int? ?? 1,
        activeToday: (j['activeToday'] as List?)?.cast<String>() ?? const [],
      );

  final int count;
  final int best;

  /// yyyy-mm-dd in the pair's timezone.
  final String? lastBothActiveDate;
  final int freezesLeft;

  /// Member uids who interacted on the current day.
  final List<String> activeToday;

  Map<String, dynamic> toJson() => {
        'count': count,
        'best': best,
        'lastBothActiveDate': lastBothActiveDate,
        'freezesLeft': freezesLeft,
        'activeToday': activeToday,
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

  static int stageForStreak(int streak) =>
      milestones.where((m) => streak >= m).length;

  final int stage;
  final PlantHealth health;
  final String species;

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
  final DateTime createdAt;

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
        'createdAt': _ms(createdAt),
      };
}

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

  Map<String, dynamic> toJson() =>
      {'senderId': senderId, 'kind': kind, 'createdAt': _ms(createdAt)};
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
      );

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
  });

  final ItemType type;
  final String imagePath;
  final String caption;
  final String? text;
  final NoteStyle? noteStyle;
  final GeoTag? geo;
  final bool saveToMemories;
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
