import 'dart:async';

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/widget_bridge.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/plant_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final _installedWidgetsProvider = FutureProvider.autoDispose<int>((ref) => WidgetBridge.installedCount());

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider).value;
    final partner = ref.watch(partnerProvider).value;
    final pair = ref.watch(pairProvider).value;
    final name = ref.watch(partnerNameProvider);
    final installed = ref.watch(_installedWidgetsProvider).value;
    if (me == null || pair == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final partnerUid = pair.partnerOf(me.uid);
    final latest = pair.latestItemByUser[partnerUid];

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(_installedWidgetsProvider);
            await WidgetBridge.updateAll();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.xl),
            children: [
              _PartnerHeader(me: me, partner: partner, name: name),
              const SizedBox(height: Space.m),
              if (installed == 0) ...[
                _WidgetNudge(onTap: () => context.push('/widgets')),
                const SizedBox(height: Space.m),
              ],
              _LatestCard(latest: latest, name: name),
              const SizedBox(height: Space.m),
              _HeartTap(name: name),
              const SizedBox(height: Space.m),
              const _QuestionCard(),
              const SizedBox(height: Space.m),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _PlantCard(pair: pair)),
                  const SizedBox(width: Space.m),
                  const Expanded(child: _CountdownCard()),
                ],
              ),
              const _OnThisDay(),
            ],
          ),
        ),
      ),
    );
  }
}

class _PartnerHeader extends StatelessWidget {
  const _PartnerHeader({required this.me, required this.partner, required this.name});

  final AppUser me;
  final AppUser? partner;
  final String name;

  @override
  Widget build(BuildContext context) {
    final mood = partner?.mood;
    final status = partner?.status;
    final now = DateTime.now();
    return Row(
      children: [
        AvatarPair(
          me: me.displayName,
          partner: partner?.displayName ?? '',
          mePhoto: me.photoUrl,
          partnerPhoto: partner?.photoUrl,
          size: 48,
        ),
        const SizedBox(width: Space.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: context.tt.titleLarge, overflow: TextOverflow.ellipsis),
              Text(
                [
                  if (mood != null) '${mood.emoji} ${mood.label}',
                  if (status != null && status.text.isNotEmpty) status.text,
                  if (mood == null && status == null) 'Their local time ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                ].join(' · '),
                style: context.tt.bodyMedium?.copyWith(color: context.cc.muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        RoundIconButton(
          icon: Icons.mood_rounded,
          label: 'Set your mood',
          onPressed: () => context.push('/mood'),
        ),
      ],
    );
  }
}

class _WidgetNudge extends StatelessWidget {
  const _WidgetNudge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CloserCard(
      onTap: onTap,
      color: context.cc.secondaryTint,
      child: Row(
        children: [
          const Text('📱', style: TextStyle(fontSize: 28)),
          const SizedBox(width: Space.m),
          Expanded(
            child: Text(
              'Add the Closer widget to your home screen so you never miss a thing',
              style: context.tt.titleSmall,
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

class _LatestCard extends ConsumerWidget {
  const _LatestCard({required this.latest, required this.name});

  final LatestItem? latest;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = latest;
    final image = ref.watch(imageUrlProvider(l?.thumbPath)).value;
    if (l == null) {
      return CloserCard(
        child: SizedBox(
          height: 180,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('💌', style: TextStyle(fontSize: 40)),
                const SizedBox(height: Space.s),
                Text('Waiting for $name’s first photo', style: context.tt.titleMedium),
                const SizedBox(height: Space.xs),
                Text('Why not send one first?', style: context.tt.bodyMedium?.copyWith(color: context.cc.muted)),
              ],
            ),
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      label: 'Latest from $name. ${l.caption}. Open to reply',
      child: GestureDetector(
        onTap: () => context.push('/reply'),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.card),
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AppImage(image),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(Space.m, Space.xl, Space.m, Space.m),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xAA000000)],
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (l.caption.isNotEmpty)
                                Text(l.caption, style: context.tt.titleMedium?.copyWith(color: Colors.white)),
                              Text(
                                'From $name · ${timeAgo(l.sentAt)}',
                                style: context.tt.bodySmall?.copyWith(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () => context.push('/reply'),
                          icon: const Icon(Icons.reply_rounded, size: 18),
                          label: const Text('Reply'),
                          style: FilledButton.styleFrom(minimumSize: const Size(48, 40)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Big "thinking of you" heart (F5).
class _HeartTap extends ConsumerStatefulWidget {
  const _HeartTap({required this.name});

  final String name;

  @override
  ConsumerState<_HeartTap> createState() => _HeartTapState();
}

class _HeartTapState extends ConsumerState<_HeartTap> with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(vsync: this, duration: 500.ms);
  final _bursts = <int>[];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _tap() async {
    hapticMedium();
    unawaited(_ctrl.forward(from: 0));
    setState(() => _bursts.add(DateTime.now().microsecondsSinceEpoch));
    final ok = await runAction(context, () => ref.read(backendProvider).sendTap());
    if (ok && mounted) showToast(context, '${widget.name} will feel that 💗');
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authUidProvider).value;
    final tap = ref.watch(latestTapProvider).value;
    final fromPartner = tap != null && tap.senderId != me && DateTime.now().difference(tap.createdAt).inHours < 1;
    final cc = context.cc;
    return CloserCard(
      color: cc.accentTint,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Thinking of ${widget.name}?', style: context.tt.titleMedium),
                const SizedBox(height: 2),
                Text(
                  fromPartner ? '${widget.name} tapped you ${timeAgo(tap.createdAt)} 💗' : 'Tap the heart to send a soft buzz',
                  style: context.tt.bodyMedium?.copyWith(color: context.cc.muted),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 88,
            height: 88,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                for (final b in _bursts)
                  Text('💗', key: ValueKey(b), style: const TextStyle(fontSize: 22))
                      .animate(onComplete: (_) => setState(() => _bursts.remove(b)))
                      .moveY(begin: 0, end: -70, duration: 900.ms, curve: Curves.easeOut)
                      .fadeOut(delay: 400.ms, duration: 500.ms),
                Semantics(
                  button: true,
                  label: 'Send a thinking-of-you tap to ${widget.name}',
                  child: GestureDetector(
                    onTap: _tap,
                    child: ScaleTransition(
                      scale: TweenSequence([
                        TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.8), weight: 1),
                        TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.15), weight: 1),
                        TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 1),
                      ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut)),
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: cc.gradient),
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: cc.accent.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6))],
                        ),
                        child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 38),
                      ),
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

class _QuestionCard extends ConsumerWidget {
  const _QuestionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(todayQuestionProvider).value;
    final name = ref.watch(partnerNameProvider);
    final me = ref.watch(authUidProvider).value;
    if (q == null) return const SizedBox.shrink();
    final answered = q.myAnswer != null;
    final partnerAnswered = q.answeredBy.any((u) => u != me);
    final status = q.revealed
        ? 'Both answered — tap to see! 👀'
        : answered
            ? 'Waiting for $name…'
            : partnerAnswered
                ? '$name answered. Your turn!'
                : 'Answer to unlock $name’s answer';
    return CloserCard(
      onTap: () => context.push('/question'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CounterChip(label: 'Question of the day', icon: Icons.wb_sunny_rounded, color: context.cc.secondary),
              const Spacer(),
              if (q.revealed) const Text('🎉') else if (partnerAnswered && !answered) const Text('⏳'),
            ],
          ),
          const SizedBox(height: Space.s + 4),
          Text(q.text, style: context.tt.titleLarge),
          const SizedBox(height: Space.s),
          Text(status, style: context.tt.bodyMedium?.copyWith(color: context.cc.muted)),
        ],
      ),
    );
  }
}

class _PlantCard extends StatelessWidget {
  const _PlantCard({required this.pair});

