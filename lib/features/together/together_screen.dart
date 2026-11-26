import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/ads.dart';
import 'package:closer_app/core/services/always_with_me.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/plant_art.dart';
import 'package:closer_app/core/ui/soft_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Row colours from the Figma "together screen": tinted background with a
/// matching outline icon on a white tile.
enum _Tone {
  violet(Color(0xFFEFE9FF), Color(0xFF6A3DF0)),
  blue(Color(0xFFE3E6FF), Color(0xFF2F3BD6)),
  pink(Color(0xFFFFE3F0), Color(0xFFC2185B)),
  mint(Color(0xFFDDFBF4), Color(0xFF0F8F80)),
  yellow(Color(0xFFFFF1CC), Color(0xFF8A5A00));

  _Tone(this.background, this.icon);

  final Color background;
  final Color icon;
}

const _badgeColor = Color(0xFFD6246E);

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

  late _Section _section = _Section.values.firstWhere((s) => s.name == _readPref(), orElse: () => _Section.play);

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
    final top = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          // Violet header with the title and mascots; the streak card
          // overlaps its rounded bottom edge.
          Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(left: 0, right: 0, top: 0, height: top + 160, child: const HeroBackdrop()),
              Positioned(
                right: -8,
                top: top - 10,
                child: Image.asset('assets/together/header_mascots.png', width: 112, height: 124)
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .moveY(begin: 0, end: -5, duration: 1800.ms, curve: Curves.easeInOut),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(20, top + 22, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Together',
                      style: context.tt.headlineLarge?.copyWith(color: Colors.white, fontSize: 40, height: 1.1),
                    ),
                    SizedBox(height: pair != null ? 22 : 70),
                    if (pair != null) _StreakCard(streak: pair.streak),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionSwitch(selected: _section, loveBadge: fresh, onSelect: _select),
                const SizedBox(height: 16),
                ...switch (_section) {
                  _Section.play => _play(context, me),
                  _Section.love => _love(context, me),
                  _Section.plan => _plan(context, pair),
                },
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _gap(List<Widget> tiles) => [
    for (final (i, t) in tiles.indexed) ...[if (i > 0) const SizedBox(height: 14), t],
  ];

  List<Widget> _play(BuildContext context, String? me) {
    final q = ref.watch(todayQuestionProvider).value;
    final games = ref.watch(gamesProvider).value ?? const <Game>[];
    final name = ref.watch(partnerNameProvider);
    final myTurn = games
        .where(
          (g) =>
              (g.status == GameStatus.subjectTurn && g.subjectUid == me) ||
              (g.status == GameStatus.guesserTurn && g.guesserUid == me),
        )
        .length;
    return [
      ..._gap([
        _Tile(
          icon: Icons.wb_sunny_outlined,
          tone: _Tone.yellow,
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
          icon: Icons.psychology_alt_outlined,
          tone: _Tone.violet,
          title: 'How well do you know me?',
          subtitle: myTurn > 0
              ? '$myTurn game${myTurn == 1 ? '' : 's'} waiting for you'
              : 'Answer about yourself, $name guesses',
          badge: myTurn > 0 ? '$myTurn' : null,
          onTap: () => context.push('/games'),
        ),
        _Tile(
          icon: Icons.visibility_off_outlined,
          tone: _Tone.blue,
          title: 'Secret admirer',
          subtitle: 'Send $name an anonymous note or photo, reveal yourself later',
          onTap: () => context.push('/send?tab=note&secret=1'),
        ),
      ]),
      const SizedBox(height: Space.m),
      const AdBanner(),
      Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10),
        child: Row(
          children: [
            Expanded(child: Text('Past questions', style: context.tt.titleLarge?.copyWith(fontSize: 22))),
            TextButton(onPressed: () => context.push('/question/history'), child: const Text('See all')),
          ],
        ),
      ),
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
    final reasonsForMe = capsules
        .where((c) => c.kind == CapsuleKind.reason && c.forUid == me && c.isUnlocked(now))
        .length;
    final sealedLetters = capsules
        .where((c) => c.kind == CapsuleKind.letter && c.forUid == me && !c.isUnlocked(now))
        .length;
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
        icon: Icons.chat_bubble_outline_rounded,
        tone: _Tone.violet,
        title: 'Chat',
        subtitle: unread > 0
            ? '$unread new message${unread == 1 ? '' : 's'} from $name'
            : 'Messages, photos and voice notes, just for you two',
        badge: unread > 0 ? '$unread' : null,
        onTap: () => context.push('/chat'),
      ),
      _Tile(
        icon: Icons.bedtime_outlined,
        tone: _Tone.blue,
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
        icon: Icons.favorite_border_rounded,
        tone: _Tone.pink,
        title: mode == PairMode.couple ? '100 reasons I love you' : '100 reasons you’re special',
        subtitle: newReasons > 0
            ? 'A new reason from $name is waiting!'
            : '$reasonsForMe of 100 from $name · one opens every day',
        badge: newReasons > 0 ? '$newReasons' : null,
        onTap: () => context.push('/reasons'),
      ),
      _Tile(
        icon: Icons.mail_outline_rounded,
        tone: _Tone.mint,
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
        icon: Icons.card_giftcard_rounded,
        tone: _Tone.yellow,
        title: 'Surprise me',
        subtitle: newSurprises > 0 ? 'You have a surprise to unwrap!' : 'Secret notes, photos, compliments and gifts',
        badge: newSurprises > 0 ? '$newSurprises' : null,
        onTap: () => context.push('/surprises'),
      ),
      _Tile(
        icon: Icons.history_rounded,
        tone: _Tone.mint,
        title: mode == PairMode.couple ? 'Our love timeline' : 'Our friendship timeline',
        subtitle: timeline.isEmpty
            ? 'First chat, first date, every big moment'
            : '${timeline.length} moment${timeline.length == 1 ? '' : 's'} so far',
        onTap: () => context.push('/timeline'),
      ),
      _Tile(
        icon: Icons.local_fire_department_outlined,
        tone: _Tone.yellow,
        title: 'Love shrine',
        subtitle: partnerShrine != null && !partnerShrine.isEmpty
            ? '$name built a shrine for you ✨'
            : 'A little space dedicated to $name',
        onTap: () => context.push('/shrine'),
      ),
      _Tile(
        icon: Icons.location_on_outlined,
        tone: _Tone.pink,
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
    final next =
        (events.where((e) => !e.isPast(now)).toList()..sort((a, b) => a.nextMoment(now).compareTo(b.nextMoment(now))))
            .firstOrNull;
    final todos = ref.watch(todosProvider).value ?? const <Todo>[];
    final openTodos = todos.where((t) => !t.isDone).length;
    final forMe = todos.where((t) => !t.isDone && t.assignee == me).length;
    final wishes = ref.watch(wishesProvider).value ?? const <Wish>[];
    final openWishes = wishes.where((w) => w.doneAt == null).length;
    final goal = pair?.dateGoal;
    final nextDate =
        (events.where((e) => e.isDate && !e.isPast(now)).toList()..sort((a, b) => a.date.compareTo(b.date)))
            .firstOrNull;
    final datesDone = goal == null
        ? 0
        : events.where((e) => e.isDate && !e.date.isBefore(goal.periodStart(now)) && e.date.isBefore(now)).length;
    final days = next?.daysLeft(now);
    return _gap([
      _Tile(
        icon: Icons.calendar_month_outlined,
        tone: _Tone.violet,
        title: 'Our calendar',
        subtitle: next == null
            ? 'Dates, trips, birthdays and countdowns'
            : '${next.emoji} ${next.title} · ${days == 0
                  ? 'today'
                  : days == 1
                  ? 'tomorrow'
                  : 'in $days days'}',
        onTap: () => context.push('/calendar'),
      ),
      _Tile(
        icon: Icons.restaurant_outlined,
        tone: _Tone.pink,
        title: 'Date night',
        subtitle: goal != null
            ? '${goal.label} · $datesDone so far this ${goal.perMonth ? 'month' : 'week'}'
            : nextDate != null
            ? 'Next: ${nextDate.title}'
            : 'Plan a date with $name, in person or online',
        onTap: () => context.push('/dates'),
      ),
      _Tile(
        icon: Icons.checklist_rounded,
        tone: _Tone.mint,
        title: 'Our to-dos',
        subtitle: openTodos == 0
            ? 'Shared lists for chores, trips and plans'
            : '$openTodos open${forMe > 0 ? ' · $forMe for you' : ''}',
        badge: forMe > 0 ? '$forMe' : null,
        onTap: () => context.push('/todos'),
      ),
      _Tile(
        icon: Icons.insights_rounded,
        tone: _Tone.blue,
        title: 'Our insights',
        subtitle: 'Milestones, moods and who does what',
        onTap: () => context.push('/insights'),
      ),
      _Tile(
        icon: Icons.auto_awesome_outlined,
        tone: _Tone.yellow,
        title: 'Wishlist',
        subtitle: openWishes == 0
            ? 'Gifts, restaurants, trips and date ideas'
            : '$openWishes wish${openWishes == 1 ? '' : 'es'} to make come true',
        onTap: () => context.push('/wishlist'),
      ),
      _Tile(
        leading: PlantArt(stage: pair?.plant.stage ?? 0, health: pair?.plant.health ?? PlantHealth.healthy, size: 40),
        tone: _Tone.mint,
        title: 'Your plant',
        subtitle: '🔥 ${pair?.streak.count ?? 0} day streak · best ${pair?.streak.best ?? 0}',
        onTap: () => context.push('/plant'),
      ),
    ]);
  }
}

