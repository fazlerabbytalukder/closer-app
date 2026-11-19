import 'package:closer_app/core/models/models.dart';

/// What the "Always with me" widget shows: a memory photo that changes every
/// day, a romantic line of the day, and how long since you last met.
abstract final class AlwaysWithMe {
  static const _couple = [
    'You’re my favourite place to be 💞',
    'Every day with you is my favourite day',
    'Distance means so little when you mean so much',
    'I carry your heart with me ✨',
    'Home is wherever you are 🏡',
    'You make ordinary days feel special',
    'Still choosing you, every single day',
    'My heart is wherever you are 💗',
    'Counting down to our next hug 🤗',
    'You + me = my favourite story 📖',
  ];

  static const _friends = [
    'Friends like you are rare ✨',
    'Partner in crime, always 🤝',
    'Life is better with you in it',
    'My favourite person to laugh with 😂',
    'Distance can’t touch this friendship',
    'You’re stuck with me forever 💛',
    'Every adventure is better with you',
    'Thanks for being you 🌻',
  ];

  static int _dayIndex(DateTime d) => DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000;

  /// The line of the day. A partner tap from the last 24 h wins.
  static String message({required PairMode mode, required DateTime now, String partnerName = '', Tap? partnerTap}) {
    if (partnerTap != null && now.difference(partnerTap.createdAt) < const Duration(hours: 24)) {
      final who = partnerName.isEmpty ? 'Your person' : partnerName;
      return '$who ${partnerTap.info.message} ${partnerTap.info.emoji}';
    }
    final lines = mode == PairMode.couple ? _couple : _friends;
    return lines[_dayIndex(now) % lines.length];
  }

  /// A memory photo for today, stable for the whole day. Prefers what your
  /// partner sent; falls back to anything saved to Memories.
  static Item? memoryOfTheDay(List<Item> items, {required String partnerUid, required DateTime now}) {
    bool usable(Item i) =>
        i.saveToMemories && i.thumbPath != null && (i.type == ItemType.photo || i.type == ItemType.location);
    var pool = items.where((i) => usable(i) && i.senderId == partnerUid).toList();
    if (pool.isEmpty) pool = items.where(usable).toList();
    if (pool.isEmpty) return null;
    pool.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return pool[_dayIndex(now) % pool.length];
  }

  /// "Together right now", "Saw each other 5 h ago", "12 days since we met".
  /// Mirrors AlwaysWithMeWidget.sinceLabel in Kotlin.
  static String sinceLabel(DateTime? lastMet, DateTime now) {
    if (lastMet == null) return 'When did you last meet?';
    final d = now.difference(lastMet);
    if (d.isNegative || d.inMinutes < 60) return 'Together right now 💞';
    if (d.inHours < 24) return 'Saw each other ${d.inHours} h ago';
    final days = d.inDays;
    return days == 1 ? '1 day since we met' : '$days days since we met';
  }
}
