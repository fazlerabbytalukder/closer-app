import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/ads.dart';
import 'package:closer_app/core/services/always_with_me.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/plant_art.dart';
import 'package:closer_app/core/ui/soft_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Together tab, split into Play (daily games), Love (sealed letters,
/// reasons, surprises, timeline, shrine) and Plan (dates and the plant).
class TogetherScreen extends ConsumerStatefulWidget {
  const TogetherScreen({super.key});

  @override
  ConsumerState<TogetherScreen> createState() => _TogetherScreenState();
}

enum _Section { play, love, plan }

class _TogetherScreenState extends ConsumerState<TogetherScreen> {
  static const _prefKey = 'together_section';

  late _Section _section = _Section.values.firstWhere(
    (s) => s.name == _readPref(),
    orElse: () => _Section.play,
  );

  String? _readPref() {
    try {
      return ref.read(prefsProvider).getString(_prefKey);
    } on Object {
      return null;
    }
  }

  void _select(_Section s) {
    setState(() => _section = s);
    try {
      ref.read(prefsProvider).setString(_prefKey, s.name).ignore();
    } on Object {
      // Remembering the tab is only a convenience.
    }
  }

  @override
  Widget build(BuildContext context) {
    final pair = ref.watch(pairProvider).value;
    final me = ref.watch(authUidProvider).value;
    final fresh = ref.watch(newCapsulesProvider).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: softAppBar(context, 'Together'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, 120),
        children: [
          if (pair != null) ...[
            _StreakCard(streak: pair.streak),
            const SizedBox(height: Space.m),
          ],
          SegmentedButton<_Section>(
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(value: _Section.play, label: Text('Play'), icon: Icon(Icons.casino_rounded)),
              ButtonSegment(
                value: _Section.love,
                label: const Text('Love'),
                icon: fresh > 0
                    ? Badge(label: Text('$fresh'), child: const Icon(Icons.favorite_rounded))
                    : const Icon(Icons.favorite_rounded),
              ),
              const ButtonSegment(value: _Section.plan, label: Text('Plan'), icon: Icon(Icons.event_rounded)),
            ],
            selected: {_section},
            onSelectionChanged: (v) => _select(v.first),
          ),
          const SizedBox(height: Space.m),
          ...switch (_section) {
            _Section.play => _play(context, me),
            _Section.love => _love(context, me),
            _Section.plan => _plan(context, pair),
          },
        ],
      ),
    );
  }

  List<Widget> _gap(List<Widget> tiles) => [
        for (final (i, t) in tiles.indexed) ...[if (i > 0) const SizedBox(height: Space.m), t],
      ];

  List<Widget> _play(BuildContext context, String? me) {
    final q = ref.watch(todayQuestionProvider).value;
    final games = ref.watch(gamesProvider).value ?? const <Game>[];
    final name = ref.watch(partnerNameProvider);
    final myTurn = games.where((g) =>
        (g.status == GameStatus.subjectTurn && g.subjectUid == me) ||
        (g.status == GameStatus.guesserTurn && g.guesserUid == me)).length;
    return [
      ..._gap([
        _Tile(
          emoji: '☀️',
          color: context.cc.secondaryTint,
          title: 'Question of the day',
          subtitle: q == null
              ? 'A new question every morning'
              : q.revealed
                  ? 'Revealed — see both answers'
                  : q.myAnswer != null
                      ? 'Waiting for $name'
                      : q.text,
          onTap: () => context.push('/question'),
        ),
        _MissMeterTile(name: name, me: me),
        const _PetTile(),
        _Tile(
          emoji: '🎯',
          color: context.cc.accentTint,
          title: 'How well do you know me?',
          subtitle: myTurn > 0 ? '$myTurn game${myTurn == 1 ? '' : 's'} waiting for you' : 'Answer about yourself, $name guesses',
          badge: myTurn > 0 ? '$myTurn' : null,
          onTap: () => context.push('/games'),
        ),
        _Tile(
          emoji: '🕵️',
          color: context.cc.accentTint,
          title: 'Secret admirer',
          subtitle: 'Send $name an anonymous note or photo, reveal yourself later',
          onTap: () => context.push('/send?tab=note&secret=1'),
        ),
      ]),
      const SizedBox(height: Space.m),
      const AdBanner(),
      SectionHeader('Past questions', action: 'See all', onAction: () => context.push('/question/history')),
      const _PastPreview(),
    ];
  }

  List<Widget> _love(BuildContext context, String? me) {
    final name = ref.watch(partnerNameProvider);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final capsules = ref.watch(capsulesProvider).value ?? const <Capsule>[];
    final timeline = ref.watch(timelineProvider).value ?? const <TimelineEntry>[];
    final shrines = ref.watch(shrinesProvider).value ?? const <String, Shrine>{};
    final partner = ref.watch(partnerUidProvider);
    final mode = ref.watch(pairModeProvider);

    int fresh(CapsuleKind k) => capsules.where((c) => c.kind == k && c.isNewFor(me, now)).length;
    final reasonsForMe = capsules.where((c) => c.kind == CapsuleKind.reason && c.forUid == me && c.isUnlocked(now)).length;
    final sealedLetters = capsules.where((c) => c.kind == CapsuleKind.letter && c.forUid == me && !c.isUnlocked(now)).length;
    final newReasons = fresh(CapsuleKind.reason);
    final newLetters = fresh(CapsuleKind.letter);
    final newSurprises = fresh(CapsuleKind.surprise);
    final partnerShrine = partner == null ? null : shrines[partner];

    final unread = ref.watch(unreadChatProvider);
    final tonight = ref.watch(tonightProvider);
    final saidGoodnight = tonight?.doneBy(me) ?? false;
    final partnerSaid = tonight?.doneBy(partner) ?? false;
    return _gap([
      _Tile(
        emoji: '💬',
        color: context.cc.secondaryTint,
        title: 'Chat',
        subtitle: unread > 0 ? '$unread new message${unread == 1 ? '' : 's'} from $name' : 'Messages, photos and voice notes, just for you two',
        badge: unread > 0 ? '$unread' : null,
        onTap: () => context.push('/chat'),
      ),
      _Tile(
        emoji: '🌙',
        color: context.cc.accentTint,
        title: 'Goodnight ritual',
        subtitle: saidGoodnight && partnerSaid
            ? 'You both said goodnight 💫'
            : partnerSaid
                ? '$name said goodnight. Your turn!'
                : saidGoodnight
                    ? 'Waiting for $name'
                    : 'Goodnight messages, best moments and a kiss',
        badge: partnerSaid && !saidGoodnight ? '1' : null,
        onTap: () => context.push('/goodnight'),
      ),
      _Tile(
        emoji: '💗',
        color: context.cc.accentTint,
        title: mode == PairMode.couple ? '100 reasons I love you' : '100 reasons you’re special',
        subtitle: newReasons > 0 ? 'A new reason from $name is waiting!' : '$reasonsForMe of 100 from $name · one opens every day',
        badge: newReasons > 0 ? '$newReasons' : null,
        onTap: () => context.push('/reasons'),
      ),
      _Tile(
        emoji: '💌',
        color: context.cc.secondaryTint,
        title: 'Letters from the future',
        subtitle: newLetters > 0
            ? 'A letter just opened for you!'
            : sealedLetters > 0
                ? '$sealedLetters sealed letter${sealedLetters == 1 ? '' : 's'} waiting for you'
                : 'Write something $name can open later',
        badge: newLetters > 0 ? '$newLetters' : null,
        onTap: () => context.push('/letters'),
      ),
      _Tile(
        emoji: '🎁',
        color: context.cc.accentTint,
        title: 'Surprise me',
        subtitle: newSurprises > 0 ? 'You have a surprise to unwrap!' : 'Secret notes, photos, compliments and gifts',
        badge: newSurprises > 0 ? '$newSurprises' : null,
        onTap: () => context.push('/surprises'),
      ),
      _Tile(
        emoji: '🗓️',
        color: context.cc.plantTint,
        title: mode == PairMode.couple ? 'Our love timeline' : 'Our friendship timeline',
        subtitle: timeline.isEmpty ? 'First chat, first date, every big moment' : '${timeline.length} moment${timeline.length == 1 ? '' : 's'} so far',
        onTap: () => context.push('/timeline'),
      ),
      _Tile(
        emoji: '🕯️',
        color: context.cc.secondaryTint,
        title: 'Love shrine',
        subtitle: partnerShrine != null && !partnerShrine.isEmpty
            ? '$name built a shrine for you ✨'
            : 'A little space dedicated to $name',
        onTap: () => context.push('/shrine'),
      ),
      _Tile(
        emoji: '💞',
        color: context.cc.plantTint,
        title: 'Always with me',
        subtitle: AlwaysWithMe.sinceLabel(ref.watch(pairProvider).value?.lastMetAt, now),
        onTap: () => context.push('/always'),
      ),
    ]);
  }

  List<Widget> _plan(BuildContext context, Pair? pair) {
    final me = ref.watch(authUidProvider).value;
    final name = ref.watch(partnerNameProvider);
    final now = DateTime.now();
    final events = ref.watch(eventsProvider).value ?? const <Countdown>[];
    final next = (events.where((e) => !e.isPast(now)).toList()..sort((a, b) => a.nextMoment(now).compareTo(b.nextMoment(now)))).firstOrNull;
    final todos = ref.watch(todosProvider).value ?? const <Todo>[];
    final openTodos = todos.where((t) => !t.isDone).length;
    final forMe = todos.where((t) => !t.isDone && t.assignee == me).length;
    final wishes = ref.watch(wishesProvider).value ?? const <Wish>[];
    final openWishes = wishes.where((w) => w.doneAt == null).length;
    final goal = pair?.dateGoal;
    final nextDate = (events.where((e) => e.isDate && !e.isPast(now)).toList()..sort((a, b) => a.date.compareTo(b.date))).firstOrNull;
    final datesDone = goal == null
        ? 0
        : events.where((e) => e.isDate && !e.date.isBefore(goal.periodStart(now)) && e.date.isBefore(now)).length;
    final days = next?.daysLeft(now);
    return _gap([
      _Tile(
        emoji: '📅',
        color: context.cc.secondaryTint,
        title: 'Our calendar',
        subtitle: next == null
            ? 'Dates, trips, birthdays and countdowns'
            : '${next.emoji} ${next.title} · ${days == 0 ? 'today' : days == 1 ? 'tomorrow' : 'in $days days'}',
        onTap: () => context.push('/calendar'),
      ),
      _Tile(
        emoji: '💑',
        color: context.cc.accentTint,
        title: 'Date night',
        subtitle: goal != null
            ? '${goal.label} · $datesDone so far this ${goal.perMonth ? 'month' : 'week'}'
            : nextDate != null
                ? 'Next: ${nextDate.title}'
                : 'Plan a date with $name, in person or online',
        onTap: () => context.push('/dates'),
      ),
      _Tile(
        emoji: '✅',
        color: context.cc.plantTint,
        title: 'Our to-dos',
        subtitle: openTodos == 0 ? 'Shared lists for chores, trips and plans' : '$openTodos open${forMe > 0 ? ' · $forMe for you' : ''}',
        badge: forMe > 0 ? '$forMe' : null,
        onTap: () => context.push('/todos'),
      ),
      _Tile(
        emoji: '📊',
        color: context.cc.accentTint,
        title: 'Our insights',
        subtitle: 'Milestones, moods and who does what',
        onTap: () => context.push('/insights'),
      ),
      _Tile(
        emoji: '🌠',
        color: context.cc.secondaryTint,
        title: 'Wishlist',
        subtitle: openWishes == 0 ? 'Gifts, restaurants, trips and date ideas' : '$openWishes wish${openWishes == 1 ? '' : 'es'} to make come true',
        onTap: () => context.push('/wishlist'),
      ),
      CloserCard(
        color: context.cc.plantTint,
        onTap: () => context.push('/plant'),
        child: Row(
          children: [
            PlantArt(stage: pair?.plant.stage ?? 0, health: pair?.plant.health ?? PlantHealth.healthy, size: 72),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your plant', style: context.tt.titleMedium),
                  Text(
                    '🔥 ${pair?.streak.count ?? 0} day streak · best ${pair?.streak.best ?? 0}',
                    style: context.tt.bodyMedium?.copyWith(color: context.cc.muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    ]);
  }
}

/// The pet that grows from the plant (or the egg it's growing).
class _PetTile extends ConsumerWidget {
  const _PetTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pair = ref.watch(pairProvider).value;
    if (pair == null) return const SizedBox.shrink();
    final pet = pair.pet;
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final ready = pair.plant.stage >= Pet.hatchStage;
    final mood = pet?.mood(now, plant: pair.plant.health, members: pair.memberIds);
    return _Tile(
      emoji: pet?.info.emoji ?? '🥚',
      color: context.cc.plantTint,
      title: pet == null ? 'Your plant’s secret' : '${pet.name} the ${pet.info.name.toLowerCase()}',
      subtitle: pet == null
          ? (ready ? 'Your plant grew an egg! Hatch it together 🐣' : 'Keep your streak going. Something is growing…')
          : '${mood!.emoji} ${pet.name} ${mood.text} · 💗 ${pair.lovePoints}',
      badge: (pet == null && ready) || mood == PetMood.hungry ? '!' : null,
      onTap: () => context.push('/pet'),
    );
  }
}

class _MissMeterTile extends ConsumerWidget {
  const _MissMeterTile({required this.name, required this.me});

  final String name;
  final String? me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(todayMissMeterProvider);
    final partnerAnswered = m?.answeredBy.any((u) => u != me) ?? false;
    final subtitle = m == null
        ? 'Both pick how much, then reveal together'
        : m.revealed
            ? 'Revealed — see who misses who more'
            : m.myValue != null
                ? 'Waiting for $name…'
                : partnerAnswered
                    ? '$name answered. Your turn!'
                    : 'Both pick how much, then reveal together';
    return _Tile(
      emoji: '🥺',
      color: context.cc.accentTint,
      title: 'How much do you miss me?',
      subtitle: subtitle,
      badge: partnerAnswered && m?.myValue == null && !(m?.revealed ?? false) ? '1' : null,
      onTap: () => context.push('/miss-meter'),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.emoji,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final String emoji;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return CloserCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(Radii.small + 4)),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 28)),
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.tt.titleMedium),
                const SizedBox(height: 2),
                Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.tt.bodyMedium?.copyWith(color: context.cc.muted)),
              ],
            ),
          ),
          if (badge != null)
            Badge(label: Text(badge!), backgroundColor: context.cc.accent)
          else
            const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

