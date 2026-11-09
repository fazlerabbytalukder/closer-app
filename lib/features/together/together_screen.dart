import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/ads.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/plant_art.dart';
import 'package:closer_app/core/ui/soft_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class TogetherScreen extends ConsumerWidget {
  const TogetherScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(todayQuestionProvider).value;
    final games = ref.watch(gamesProvider).value ?? const <Game>[];
    final countdowns = ref.watch(countdownsProvider).value ?? const <Countdown>[];
    final pair = ref.watch(pairProvider).value;
    final me = ref.watch(authUidProvider).value;
    final name = ref.watch(partnerNameProvider);
    final myTurn = games.where((g) =>
        (g.status == GameStatus.subjectTurn && g.subjectUid == me) ||
        (g.status == GameStatus.guesserTurn && g.guesserUid == me)).length;

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
          const SizedBox(height: Space.m),
          _Tile(
            emoji: '🎯',
            color: context.cc.accentTint,
            title: 'How well do you know me?',
            subtitle: myTurn > 0 ? '$myTurn game${myTurn == 1 ? '' : 's'} waiting for you' : 'Answer about yourself, $name guesses',
            badge: myTurn > 0 ? '$myTurn' : null,
            onTap: () => context.push('/games'),
          ),
          const SizedBox(height: Space.m),
          _Tile(
            emoji: '📅',
            color: context.cc.secondaryTint,
            title: 'Countdowns',
            subtitle: countdowns.isEmpty
                ? 'Count down to your next date, trip or anniversary'
                : '${countdowns.first.emoji} ${countdowns.first.daysLeft(DateTime.now())} days to ${countdowns.first.title}',
            onTap: () => context.push('/countdowns'),
          ),
          const SizedBox(height: Space.m),
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
          const SizedBox(height: Space.m),
          const AdBanner(),
          SectionHeader('Past questions', action: 'See all', onAction: () => context.push('/question/history')),
          const _PastPreview(),
        ],
      ),
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
