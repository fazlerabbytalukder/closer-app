import 'dart:math' as math;

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/models/streak_rules.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/plant_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// Streak + shared plant (F8). The rules live in [StreakRules]; this screen
/// explains them and shows where the pair stands today.
class PlantScreen extends ConsumerStatefulWidget {
  const PlantScreen({super.key});

  @override
  ConsumerState<PlantScreen> createState() => _PlantScreenState();
}

class _PlantScreenState extends ConsumerState<PlantScreen> with SingleTickerProviderStateMixin {
  late final _sway = AnimationController(vsync: this, duration: const Duration(seconds: 3));

  @override
  void initState() {
    super.initState();
    _sway.repeat(reverse: true);
  }

  @override
  void dispose() {
    _sway.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pair = ref.watch(pairProvider).value;
    final me = ref.watch(authUidProvider).value;
    final name = ref.watch(partnerNameProvider);
    final plus = ref.watch(isPlusProvider);
    if (pair == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final s = pair.streak;
    final plant = pair.plant;
    final wilted = plant.health == PlantHealth.wilted;
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final active = s.activeOn(today);
    final meActive = active.contains(me);
    final partnerActive = active.any((u) => u != me);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final monthly = Streak.monthlyFreezes(plus: plus);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your plant'),
        actions: [
          IconButton(
            tooltip: 'How it works',
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () => _showGuide(context, plus: plus, partner: name),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          CloserCard(
            color: wilted ? context.cc.secondaryTint : context.cc.plantTint,
            padding: const EdgeInsets.all(Space.l),
            child: Column(
              children: [
                _StagePill(plant: plant, years: s.years),
                AnimatedBuilder(
                  animation: _sway,
                  builder: (_, _) => PlantArt(
                    stage: plant.stage,
                    health: plant.health,
                    size: 220,
                    sway: reduceMotion || wilted ? 0 : math.sin(_sway.value * math.pi * 2) * 0.6,
                  ),
                ),
                Text('🔥 ${s.count} day streak', style: context.tt.headlineSmall),
                const SizedBox(height: Space.xs),
                Text(
                  _goalText(s, plant),
                  textAlign: TextAlign.center,
                  style: context.tt.bodyMedium?.copyWith(color: context.cc.muted),
                ),
                if (!wilted) ...[
                  const SizedBox(height: Space.m),
                  _GoalBar(streak: s, plant: plant),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.m),
          for (final b in _banners(s, plant, today, now, meActive: meActive, partnerActive: partnerActive, partner: name))
            Padding(padding: const EdgeInsets.only(bottom: Space.s), child: b),
          const SizedBox(height: Space.xs),
          Row(
            children: [
              Expanded(child: _Stat(label: 'Best streak', value: '${s.best}')),
              const SizedBox(width: Space.m),
              Expanded(child: _Stat(label: 'Stage', value: '${plant.stage}/${Plant.maxStage}')),
              const SizedBox(width: Space.m),
              Expanded(child: _Stat(label: 'Freezes left', value: '${s.freezesLeft}/$monthly')),
            ],
          ),
          const SectionHeader('Today'),
          CloserCard(
            child: Column(
              children: [
                _Check(done: meActive, text: 'You interacted'),
                const Divider(height: Space.l),
                _Check(done: partnerActive, text: '$name interacted'),
              ],
            ),
          ),
          const SizedBox(height: Space.s),
          Text(
            'Sending something, a heart tap, or answering the daily question all count. A day counts when you both show up before midnight.',
            style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
          ),
          const SectionHeader('Streak freezes'),
          CloserCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (var i = 0; i < monthly; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: Space.xs),
                        child: Opacity(
                          opacity: i < s.freezesLeft ? 1 : 0.25,
                          child: const Text('🧊', style: TextStyle(fontSize: 26)),
                        ),
                      ),
                    const Spacer(),
                    Text(
                      'Refills ${DateFormat('d MMM').format(DateTime(now.year, now.month + 1))}',
                      style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
                    ),
                  ],
                ),
                const SizedBox(height: Space.s),
                Text(
                  'You get $monthly freeze${monthly == 1 ? '' : 's'} a month${plus ? '' : ' (3 with Plus)'}. '
                  'If a day is missed, one is used automatically and your streak is kept. '
                  'Unused freezes don’t carry over.',
                  style: context.tt.bodyMedium,
                ),
              ],
            ),
          ),
          if (!plus) ...[
            const SizedBox(height: Space.m),
            CloserButton(label: 'Get more freezes with Plus', kind: CloserButtonKind.secondary, onPressed: () => context.push('/paywall?from=freezes')),
          ],
          const SectionHeader('Milestones'),
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              for (final m in Plant.milestones)
                CounterChip(
                  label: m == 365 ? '1 year' : '$m day${m == 1 ? '' : 's'}',
                  icon: s.best >= m ? Icons.check_rounded : Icons.lock_outline_rounded,
                  color: s.best >= m ? Brand.green : context.cc.muted,
                ),
              // Bloom years keep going after the plant is fully grown.
              for (var y = 2; y <= math.max(2, s.best ~/ 365 + 1); y++)
                CounterChip(
                  label: '🌸 $y years',
                  icon: s.best >= y * 365 ? Icons.check_rounded : Icons.lock_outline_rounded,
                  color: s.best >= y * 365 ? Brand.pink : context.cc.muted,
                ),
            ],
          ),
          const SizedBox(height: Space.m),
          Center(
            child: TextButton.icon(
              onPressed: () => _showGuide(context, plus: plus, partner: name),
              icon: const Icon(Icons.help_outline_rounded, size: 18),
              label: const Text('How does the plant work?'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The line under the streak: what it takes to grow next.
String _goalText(Streak s, Plant plant) {
  if (plant.health == PlantHealth.wilted) {
    return 'Your plant is thirsty. Both of you interact today to revive it 💧';
  }
  final next = plant.nextGrowthAt;
  if (next == null) {
    if (s.count < 365) return 'Full bloom 🌸 Keep your streak going together';
    final target = (s.years + 1) * 365;
    final left = target - s.count;
    return 'Bloom year ${s.years + 1}: $left more day${left == 1 ? '' : 's'} to go 🌸';
  }
  final left = next - s.count;
  return '$left more day${left == 1 ? '' : 's'} until it grows into a ${Plant.stageNames[plant.stage + 1].toLowerCase()}';
}

List<Widget> _banners(
  Streak s,
  Plant plant,
  String today,
  DateTime now, {
  required bool meActive,
  required bool partnerActive,
  required String partner,
}) {
  final out = <Widget>[];
  final yesterday = StreakRules.addDays(today, -1);
  String day(String key) {
    if (key == yesterday) return 'yesterday';
    return DateFormat('EEEE').format(DateTime.parse(key));
  }

  bool recent(String? key) => key != null && StreakRules.daysBetween(key, today) <= 2;

  if (plant.health == PlantHealth.wilted && s.lostCount > 0 && recent(s.brokeDate)) {
    out.add(_Banner(
      emoji: '💔',
      tone: _Tone.sad,
      title: 'Your ${s.lostCount}-day streak ended ${day(s.brokeDate!)}',
      body: 'No freeze was left. Your plant kept its size and your best streak is saved. Both show up today to revive it.',
    ));
  } else if (recent(s.lastFrozeDate) && s.count > 0) {
    out.add(_Banner(
      emoji: '🧊',
      tone: _Tone.info,
      title: 'A freeze covered ${day(s.lastFrozeDate!)}',
      body: 'Nobody lost anything: your ${s.count}-day streak is safe.',
    ));
  }

  if (s.bothActiveOn(today)) {
    out.add(_Banner(
      emoji: '✅',
      tone: _Tone.good,
      title: 'Today counts!',
      body: 'Come back tomorrow to make it ${s.count + 1} days.',
    ));
  } else {
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final left = midnight.difference(now);
    final time = left.inHours > 0 ? '${left.inHours}h ${left.inMinutes % 60}m' : '${left.inMinutes}m';
    final who = !meActive && !partnerActive
        ? 'Both of you still need to show up.'
        : !meActive
            ? '$partner is in. Your turn!'
            : 'You’re in. Waiting for $partner.';
    if (s.count == 0) {
      out.add(_Banner(
        emoji: '🌱',
        tone: _Tone.info,
        title: plant.health == PlantHealth.wilted ? 'Revive your plant today' : 'Start your streak today',
        body: who,
      ));
    } else {
      final risky = s.freezesLeft == 0;
      out.add(_Banner(
        emoji: '⏳',
        tone: risky ? _Tone.sad : _Tone.info,
        title: '$time left today',
        body: risky
            ? '$who No freezes left: if today is missed, the streak ends.'
            : '$who If today is missed, a freeze is used automatically.',
      ));
    }
  }
  return out;
}

Future<void> _showGuide(BuildContext context, {required bool plus, required String partner}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.xl),
        children: [
          Text('How your plant works', style: context.tt.headlineSmall),
          const SizedBox(height: Space.xs),
          Text('You grow it together, one day at a time.', style: context.tt.bodyMedium?.copyWith(color: context.cc.muted)),
          const SizedBox(height: Space.l),
          _GuideStep(
            emoji: '🤝',
            title: 'Show up every day, both of you',
            body: 'Send a photo, note or voice, tap the heart, or answer the daily question. '
                'A day counts once you AND $partner have done one of these before midnight.',
          ),
          const _GuideStep(
            emoji: '🔥',
            title: 'Your streak grows by one each day',
            body: 'Doing more on the same day doesn’t add more. One day together = +1.',
          ),
          const _GuideStep(
            emoji: '🌱',
            title: 'The plant grows at milestones',
            body: '1, 3, 7, 14, 30, 60 and 100 days, then full bloom at 1 year (365 days). '
                'It never shrinks.',
          ),
          const _GuideStep(
            emoji: '🔔',
            title: 'A reminder at 8 pm',
            body: 'If your streak is running and someone hasn’t shown up yet, they get a gentle nudge.',
          ),
          _GuideStep(
            emoji: '🧊',
            title: 'Missed a day? A freeze saves you',
            body: 'A freeze is used automatically and your streak is kept (it just doesn’t grow that day). '
                'You get ${plus ? '3 freezes' : '1 freeze (3 with Plus)'} each month. They refill on the 1st and don’t carry over.',
          ),
          const _GuideStep(
            emoji: '💧',
            title: 'No freezes left? The plant gets thirsty',
            body: 'The streak goes back to 0 and the plant wilts. It never dies and keeps its size, and your best streak is saved. '
                'Show up together the next day to revive it. It grows again once your new streak reaches its next milestone.',
          ),
          const _GuideStep(
            emoji: '🌸',
            title: 'After one year: bloom years',
            body: 'At 365 days the plant is in full bloom. Keep going and every extra year together earns a bloom year: '
                '2 years at 730 days, 3 years at 1,095 days and so on. You both get a notification on each one.',
          ),
          const SizedBox(height: Space.m),
          CloserButton(label: 'Got it', onPressed: () => Navigator.pop(context)),
        ],
      ),
    ),
  );
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({required this.emoji, required this.title, required this.body});

  final String emoji;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: context.cc.accentTint, shape: BoxShape.circle),
            child: Text(emoji, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(body, style: context.tt.bodyMedium?.copyWith(color: context.cc.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StagePill extends StatelessWidget {
  const _StagePill({required this.plant, required this.years});

  final Plant plant;
  final int years;

  @override
  Widget build(BuildContext context) {
    final label = plant.health == PlantHealth.wilted
        ? '💧 Thirsty ${Plant.stageNames[plant.stage].toLowerCase()}'
        : years >= 1
            ? '🌸 Full bloom · year ${years + 1}'
            : 'Stage ${plant.stage} · ${Plant.stageNames[plant.stage]}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: context.cc.card.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: context.tt.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: Brand.grey500)),
    );
  }
}

/// Progress from the last milestone to the next growth (or bloom year).
class _GoalBar extends StatelessWidget {
  const _GoalBar({required this.streak, required this.plant});

  final Streak streak;
  final Plant plant;

  @override
  Widget build(BuildContext context) {
    final count = streak.count;
    final int from;
    final int to;
    final next = plant.nextGrowthAt;
    if (next == null) {
      from = count < 365 ? 0 : streak.years * 365;
      to = count < 365 ? 365 : from + 365;
    } else {
      final prev = plant.stage == 0 ? 0 : Plant.milestones[plant.stage - 1];
      from = count >= prev ? prev : 0;
      to = next;
    }
    final value = ((count - from) / (to - from)).clamp(0.0, 1.0);
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 10,
            backgroundColor: context.cc.card.withValues(alpha: 0.7),
            color: Brand.green,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$count', style: context.tt.labelSmall?.copyWith(color: context.cc.muted)),
            Text('$to days', style: context.tt.labelSmall?.copyWith(color: context.cc.muted)),
          ],
        ),
      ],
    );
  }
}

enum _Tone { good, info, sad }

class _Banner extends StatelessWidget {
  const _Banner({required this.emoji, required this.tone, required this.title, required this.body});

  final String emoji;
  final _Tone tone;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      _Tone.good => context.cc.plantTint,
      _Tone.info => context.cc.secondaryTint,
      _Tone.sad => context.cc.accentTint,
    };
    return CloserCard(
      color: color,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(body, style: context.tt.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return CloserCard(
      child: Column(
        children: [
          Text(value, style: context.tt.titleLarge),
          Text(label, textAlign: TextAlign.center, style: context.tt.bodySmall?.copyWith(color: context.cc.muted)),
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.done, required this.text});

  final bool done;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: done ? Brand.green : context.cc.muted),
        const SizedBox(width: Space.m),
        Text(text, style: context.tt.bodyLarge),
      ],
    );
  }
}
