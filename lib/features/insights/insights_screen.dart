import 'dart:math' as math;

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/features/love/love_widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

const _partnerColor = Color(0xFFFF6B8A);

/// "You" in charts: purple, so it never matches the partner's pink (the
/// theme accent is pink in couple mode).
const _meColor = Color(0xFF1770FF);

/// Something you did together, with who did it and when (for charts).
typedef Act = ({String uid, DateTime at, String kind});

/// Everything the insights are built from, gathered from the providers.
@immutable
class InsightData {
  const InsightData({
    required this.me,
    required this.partner,
    required this.pair,
    required this.acts,
    required this.items,
    required this.capsules,
    required this.events,
    required this.moods,
    required this.missMeters,
    required this.goodnights,
    required this.games,
    required this.timeline,
  });

  final String me;
  final String partner;
  final Pair pair;
  final List<Act> acts;
  final List<Item> items;
  final List<Capsule> capsules;
  final List<Countdown> events;
  final List<MoodEntry> moods;
  final List<MissMeter> missMeters;
  final List<Goodnight> goodnights;
  final List<Game> games;
  final List<TimelineEntry> timeline;

  /// Activity counts per week for the last [weeks] weeks (oldest first),
  /// split into (mine, theirs).
  List<(DateTime, int, int)> weekly(DateTime now, {int weeks = 8}) {
    final today = DateTime(now.year, now.month, now.day);
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    return [
      for (var w = weeks - 1; w >= 0; w--)
        () {
          final start = thisMonday.subtract(Duration(days: 7 * w));
          final end = start.add(const Duration(days: 7));
          final inWeek = acts.where((a) => !a.at.isBefore(start) && a.at.isBefore(end));
          return (start, inWeek.where((a) => a.uid == me).length, inWeek.where((a) => a.uid == partner).length);
        }(),
    ];
  }

  /// (mine, theirs) for one kind of activity.
  (int, int) split(String kind) {
    final k = acts.where((a) => a.kind == kind);
    return (k.where((a) => a.uid == me).length, k.where((a) => a.uid == partner).length);
  }
}

final _insightsProvider = Provider<InsightData?>((ref) {
  final me = ref.watch(authUidProvider).value;
  final pair = ref.watch(pairProvider).value;
  if (me == null || pair == null) return null;
  final partner = pair.partnerOf(me);
  final items = ref.watch(itemsProvider).value ?? const <Item>[];
  final messages = ref.watch(messagesProvider).value ?? const <ChatMessage>[];
  final capsules = ref.watch(capsulesProvider).value ?? const <Capsule>[];
  final goodnights = ref.watch(goodnightsProvider).value ?? const <Goodnight>[];
  final events = ref.watch(eventsProvider).value ?? const <Countdown>[];
  final todos = ref.watch(todosProvider).value ?? const <Todo>[];
  final acts = <Act>[
    for (final i in items) (uid: i.senderId, at: i.createdAt, kind: 'items'),
    for (final m in messages)
      if (!m.isDeleted && !m.isEvent) (uid: m.senderId, at: m.createdAt, kind: 'chat'),
    for (final c in capsules) (uid: c.authorId, at: c.createdAt, kind: 'love'),
    for (final g in goodnights)
      for (final e in g.entries.entries)
        if (e.value.sentAt != null) (uid: e.key, at: e.value.sentAt!, kind: 'goodnight'),
    for (final t in todos)
      if (t.doneBy != null && t.doneAt != null) (uid: t.doneBy!, at: t.doneAt!, kind: 'todos'),
  ];
  return InsightData(
    me: me,
    partner: partner,
    pair: pair,
    acts: acts,
    items: items,
    capsules: capsules,
    events: events,
    moods: ref.watch(moodLogProvider).value ?? const [],
    missMeters: ref.watch(missMetersProvider).value ?? const [],
    goodnights: goodnights,
    games: ref.watch(gamesProvider).value ?? const [],
    timeline: ref.watch(timelineProvider).value ?? const [],
  );
});

