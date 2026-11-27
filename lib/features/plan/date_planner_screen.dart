import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/features/plan/calendar_screens.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// Dates that count toward the goal: date events whose day is in
/// [from, to) and that have happened (or been rated).
int datesBetween(List<Countdown> events, DateTime from, DateTime to, DateTime now) => events.where((e) {
      if (!e.isDate) return false;
      final d = e.date;
      return !d.isBefore(from) && d.isBefore(to) && (e.done || e.date.isBefore(now));
    }).length;

/// How many goal periods in a row (before the current one) hit the goal.
int goalStreak(List<Countdown> events, DateGoal goal, DateTime now) {
  var streak = 0;
  var start = goal.previousStart(goal.periodStart(now));
  for (var i = 0; i < 104; i++) {
    final end = goal.perMonth ? DateTime(start.year, start.month + 1) : start.add(const Duration(days: 7));
    if (datesBetween(events, start, end, now) < goal.count) break;
    streak++;
    start = goal.previousStart(start);
  }
  // The current period counts once the goal is already reached.
  if (datesBetween(events, goal.periodStart(now), goal.periodEnd(now), now) >= goal.count) streak++;
  return streak;
}

/// Date planner & date-night goals (F18): plan virtual or in-person dates,
/// pick from ideas or your wishlist, set a goal and rate how it went.
class DatePlannerScreen extends ConsumerWidget {
  const DatePlannerScreen({super.key});

