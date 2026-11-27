import 'dart:math' as math;

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/models/streak_rules.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/plant_art.dart';
import 'package:closer_app/core/ui/soft_ui.dart';
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
    if (pair == null)
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
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

    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          PlainPageHeader(
            title: 'Your plant',
            actions: [
              CircleIconButton(
                icon: Icons.info_outline_rounded,
                tooltip: 'How it works',
                onTap: () => _showGuide(context, plus: plus, partner: name, plant: plant),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Mint hero card: plant, streak and what it takes to grow.
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                  decoration: BoxDecoration(
                    color: SoftTone.mint.fill(context),
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: Column(
                    children: [
                      _StagePill(plant: plant, years: s.years),
                      AnimatedBuilder(
                        animation: _sway,
                        builder: (_, _) => PlantArt(
                          stage: plant.stage,
                          health: plant.health,
                          size: 200,
                          sway: reduceMotion || wilted ? 0 : math.sin(_sway.value * math.pi * 2) * 0.6,
                        ),
                      ),
                      Text(
                        '🔥 ${s.count} day streak',
                        textAlign: TextAlign.center,
                        style: context.tt.headlineSmall?.copyWith(fontSize: 28),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _goalText(s, plant),
                        textAlign: TextAlign.center,
                        style: context.tt.bodyMedium?.copyWith(
                          color: dark ? context.cc.muted : const Color(0xFF2E5E57),
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                      if (!wilted) ...[const SizedBox(height: 16), _GoalBar(streak: s, plant: plant)],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _PetLink(plantStage: plant.stage),
                for (final b in _banners(
                  s,
                  plant,
                  today,
                  now,
                  meActive: meActive,
                  partnerActive: partnerActive,
                  partner: name,
                ))
                  Padding(padding: const EdgeInsets.only(bottom: 12), child: b),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: _Stat(label: 'Best streak', value: '${s.best}'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Stat(label: 'Stage', value: '${plant.stage}/${Plant.maxStage}'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Stat(label: 'Freezes left', value: '${s.freezesLeft}/$monthly'),
                    ),
                  ],
                ),
                const PageSectionTitle('Today'),
                _WhiteCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _Check(done: meActive, text: 'You interacted'),
                      Divider(height: 1, color: context.cs.outlineVariant.withValues(alpha: 0.5)),
                      _Check(done: partnerActive, text: '$name interacted'),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Sending something, a heart tap, or answering the daily question all count. '
                  'A day counts when you both show up before midnight.',
                  style: context.tt.bodySmall?.copyWith(color: context.cc.muted, height: 1.4),
                ),
                const PageSectionTitle('Streak freezes'),
                _WhiteCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          for (var i = 0; i < monthly; i++)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Opacity(
                                opacity: i < s.freezesLeft ? 1 : 0.35,
                                child: Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: SoftTone.violet.fill(context),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(Icons.view_in_ar_outlined, size: 20, color: SoftTone.violet.icon),
                                ),
                              ),
                            ),
                          const Spacer(),
                          Text(
                            'Refills ${DateFormat('d MMM').format(DateTime(now.year, now.month + 1))}',
                            style: context.tt.labelLarge?.copyWith(
                              color: context.cc.muted,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'You get $monthly freeze${monthly == 1 ? '' : 's'} a month${plus ? '' : ' (3 with Plus)'}. '
                        'If a day is missed, one is used automatically and your streak is kept. '
                        'Unused freezes don’t carry over.',
                        style: context.tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.4),
                      ),
                    ],
                  ),
                ),
                if (!plus) ...[
                  const SizedBox(height: Space.m),
                  CloserButton(
                    label: 'Get more freezes with Plus',
                    kind: CloserButtonKind.secondary,
                    onPressed: () => context.push('/paywall?from=freezes'),
                  ),
                ],
                const PageSectionTitle('Milestones'),
                Wrap(
                  spacing: 8,
                  runSpacing: 10,
                  children: [
                    for (final m in Plant.milestones)
                      _MilestonePill(label: m == 365 ? '1 year' : '$m day${m == 1 ? '' : 's'}', done: s.best >= m),
                    // Bloom years keep going after the plant is fully grown.
                    for (var y = 2; y <= math.max(2, s.best ~/ 365 + 1); y++)
                      _MilestonePill(label: '🌸 $y years', done: s.best >= y * 365, bloom: true),
                  ],
                ),
                const SizedBox(height: 18),
                Center(
                  child: TextButton.icon(
                    onPressed: () => _showGuide(context, plus: plus, partner: name, plant: plant),
                    icon: Icon(Icons.help_outline_rounded, size: 20, color: context.cs.primary),
                    label: Text(
                      'How does the plant work?',
                      style: context.tt.titleSmall?.copyWith(color: context.cs.primary, fontWeight: FontWeight.w800),
                    ),
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
    out.add(
      _Banner(
        icon: Icons.heart_broken_outlined,
        tone: _Tone.sad,
        title: 'Your ${s.lostCount}-day streak ended ${day(s.brokeDate!)}',
        body: 'No freeze was left. Your plant kept its size and your best streak is saved. Both show up today to revive it.',
      ),
    );
  } else if (recent(s.lastFrozeDate) && s.count > 0) {
    out.add(
      _Banner(
        icon: Icons.ac_unit_rounded,
        tone: _Tone.info,
        title: 'A freeze covered ${day(s.lastFrozeDate!)}',
        body: 'Nobody lost anything: your ${s.count}-day streak is safe.',
      ),
    );
  }

  if (s.bothActiveOn(today)) {
    out.add(
      _Banner(
        icon: Icons.check_circle_outline_rounded,
        tone: _Tone.good,
        title: 'Today counts!',
        body: 'Come back tomorrow to make it ${s.count + 1} days.',
      ),
    );
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
      out.add(
        _Banner(
          icon: Icons.eco_outlined,
          tone: _Tone.info,
          title: plant.health == PlantHealth.wilted ? 'Revive your plant today' : 'Start your streak today',
          body: who,
        ),
      );
    } else {
      final risky = s.freezesLeft == 0;
      out.add(
        _Banner(
          icon: Icons.hourglass_bottom_rounded,
          tone: risky ? _Tone.sad : _Tone.info,
          title: '$time left today',
          body: risky
              ? '$who No freezes left: if today is missed, the streak ends.'
              : '$who If today is missed, a freeze is used automatically.',
        ),
      );
    }
  }
  return out;
}