/// Relationship progress & insights (F17): milestones, activity, who does
/// what, mood trends and memorable moments.
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(_insightsProvider);
    final name = ref.watch(partnerNameProvider);
    if (d == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final now = DateTime.now();
    final since = d.pair.anniversary ?? d.pair.pairedAt;
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(since.year, since.month, since.day)).inDays;
    final couple = d.pair.mode == PairMode.couple;

    return Scaffold(
      appBar: AppBar(title: const Text('Our insights')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
        children: [
          CloserCard(
            gradient: LinearGradient(colors: context.cc.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$days',
                        style: context.tt.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        d.pair.anniversary != null
                            ? (couple ? 'days together' : 'days of friendship')
                            : 'days on Duosy',
                        style: context.tt.titleMedium?.copyWith(color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '🔥 ${d.pair.streak.count} day streak',
                      style: context.tt.titleSmall?.copyWith(color: Colors.white),
                    ),
                    Text('best ${d.pair.streak.best}', style: context.tt.bodySmall?.copyWith(color: Colors.white70)),
                    Text(
                      '💗 ${d.pair.lovePointsEarned} love points',
                      style: context.tt.bodySmall?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SectionHeader('Milestones'),
          _Milestones(d: d, name: name),
          const SectionHeader('Time together, week by week'),
          _WeeklyChart(d: d, name: name, now: now),
          const SectionHeader('Who does what'),
          _Participation(d: d, name: name),
          const SectionHeader('Mood, last 2 weeks'),
          _MoodTrend(d: d, name: name, now: now),
          const SectionHeader('By the numbers'),
          _Numbers(d: d, name: name),
          const SectionHeader('Memorable moments'),
          _Moments(d: d),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: context.tt.labelSmall),
      ],
    );
    return Row(
      children: [
        dot(_meColor, 'You'),
        const SizedBox(width: Space.m),
        dot(_partnerColor, name),
      ],
    );
  }
}

class _Milestones extends StatelessWidget {
  const _Milestones({required this.d, required this.name});

  final InsightData d;
  final String name;

  @override
  Widget build(BuildContext context) {
    final items = [...d.items]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final best = d.pair.streak.best;
    final datesDone = d.events.where((e) => e.isDate && (e.done || e.date.isBefore(DateTime.now()))).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final lettersRead = d.capsules.where((c) => c.kind == CapsuleKind.letter && c.openedAt != null).toList()
      ..sort((a, b) => a.openedAt!.compareTo(b.openedAt!));
    final reasonsRevealed = d.capsules
        .where((c) => c.kind == CapsuleKind.reason && c.isUnlocked(DateTime.now()))
        .length;
    final list = <(String, String, bool, String)>[
      ('📲', 'Connected on Duosy', true, DateFormat('d MMM yyyy').format(d.pair.pairedAt)),
      (
        '📸',
        'First photo',
        items.isNotEmpty,
        items.isEmpty ? 'Send one!' : DateFormat('d MMM yyyy').format(items.first.createdAt),
      ),
      ('🔥', '7-day streak', best >= 7, best >= 7 ? 'Done' : '$best / 7'),
      ('🌿', '30-day streak', best >= 30, best >= 30 ? 'Done' : '$best / 30'),
      ('💯', '100-day streak', best >= 100, best >= 100 ? 'Done' : '$best / 100'),
      ('🌸', 'A whole year', best >= 365, best >= 365 ? 'Full bloom!' : '$best / 365'),
      ('🗂️', '100 shared memories', items.length >= 100, '${math.min(items.length, 100)} / 100'),
      (
        '💑',
        'First date planned & done',
        datesDone.isNotEmpty,
        datesDone.isEmpty ? 'Plan one' : DateFormat('d MMM yyyy').format(datesDone.first.date),
      ),
      (
        '💌',
        'First letter opened',
        lettersRead.isNotEmpty,
        lettersRead.isEmpty ? 'Write one' : DateFormat('d MMM yyyy').format(lettersRead.first.openedAt!),
      ),
      ('💗', '25 reasons revealed', reasonsRevealed >= 25, '${math.min(reasonsRevealed, 25)} / 25'),
      (
        '☀️',
        '50 daily questions',
        d.pair.stats.questionsAnswered >= 50,
        '${math.min(d.pair.stats.questionsAnswered, 50)} / 50',
      ),
      (
        '🐣',
        'Pet hatched',
        d.pair.pet != null,
        d.pair.pet == null ? 'Grow your plant' : DateFormat('d MMM yyyy').format(d.pair.pet!.hatchedAt),
      ),
    ];
    final done = list.where((m) => m.$3).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$done of ${list.length} reached', style: context.tt.bodySmall?.copyWith(color: context.cc.muted)),
        const SizedBox(height: Space.s),
        SizedBox(
          height: 118,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.s),
            itemBuilder: (_, i) {
              final (emoji, title, reached, sub) = list[i];
              return Container(
                width: 112,
                padding: const EdgeInsets.all(Space.s + 2),
                decoration: BoxDecoration(
                  color: reached ? context.cc.accentTint : context.cc.card,
                  borderRadius: BorderRadius.circular(Radii.small + 6),
                  border: Border.all(color: reached ? context.cc.accent : Colors.transparent, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Opacity(
                      opacity: reached ? 1 : 0.35,
                      child: Text(emoji, style: const TextStyle(fontSize: 26)),
                    ),
                    const Spacer(),
                    Text(title, maxLines: 2, style: context.tt.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.tt.labelSmall?.copyWith(color: context.cc.muted),
                    ),
                  ],
                ),
              ).animate(delay: (i * 40).ms).fadeIn().moveX(begin: 12, end: 0);
            },
          ),
        ),
      ],
    );
  }
}