  Future<void> _plan(BuildContext context, WidgetRef ref) async {
    final wishes = (ref.read(wishesProvider).value ?? const <Wish>[])
        .where((w) => w.category == WishCategory.date && w.doneAt == null)
        .toList();
    final picked = await showModalBottomSheet<(String, String, bool)>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _IdeaSheet(wishes: wishes),
    );
    if (picked == null || !context.mounted) return;
    final (emoji, title, virtual) = picked;
    final q = Uri(queryParameters: {
      'category': 'date',
      if (title.isNotEmpty) 'title': title,
      if (emoji.isNotEmpty) 'emoji': emoji,
      'virtual': virtual ? '1' : '0',
    }).query;
    await context.push('/calendar/edit?$q');
  }

  Future<void> _setGoal(BuildContext context, WidgetRef ref, DateGoal? current) async {
    var count = current?.count ?? 1;
    var perMonth = current?.perMonth ?? false;
    final result = await showModalBottomSheet<DateGoal?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Your date goal', style: ctx.tt.titleLarge),
                const SizedBox(height: Space.m),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Per week')),
                    ButtonSegment(value: true, label: Text('Per month')),
                  ],
                  selected: {perMonth},
                  onSelectionChanged: (v) => setSheet(() => perMonth = v.first),
                ),
                const SizedBox(height: Space.m),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Fewer',
                      onPressed: count > 1 ? () => setSheet(() => count--) : null,
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.l),
                      child: Text('$count', style: ctx.tt.displaySmall?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'More',
                      onPressed: count < DateGoal.maxCount ? () => setSheet(() => count++) : null,
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
                Text(DateGoal(count: count, perMonth: perMonth).label, style: ctx.tt.titleMedium),
                const SizedBox(height: Space.l),
                CloserButton(label: 'Save goal', onPressed: () => Navigator.pop(ctx, DateGoal(count: count, perMonth: perMonth))),
                if (current != null)
                  TextButton(onPressed: () => Navigator.pop(ctx, const DateGoal(count: 0)), child: const Text('Remove goal')),
              ],
            ),
          ),
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    await runAction(context, () => ref.read(backendProvider).setDateGoal(result.count == 0 ? null : result));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventsProvider).value ?? const <Countdown>[];
    final pair = ref.watch(pairProvider).value;
    final me = ref.watch(authUidProvider).value;
    final name = ref.watch(partnerNameProvider);
    final now = DateTime.now();
    final dates = events.where((e) => e.isDate).toList();
    final upcoming = dates.where((e) => !e.isPast(now)).toList()..sort((a, b) => a.date.compareTo(b.date));
    final past = dates.where((e) => e.isPast(now)).toList()..sort((a, b) => b.date.compareTo(a.date));
    final toRate = past.where((e) => me != null && !e.ratings.containsKey(me)).toList();
    final goal = pair?.dateGoal;
    final monthStart = DateTime(now.year, now.month);
    final thisMonth = datesBetween(events, monthStart, DateTime(now.year, now.month + 1), now);
    final allRatings = [for (final e in past) ...e.ratings.values];
    final avg = allRatings.isEmpty ? null : allRatings.reduce((a, b) => a + b) / allRatings.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Date night')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _plan(context, ref),
        icon: const Icon(Icons.favorite_rounded),
        label: const Text('Plan a date'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, 100),
        children: [
          _GoalCard(goal: goal, events: events, now: now, onEdit: () => _setGoal(context, ref, goal)),
          const SizedBox(height: Space.m),
          Row(
            children: [
              Expanded(child: _Stat(value: '$thisMonth', label: 'dates this month')),
              const SizedBox(width: Space.s),
              Expanded(child: _Stat(value: '${past.length}', label: 'dates so far')),
              const SizedBox(width: Space.s),
              Expanded(child: _Stat(value: avg == null ? '–' : '${avg.toStringAsFixed(1)} ❤️', label: 'average rating')),
            ],
          ),
          if (toRate.isNotEmpty) ...[
            const SectionHeader('How was it?'),
            for (final e in toRate.take(3)) _RateCard(event: e, name: name),
          ],
          SectionHeader('Coming up', action: 'Calendar', onAction: () => context.push('/calendar')),
          if (upcoming.isEmpty)
            CloserCard(
              color: context.cc.accentTint,
              onTap: () => _plan(context, ref),
              child: Row(
                children: [
                  const Text('💡', style: TextStyle(fontSize: 28)),
                  const SizedBox(width: Space.m),
                  Expanded(child: Text('No dates planned yet. Pick an idea and put it in the calendar.', style: context.tt.bodyMedium)),
                ],
              ),
            )
          else
            for (final e in upcoming) EventTile(event: e),
          if (past.isNotEmpty) ...[
            const SectionHeader('Our dates'),
            for (final e in past.take(20)) _PastDate(event: e, me: me, name: name),
          ],
        ],
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, required this.events, required this.now, required this.onEdit});

  final DateGoal? goal;
  final List<Countdown> events;
  final DateTime now;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final g = goal;
    if (g == null) {
      return CloserCard(
        onTap: onEdit,
        gradient: const LinearGradient(colors: [Color(0xFFFFE6EF), Color(0xFFF1EDFF)]),
        child: Row(
          children: [
            const Text('🎯', style: TextStyle(fontSize: 34)),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Set a date-night goal', style: context.tt.titleMedium?.copyWith(color: Brand.ink)),
                  Text('Like one date a week. We’ll keep track together.', style: context.tt.bodyMedium?.copyWith(color: Brand.grey700)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final done = datesBetween(events, g.periodStart(now), g.periodEnd(now), now);
    final planned = events.where((e) => e.isDate && !e.date.isBefore(now) && e.date.isBefore(g.periodEnd(now))).length;
    final streak = goalStreak(events, g, now);
    final reached = done >= g.count;
    return CloserCard(
      onTap: onEdit,
      gradient: LinearGradient(colors: reached ? const [Color(0xFFE3F5E4), Color(0xFFF1EDFF)] : const [Color(0xFFFFE6EF), Color(0xFFF1EDFF)]),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            height: 76,
            child: Stack(
              alignment: Alignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: (done / g.count).clamp(0, 1)),
                  duration: 900.ms,
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => CircularProgressIndicator(
                    value: v,
                    strokeWidth: 8,
                    backgroundColor: Colors.white,
                    color: reached ? Brand.green : Brand.pink,
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Text(reached ? '🎉' : '$done/${g.count}', style: context.tt.titleMedium?.copyWith(color: Brand.ink, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.label, style: context.tt.titleMedium?.copyWith(color: Brand.ink)),
                const SizedBox(height: 2),
                Text(
                  reached
                      ? 'Goal reached this ${g.perMonth ? 'month' : 'week'}! 💞'
                      : planned > 0
                          ? '$planned more planned this ${g.perMonth ? 'month' : 'week'}'
                          : '${g.count - done} to go this ${g.perMonth ? 'month' : 'week'}',
                  style: context.tt.bodyMedium?.copyWith(color: Brand.grey700),
                ),
                if (streak > 1)
                  Text('🔥 $streak ${g.perMonth ? 'months' : 'weeks'} in a row', style: context.tt.bodySmall?.copyWith(color: Brand.grey700)),
              ],
            ),
          ),
          const Icon(Icons.tune_rounded, color: Brand.grey700),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return CloserCard(
      padding: const EdgeInsets.symmetric(vertical: Space.m, horizontal: Space.s),
      child: Column(
        children: [
          FittedBox(child: Text(value, style: context.tt.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
          Text(label, textAlign: TextAlign.center, style: context.tt.bodySmall?.copyWith(color: context.cc.muted)),
        ],
      ),
    );
  }
}

class _Hearts extends StatelessWidget {
  const _Hearts({required this.value, this.onTap, this.size = 26});

  final int value;
  final ValueChanged<int>? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          GestureDetector(
            onTap: onTap == null ? null : () => onTap!(i),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Semantics(
                button: onTap != null,
                label: '$i heart${i == 1 ? '' : 's'}',
                child: Icon(
                  i <= value ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  size: size,
                  color: Brand.pink,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RateCard extends ConsumerWidget {
  const _RateCard({required this.event, required this.name});

  final Countdown event;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: CloserCard(
        color: context.cc.accentTint,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${event.emoji} ${event.title}', style: context.tt.titleMedium),
            Text(DateFormat('EEEE d MMMM').format(event.date), style: context.tt.bodySmall?.copyWith(color: context.cc.muted)),
            const SizedBox(height: Space.s),
            _Hearts(
              value: 0,
              size: 32,
              onTap: (v) async {
                hapticMedium();
                final ok = await runAction(context, () => ref.read(backendProvider).rateDate(event.id, v));
                if (ok && context.mounted) showToast(context, v >= 4 ? 'Sounds like a great one 💞' : 'Thanks! Noted for next time');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PastDate extends StatelessWidget {
  const _PastDate({required this.event, required this.me, required this.name});

  final Countdown event;
  final String? me;
  final String name;

  @override
  Widget build(BuildContext context) {
    final mine = me == null ? null : event.ratings[me];
    final theirs = event.ratings.entries.where((e) => e.key != me).map((e) => e.value).firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: CloserCard(
        onTap: () => context.push('/calendar/edit?id=${event.id}'),
        padding: const EdgeInsets.all(Space.s + 4),
        child: Row(
          children: [
            Text(event.emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: Space.s + 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title, style: context.tt.titleSmall),
                  Text(
                    '${DateFormat('d MMM yyyy').format(event.date)} · ${event.isVirtual ? 'online' : 'in person'}',
                    style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (mine != null) Text('You ${'❤️' * mine}', style: const TextStyle(fontSize: 11)),
                if (theirs != null) Text('$name ${'❤️' * theirs}', style: const TextStyle(fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Pick a date idea: built-in ideas (in person / online) or date ideas from
/// your wishlist. Returns (emoji, title, virtual).
class _IdeaSheet extends StatefulWidget {
  const _IdeaSheet({required this.wishes});

  final List<Wish> wishes;

  @override
  State<_IdeaSheet> createState() => _IdeaSheetState();
}

class _IdeaSheetState extends State<_IdeaSheet> {
  bool _virtual = false;

  @override
  Widget build(BuildContext context) {
    final ideas = dateIdeas.where((i) => i.virtual == _virtual).toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.s),
              child: Text('What kind of date?', style: context.tt.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.m),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('In person'), icon: Icon(Icons.favorite_rounded)),
                  ButtonSegment(value: true, label: Text('Online'), icon: Icon(Icons.videocam_rounded)),
                ],
                selected: {_virtual},
                onSelectionChanged: (v) => setState(() => _virtual = v.first),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(Space.m),
                children: [
                  if (widget.wishes.isNotEmpty && !_virtual) ...[
                    Text('From your wishlist', style: context.tt.titleSmall),
                    const SizedBox(height: Space.s),
                    for (final w in widget.wishes)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Text(w.category.emoji, style: const TextStyle(fontSize: 26)),
                        title: Text(w.title),
                        onTap: () => Navigator.pop(context, ('💑', w.title, false)),
                      ),
                    const Divider(),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final i in ideas)
                        ActionChip(
                          avatar: Text(i.emoji),
                          label: Text(i.title),
                          onPressed: () => Navigator.pop(context, (i.emoji, i.title, i.virtual)),
                        ),
                    ],
                  ),
                  const SizedBox(height: Space.m),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, ('💑', '', _virtual)),
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('My own idea'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
