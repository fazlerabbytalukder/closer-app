import 'dart:math' as math;

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/plant_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Streak + shared plant (F8). The plant wilts when the streak breaks but
/// never dies.
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
    final nextMilestone = Plant.milestones.where((m) => m > s.count).firstOrNull;
    final meActive = s.activeToday.contains(me);
    final partnerActive = s.activeToday.any((u) => u != me);
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      appBar: AppBar(title: const Text('Your plant')),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          CloserCard(
            color: context.cc.plantTint,
            padding: const EdgeInsets.all(Space.l),
            child: Column(
              children: [
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
                  wilted
                      ? 'Your plant is thirsty. Both of you interact today to revive it 💧'
                      : nextMilestone == null
                          ? 'Fully grown! You two are amazing 🌸'
                          : '${nextMilestone - s.count} more day${nextMilestone - s.count == 1 ? '' : 's'} until it grows',
                  textAlign: TextAlign.center,
                  style: context.tt.bodyMedium?.copyWith(color: context.cc.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.m),
          Row(
            children: [
              Expanded(child: _Stat(label: 'Best streak', value: '${s.best}')),
              const SizedBox(width: Space.m),
              Expanded(child: _Stat(label: 'Stage', value: '${plant.stage}/8')),
              const SizedBox(width: Space.m),
              Expanded(child: _Stat(label: 'Freezes left', value: '${s.freezesLeft}')),
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
            'Sending something, a heart tap, or answering the daily question all count. A day counts when you both show up.',
            style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
          ),
          const SectionHeader('Streak freezes'),
          CloserCard(
            child: Row(
              children: [
                const Text('🧊', style: TextStyle(fontSize: 28)),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Text(
                    plus
                        ? 'You get 3 freezes a month. They’re used automatically if you miss a day.'
                        : 'You get 1 freeze a month (3 with Plus). It’s used automatically if you miss a day.',
                    style: context.tt.bodyMedium,
                  ),
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
                  label: '$m day${m == 1 ? '' : 's'}',
                  icon: s.best >= m ? Icons.check_rounded : Icons.lock_outline_rounded,
                  color: s.best >= m ? Brand.green : context.cc.muted,
                ),
            ],
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