class _WeeklyChart extends StatelessWidget {
  const _WeeklyChart({required this.d, required this.name, required this.now});

  final InsightData d;
  final String name;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final weeks = d.weekly(now);
    final maxV = weeks.map((w) => math.max(w.$2, w.$3)).fold<int>(1, math.max);
    final total = weeks.fold<int>(0, (s, w) => s + w.$2 + w.$3);
    return CloserCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$total things shared in 8 weeks', style: context.tt.titleSmall),
          Text(
            'Photos, notes, messages, love notes, goodnights and finished to-dos',
            style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
          ),
          const SizedBox(height: Space.m),
          SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (i, (start, mine, theirs)) in weeks.indexed)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _Bar(value: mine / maxV, color: _meColor, delay: i * 60, tooltip: 'You: $mine'),
                            const SizedBox(width: 2),
                            _Bar(
                              value: theirs / maxV,
                              color: _partnerColor,
                              delay: i * 60 + 30,
                              tooltip: '$name: $theirs',
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('d/M').format(start),
                          style: context.tt.labelSmall?.copyWith(fontSize: 9, color: context.cc.muted),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.s),
          _Legend(name: name),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color, required this.delay, required this.tooltip});

  final double value;
  final Color color;
  final int delay;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value),
        duration: Duration(milliseconds: 700 + delay),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Container(
          width: 9,
          height: 4 + 104 * v,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        ),
      ),
    );
  }
}

class _Participation extends StatelessWidget {
  const _Participation({required this.d, required this.name});