/// Play / Love / Plan switch: white pill track, selected segment is a solid
/// violet pill (Figma).
class _SectionSwitch extends StatelessWidget {
  const _SectionSwitch({required this.selected, required this.loveBadge, required this.onSelect});

  final _Section selected;
  final int loveBadge;
  final ValueChanged<_Section> onSelect;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget segment(_Section s, IconData icon, IconData selectedIcon, String label, {int badge = 0}) {
      final on = s == selected;
      final fg = on ? Colors.white : context.cs.onSurface;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              height: 44,
              decoration: BoxDecoration(
                color: on ? Brand.purple : Brand.purple.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(on ? selectedIcon : icon, size: 20, color: fg),
                  const SizedBox(width: 8),
                  Text(label, style: context.tt.labelLarge?.copyWith(color: fg)),
                  if (badge > 0) ...[const SizedBox(width: 8), _CountBadge('$badge', size: 20)],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 54,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: context.cc.card,
        borderRadius: BorderRadius.circular(27),
        boxShadow: dark ? null : softCardShadow,
      ),
      child: Row(
        children: [
          segment(_Section.play, Icons.casino_outlined, Icons.casino_rounded, 'Play'),
          segment(_Section.love, Icons.favorite_border_rounded, Icons.favorite_rounded, 'Love', badge: loveBadge),
          segment(_Section.plan, Icons.calendar_today_outlined, Icons.calendar_today_rounded, 'Plan'),
        ],
      ),
    );
  }
}

