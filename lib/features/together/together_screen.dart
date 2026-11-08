import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/ads.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/plant_art.dart';
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
      appBar: AppBar(title: const Text('Together')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.xl),
        children: [
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