  final Pair pair;

  @override
  Widget build(BuildContext context) {
    final wilted = pair.plant.health == PlantHealth.wilted;
    return CloserCard(
      onTap: () => context.push('/plant'),
      color: context.cc.plantTint,
      child: Column(
        children: [
          PlantArt(stage: pair.plant.stage, health: pair.plant.health, size: 96),
          const SizedBox(height: Space.xs),
          Text('🔥 ${pair.streak.count} day${pair.streak.count == 1 ? '' : 's'}', style: context.tt.titleMedium),
          Text(
            wilted ? 'Needs some love' : 'Your streak',
            style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
          ),
        ],
      ),
    );
  }
}

class _CountdownCard extends ConsumerWidget {
  const _CountdownCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(countdownsProvider).value ?? const [];
    final c = list.isEmpty ? null : list.first;
    final days = c?.daysLeft(DateTime.now());
    return CloserCard(
      onTap: () => context.push(c == null ? '/countdowns/edit' : '/countdowns'),
      color: context.cc.secondaryTint,
      child: SizedBox(
        height: 146,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: c == null
              ? [
                  const Text('📅', style: TextStyle(fontSize: 36)),
                  const SizedBox(height: Space.s),
                  Text('Add a date', style: context.tt.titleMedium),
                  Text('to look forward to', style: context.tt.bodySmall?.copyWith(color: context.cc.muted)),
                ]
              : [
                  Text(c.emoji, style: const TextStyle(fontSize: 28)),
                  Text(
                    days == 0 ? 'Today!' : '$days',
                    style: context.tt.displaySmall?.copyWith(color: context.cc.secondary),
                  ),
                  Text(
                    days == 0 ? c.title : '${days == 1 ? 'day' : 'days'} to ${c.title}',
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: context.tt.bodyMedium,
                  ),
                ],
        ),
      ),
    );
  }
}

/// "On this day" memory (F9).
class _OnThisDay extends ConsumerWidget {
  const _OnThisDay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(itemsProvider).value ?? const <Item>[];
    final now = DateTime.now();
    final match = items.where((i) {
      final d = i.createdAt;
      return i.saveToMemories && d.month == now.month && d.day == now.day && d.year < now.year;
    }).firstOrNull;
    if (match == null) return const SizedBox.shrink();
    final years = now.year - match.createdAt.year;
    final image = ref.watch(imageUrlProvider(match.thumbPath)).value;
    return Padding(
      padding: const EdgeInsets.only(top: Space.m),
      child: CloserCard(
        onTap: () => context.push('/item/${match.id}'),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.small),
              child: SizedBox(width: 64, height: 64, child: AppImage(image)),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('On this day', style: context.tt.titleMedium),
                  Text(
                    '$years year${years == 1 ? '' : 's'} ago${match.caption.isEmpty ? '' : ' · ${match.caption}'}',
                    style: context.tt.bodyMedium?.copyWith(color: context.cc.muted),
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