Future<void> _showGuide(BuildContext context, {required bool plus, required String partner, required Plant plant}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        final steps = [
          _GuideStep(
            icon: Icons.people_outline_rounded,
            tone: SoftTone.violet,
            title: 'Show up every day, both of you',
            body:
                'Send a photo, note or voice, tap the heart, or answer the daily question. '
                'A day counts once you AND $partner have done one of these before midnight.',
          ),
          const _GuideStep(
            icon: Icons.local_fire_department_outlined,
            tone: SoftTone.yellow,
            title: 'Your streak grows by one each day',
            body: 'Doing more on the same day doesn’t add more. One day together = +1.',
          ),
          const _GuideStep(
            icon: Icons.eco_outlined,
            tone: SoftTone.mint,
            title: 'The plant grows at milestones',
            body:
                '1, 3, 7, 14, 30, 60 and 100 days, then full bloom at 1 year (365 days). '
                'It never shrinks.',
          ),
          const _GuideStep(
            icon: Icons.notifications_none_rounded,
            tone: SoftTone.pink,
            title: 'A reminder at 8 pm',
            body: 'If your streak is running and someone hasn’t shown up yet, they get a gentle nudge.',
          ),
          _GuideStep(
            icon: Icons.view_in_ar_outlined,
            tone: SoftTone.blue,
            title: 'Missed a day? A freeze saves you',
            body:
                'A freeze is used automatically and your streak is kept (it just doesn’t grow that day). '
                'You get ${plus ? '3 freezes' : '1 freeze (3 with Plus)'} each month. '
                'They refill on the 1st and don’t carry over.',
          ),
          const _GuideStep(
            icon: Icons.water_drop_outlined,
            tone: SoftTone.violet,
            title: 'No freezes left? The plant gets thirsty',
            body:
                'The streak goes back to 0 and the plant wilts. It never dies and keeps its size, and your best '
                'streak is saved. Show up together the next day to revive it. It grows again once your new streak '
                'reaches its next milestone.',
          ),
          const _GuideStep(
            icon: Icons.local_florist_outlined,
            tone: SoftTone.pink,
            title: 'After one year: bloom years',
            body:
                'At 365 days the plant is in full bloom. Keep going and every extra year together earns a bloom year: '
                '2 years at 730 days, 3 years at 1,095 days and so on. You both get a notification on each one.',
          ),
        ];
        return Column(
          children: [
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                children: [
                  // Mint header card with the plant (Figma "your plant info screen").
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
                    decoration: BoxDecoration(
                      color: SoftTone.mint.fill(context),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        PlantArt(stage: plant.stage, health: plant.health, size: 84),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'How your plant works',
                                style: context.tt.headlineSmall?.copyWith(fontSize: 24, height: 1.15),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'You grow it together, one day at a time.',
                                style: context.tt.bodyMedium?.copyWith(
                                  color: dark ? context.cc.muted : const Color(0xFF2E5E57),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // All steps in one white card, split by hairlines.
                  Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: context.cc.card,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: dark ? null : softCardShadow,
                    ),
                    child: Column(
                      children: [
                        for (final (i, step) in steps.indexed) ...[
                          if (i > 0) Divider(height: 1, color: context.cs.outlineVariant.withValues(alpha: 0.5)),
                          step,
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: PillButton(label: 'Got it', onPressed: () => Navigator.pop(context)),
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// One rule in the guide: tinted outline-icon tile, bold title, muted text.
class _GuideStep extends StatelessWidget {
  const _GuideStep({required this.icon, required this.tone, required this.title, required this.body});

  final IconData icon;
  final SoftTone tone;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(icon: icon, tone: tone, size: 38, filled: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(body, style: context.tt.bodySmall?.copyWith(color: context.cc.muted, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// White pill at the top of the hero card: stage, thirsty or bloom year.
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(color: context.cc.card, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        style: context.tt.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: context.cc.muted),
      ),
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
    final label = context.tt.labelSmall?.copyWith(color: context.cc.muted, fontWeight: FontWeight.w800);
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 10,
            backgroundColor: context.cc.card,
            color: Brand.green,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$count', style: label),
            Text('$to days', style: label),
          ],
        ),
      ],
    );
  }
}

enum _Tone { good, info, sad }

/// Status row: white card with a mint icon tile (info), mint card (good) or
/// pink card (sad), bold title and a muted line (Figma "Revive your plant").
class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.tone, required this.title, required this.body});

  final IconData icon;
  final _Tone tone;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final fill = switch (tone) {
      _Tone.good => SoftTone.mint.fill(context),
      _Tone.info => null,
      _Tone.sad => SoftTone.pink.fill(context),
    };
    final tile = tone == _Tone.sad ? SoftTone.red : SoftTone.mint;
    return _WhiteCard(
      color: fill,
      child: Row(
        children: [
          IconTile(icon: icon, tone: tile, size: 44, filled: fill == null),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(body, style: context.tt.bodyMedium?.copyWith(color: context.cc.muted, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded card used across this screen: white with a soft shadow, or a
/// flat tint when [color] is given.
class _WhiteCard extends StatelessWidget {
  const _WhiteCard({required this.child, this.color, this.padding = const EdgeInsets.all(16), this.onTap});

  final Widget child;
  final Color? color;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color ?? context.cc.card,
        borderRadius: BorderRadius.circular(24),
        boxShadow: dark || color != null ? null : softCardShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Number + label tile (Best streak, Stage, Freezes left).
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return _WhiteCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 16),
      child: Column(
        children: [
          Text(value, style: context.tt.headlineSmall?.copyWith(fontSize: 26, height: 1.1)),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.tt.labelMedium?.copyWith(color: context.cc.muted, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// "You interacted" row: lavender ring when open, green check when done.
class _Check extends StatelessWidget {
  const _Check({required this.done, required this.text});

  final bool done;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? Brand.green : null,
              border: done ? null : Border.all(color: const Color(0xFFC9BDF5), width: 2),
            ),
            child: done ? const Icon(Icons.check_rounded, size: 17, color: Colors.white) : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(text, style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

/// Milestone pill: mint with a check when reached (pink for bloom years),
/// lavender with a lock when not yet.
class _MilestonePill extends StatelessWidget {
  const _MilestonePill({required this.label, required this.done, this.bloom = false});

  final String label;
  final bool done;
  final bool bloom;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tone = bloom ? SoftTone.pink : SoftTone.mint;
    final fg = done ? tone.icon : context.cc.muted;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
      decoration: BoxDecoration(
        color: done ? tone.fill(context) : (dark ? context.cs.surfaceContainerHigh : const Color(0xFFEDE9F7)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(done ? Icons.check_rounded : Icons.lock_outline_rounded, size: 16, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: context.tt.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// The pet that grows out of the plant: an egg until stage 3, then the pet.
/// Pink card with a white icon tile (Figma "At a 7-day streak...").
class _PetLink extends ConsumerWidget {
  const _PetLink({required this.plantStage});

  final int plantStage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pet = ref.watch(pairProvider).value?.pet;
    final ready = plantStage >= Pet.hatchStage;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _WhiteCard(
        onTap: () => context.push('/pet'),
        color: SoftTone.pink.fill(context),
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: context.cc.card, borderRadius: BorderRadius.circular(14)),
              alignment: Alignment.center,
              child: pet != null
                  ? Text(pet.info.emoji, style: const TextStyle(fontSize: 24))
                  : Icon(Icons.egg_outlined, size: 24, color: SoftTone.pink.icon),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                pet != null
                    ? '${pet.name} lives here. Visit their home'
                    : ready
                    ? 'Your plant grew an egg! Tap to hatch it 🐣'
                    : 'At a ${Plant.milestones[Pet.hatchStage - 1]}-day streak your plant grows a surprise…',
                style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.3),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