  final InsightData d;
  final String name;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('📸', 'Photos & notes', d.split('items')),
      ('💬', 'Chat messages', d.split('chat')),
      ('💌', 'Reasons, letters & surprises', d.split('love')),
      ('🌙', 'Goodnights', d.split('goodnight')),
      ('✅', 'To-dos finished', d.split('todos')),
    ].where((r) => r.$3.$1 + r.$3.$2 > 0).toList();
    if (rows.isEmpty) {
      return Text(
        'Start sharing and you’ll see who does what here.',
        style: context.tt.bodyMedium?.copyWith(color: context.cc.muted),
      );
    }
    return CloserCard(
      child: Column(
        children: [
          for (final (emoji, label, (mine, theirs)) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s + 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('$emoji $label', style: context.tt.titleSmall),
                      const Spacer(),
                      Text('$mine · $theirs', style: context.tt.labelMedium?.copyWith(color: context.cc.muted)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: SizedBox(
                      height: 10,
                      child: Row(
                        children: [
                          if (mine > 0)
                            Expanded(
                              flex: mine,
                              child: const ColoredBox(color: _meColor),
                            ),
                          if (theirs > 0)
                            Expanded(
                              flex: theirs,
                              child: const ColoredBox(color: _partnerColor),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _Legend(name: name),
        ],
      ),
    );
  }
}

class _MoodTrend extends StatelessWidget {
  const _MoodTrend({required this.d, required this.name, required this.now});

  final InsightData d;
  final String name;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final days = [for (var i = 13; i >= 0; i--) now.subtract(Duration(days: i))];
    String key(DateTime t) =>
        '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    List<int?> series(String uid) => [
      for (final day in days) d.moods.where((m) => m.uid == uid && m.date == key(day)).firstOrNull?.score,
    ];
    final mine = series(d.me);
    final theirs = series(d.partner);
    if (mine.every((v) => v == null) && theirs.every((v) => v == null)) {
      return CloserCard(
        onTap: () => context.push('/mood'),
        child: Text('Set your mood each day and your trends show up here 😊', style: context.tt.bodyMedium),
      );
    }
    String common(String uid) {
      final counts = <String, int>{};
      for (final m in d.moods.where((m) => m.uid == uid)) {
        counts['${m.emoji} ${m.label}'] = (counts['${m.emoji} ${m.label}'] ?? 0) + 1;
      }
      if (counts.isEmpty) return '–';
      return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }

    return CloserCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 120,
            child: CustomPaint(
              size: Size.infinite,
              painter: _MoodPainter(
                mine: mine,
                theirs: theirs,
                me: _meColor,
                partner: _partnerColor,
                grid: context.cc.muted.withValues(alpha: 0.2),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('d MMM').format(days.first),
                style: context.tt.labelSmall?.copyWith(color: context.cc.muted),
              ),
              Text('Today', style: context.tt.labelSmall?.copyWith(color: context.cc.muted)),
            ],
          ),
          const SizedBox(height: Space.s),
          _Legend(name: name),
          const SizedBox(height: Space.s),
          Text('Your most common mood: ${common(d.me)}', style: context.tt.bodySmall),
          Text('$name’s most common mood: ${common(d.partner)}', style: context.tt.bodySmall),
        ],
      ),
    );
  }
}

class _MoodPainter extends CustomPainter {
  _MoodPainter({required this.mine, required this.theirs, required this.me, required this.partner, required this.grid});

  final List<int?> mine;
  final List<int?> theirs;
  final Color me;
  final Color partner;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 1; i <= 5; i++) {
      final y = size.height - (i - 1) / 4 * (size.height - 12) - 6;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    void line(List<int?> values, Color color) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final dot = Paint()..color = color;
      final path = Path();
      var started = false;
      for (var i = 0; i < values.length; i++) {
        final v = values[i];
        if (v == null) continue;
        final x = values.length == 1 ? size.width / 2 : i / (values.length - 1) * size.width;
        final y = size.height - (v - 1) / 4 * (size.height - 12) - 6;
        if (started) {
          path.lineTo(x, y);
        } else {
          path.moveTo(x, y);
          started = true;
        }
        canvas.drawCircle(Offset(x, y), 3.5, dot);
      }
      canvas.drawPath(path, paint);
    }

    line(theirs, partner);
    line(mine, me);
  }

  @override
  bool shouldRepaint(_MoodPainter old) => old.mine != mine || old.theirs != theirs || old.me != me;
}