/// Round pink count badge.
class _CountBadge extends StatelessWidget {
  const _CountBadge(this.label, {this.size = 24});

  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      constraints: BoxConstraints(minWidth: size),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: _badgeColor, borderRadius: BorderRadius.circular(size / 2)),
      child: Text(
        label,
        style: context.tt.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
      ),
    );
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
      icon: Icons.pets_rounded,
      tone: _Tone.mint,
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
      icon: Icons.speed_rounded,
      tone: _Tone.pink,
      title: 'How much do you miss me?',
      subtitle: subtitle,
      badge: partnerAnswered && m?.myValue == null && !(m?.revealed ?? false) ? '1' : null,
      onTap: () => context.push('/miss-meter'),
    );
  }
}

/// Tinted list row (Figma): white icon tile, title + subtitle, pink count
/// badge or a chevron.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.icon,
    this.leading,
    this.badge,
  });

  final IconData? icon;
  final Widget? leading;
  final _Tone tone;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(24);
    return Material(
      color: dark ? tone.icon.withValues(alpha: 0.16) : tone.background,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: dark ? context.cc.card : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: leading ?? Icon(icon, color: tone.icon, size: 22),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.tt.titleSmall?.copyWith(fontSize: 15.5)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.tt.bodyMedium?.copyWith(color: context.cc.muted, fontSize: 13.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (badge != null)
                _CountBadge(badge!)
              else
                Icon(Icons.chevron_right_rounded, color: context.cs.onSurface),
            ],
          ),
        ),
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
      return Text(
        'Answered questions will collect here.',
        style: context.tt.bodyMedium?.copyWith(color: context.cc.muted),
      );
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(20);
    return Column(
      children: [
        for (final q in past.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DecoratedBox(
              decoration: BoxDecoration(borderRadius: radius, boxShadow: dark ? null : softCardShadow),
              child: Material(
                color: context.cc.card,
                borderRadius: radius,
                child: InkWell(
                  borderRadius: radius,
                  onTap: () => context.push('/question/history'),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            q.text,
                            style: context.tt.titleSmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(q.date.substring(5), style: context.tt.bodySmall?.copyWith(color: context.cc.muted)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// White streak card on the header edge: mascot, title and this week's days.
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
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: context.cc.card,
        borderRadius: BorderRadius.circular(32),
        boxShadow: dark ? null : softCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Image.asset('assets/together/streak_mascot.png', width: 78, height: 86)
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .moveY(begin: 0, end: -4, duration: 1600.ms, curve: Curves.easeInOut),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hot ? '${streak.count} Day${streak.count == 1 ? '' : 's'} Streak' : 'Start a streak',
                      style: context.tt.headlineSmall?.copyWith(fontSize: 24),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hot
                          ? 'Best ${streak.best} · ${streak.freezesLeft} freeze${streak.freezesLeft == 1 ? '' : 's'} left'
                          : 'Both send something today to begin',
                      style: context.tt.bodyLarge?.copyWith(color: context.cc.muted, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(6, 12, 6, 12),
            decoration: BoxDecoration(
              color: dark ? Brand.purple.withValues(alpha: 0.14) : Brand.grey100,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Column(
                      children: [
                        Text(labels[i], style: context.tt.labelSmall?.copyWith(color: context.cc.muted)),
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
    final filled = done || today;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? Brand.purple : Colors.transparent,
        boxShadow: today ? [BoxShadow(color: Brand.purple.withValues(alpha: 0.35), blurRadius: 10)] : null,
      ),
      child: done && !today
          ? const Icon(Icons.check_rounded, size: 17, color: Colors.white)
          : Text(
              '$day',
              style: context.tt.labelLarge?.copyWith(
                color: filled
                    ? Colors.white
                    : future
                    ? context.cc.muted
                    : context.cs.onSurface,
              ),
            ),
    );
  }
}