class _PastPreview extends ConsumerWidget {
  const _PastPreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final past = ref.watch(pastQuestionsProvider).value ?? const <DailyQuestion>[];
    if (past.isEmpty) {
      return Text('Answered questions will collect here.', style: context.tt.bodyMedium?.copyWith(color: context.cc.muted));
    }
    return Column(
      children: [
        for (final q in past.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: CloserCard(
              onTap: () => context.push('/question/history'),
              child: Row(
                children: [
                  Expanded(child: Text(q.text, style: context.tt.bodyLarge, maxLines: 2, overflow: TextOverflow.ellipsis)),
                  Text(q.date.substring(5), style: context.tt.bodySmall?.copyWith(color: context.cc.muted)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// "N Days Streak" hero with the buddy and this week's dots.
class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.streak});

  final Streak streak;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final last = DateTime.tryParse(streak.lastBothActiveDate ?? '');
    bool done(DateTime d) {
      if (last == null || streak.count == 0) return false;
      final diff = last.difference(d).inDays;
      return diff >= 0 && diff < streak.count;
    }

    // Week starting Sunday.
    final start = today.subtract(Duration(days: today.weekday % 7));
    final week = [for (var i = 0; i < 7; i++) start.add(Duration(days: i))];
    const labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final hot = streak.count > 0;
    final accent = context.cc.accent;

    return CloserCard(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.l, Space.m, Space.m),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              if (hot)
                Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [accent.withValues(alpha: 0.35), accent.withValues(alpha: 0)]),
                  ),
                ),
              Buddy(
                color: const Color(0xFF9D8BFF),
                withBody: true,
                mood: hot ? BuddyMood.love : BuddyMood.sleepy,
              ),
            ],
          ),
          const SizedBox(height: Space.s),
          Text(
            hot ? '${streak.count} Day${streak.count == 1 ? '' : 's'} Streak' : 'Start a streak',
            style: context.tt.titleLarge,
          ),
          Text(
            hot ? 'Best ${streak.best} · ${streak.freezesLeft} freeze${streak.freezesLeft == 1 ? '' : 's'} left' : 'Both send something today to begin',
            style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
          ),
          const SizedBox(height: Space.m),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              color: context.cc.accentTint,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          labels[i],
                          style: context.tt.labelSmall?.copyWith(
                            fontSize: 11,
                            color: week[i] == today ? accent : context.cc.muted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _DayDot(
                          day: week[i].day,
                          done: done(week[i]),
                          today: week[i] == today,
                          future: week[i].isAfter(today),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({required this.day, required this.done, required this.today, required this.future});

  final int day;
  final bool done;
  final bool today;
  final bool future;

  @override
  Widget build(BuildContext context) {
    final accent = context.cc.accent;
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? accent : Colors.transparent,
        border: today && !done ? Border.all(color: accent, width: 2) : null,
        boxShadow: today && done ? [BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 10)] : null,
      ),
      child: done
          ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
          : Text(
              '$day',
              style: context.tt.labelSmall?.copyWith(
                fontSize: 11,
                color: future ? context.cc.muted.withValues(alpha: 0.6) : context.cc.muted,
              ),
            ),
    );
  }
}