class _Numbers extends StatelessWidget {
  const _Numbers({required this.d, required this.name});

  final InsightData d;
  final String name;

  @override
  Widget build(BuildContext context) {
    final s = d.pair.stats;
    final doneGames = d.games.where((g) => g.status == GameStatus.done).toList();
    final avgGame = doneGames.isEmpty
        ? null
        : doneGames.map((g) => g.score / math.max(1, g.questions.length)).reduce((a, b) => a + b) / doneGames.length;
    final revealed = d.missMeters.where((m) => m.revealed).toList();
    double? avgMiss(String uid) {
      final v = revealed.map((m) => m.values[uid]).whereType<int>().toList();
      return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
    }

    final dates = d.events.where((e) => e.isDate && e.isPast(DateTime.now())).toList();
    final ratings = [for (final e in dates) ...e.ratings.values];
    final bothGoodnight = d.goodnights.where((g) => g.complete(d.pair.memberIds)).length;
    final missMe = avgMiss(d.me);
    final missThem = avgMiss(d.partner);
    final tiles = [
      ('📸', '${s.itemsSent}', 'photos, notes & doodles'),
      ('💗', '${s.tapsSent}', 'love taps'),
      ('☀️', '${s.questionsAnswered}', 'questions answered together'),
      ('🎯', avgGame == null ? '–' : '${(avgGame * 100).round()}%', 'average quiz score'),
      ('🥺', missMe == null ? '–' : '${missMe.round()}% · ${missThem?.round() ?? '–'}%', 'miss-o-meter (you · $name)'),
      (
        '💑',
        '${dates.length}',
        ratings.isEmpty
            ? 'dates'
            : 'dates · ${(ratings.reduce((a, b) => a + b) / ratings.length).toStringAsFixed(1)} ❤️ avg',
      ),
      ('🌙', '$bothGoodnight', 'nights you both said goodnight'),
      ('💌', '${d.capsules.length}', 'reasons, letters & surprises'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: Space.s,
      crossAxisSpacing: Space.s,
      childAspectRatio: 1.45,
      children: [
        for (final (emoji, value, label) in tiles)
          CloserCard(
            padding: const EdgeInsets.all(Space.s + 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 20)),
                const Spacer(),
                FittedBox(
                  child: Text(value, style: context.tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.labelSmall?.copyWith(color: context.cc.muted),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Moments extends StatelessWidget {
  const _Moments({required this.d});

  final InsightData d;

  @override
  Widget build(BuildContext context) {
    final loved = d.items.where((i) => i.reactions.isNotEmpty && i.thumbPath != null).toList()
      ..sort((a, b) => b.reactions.length.compareTo(a.reactions.length));
    final latest = [...d.timeline]..sort((a, b) => b.date.compareTo(a.date));
    if (loved.isEmpty && latest.isEmpty) {
      return Text(
        'React to photos and add moments to your timeline to see them here.',
        style: context.tt.bodyMedium?.copyWith(color: context.cc.muted),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loved.isNotEmpty)
          SizedBox(
            height: 110,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final i in loved.take(8))
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => context.push('/item/${i.id}'),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.small),
                        child: SizedBox(
                          width: 110,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              StoredImage(i.thumbPath),
                              Positioned(
                                right: 4,
                                bottom: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(i.reactions.values.toSet().join(), style: const TextStyle(fontSize: 12)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        for (final t in latest.take(3))
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: CloserCard(
              onTap: () => context.push('/timeline'),
              padding: const EdgeInsets.all(Space.s + 4),
              child: Row(
                children: [
                  Text(t.emoji, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: Space.s + 4),
                  Expanded(child: Text(t.title, style: context.tt.titleSmall)),
                  Text(
                    DateFormat('d MMM yyyy').format(t.date),
                    style: context.tt.labelSmall?.copyWith(color: context.cc.muted),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
