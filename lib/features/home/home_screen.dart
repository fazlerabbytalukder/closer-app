import 'dart:async';
import 'dart:ui' as ui;

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/widget_bridge.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/soft_ui.dart';
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
      return const Scaffold(backgroundColor: Colors.transparent, body: Center(child: CircularProgressIndicator()));
    }
    final partnerUid = pair.partnerOf(me.uid);
    final latest = pair.latestItemByUser[partnerUid];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_installedWidgetsProvider);
          await WidgetBridge.updateAll();
        },
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _Hero(me: me, partner: partner, pair: pair, name: name),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ProgressCard(me: me, pair: pair, name: name),
                  _Rituals(me: me, pair: pair, name: name),
                  if (installed == 0) ...[
                    const SizedBox(height: Space.m),
                    _WidgetNudge(onTap: () => context.push('/widgets')),
                  ],
                  SectionHeader('Latest from $name'),
                  _LatestCard(latest: latest, name: name),
                  const SizedBox(height: Space.m),
                  _HeartTap(name: name),
                  const SizedBox(height: Space.m),
                  const _QuestionCard(),
                  const _OnThisDay(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _isToday(DateTime? t) {
  if (t == null) return false;
  final n = DateTime.now();
  return t.year == n.year && t.month == n.month && t.day == n.day;
}

/// Purple greeting header with the bear buddy and three stat tiles.
class _Hero extends ConsumerWidget {
  const _Hero({required this.me, required this.partner, required this.pair, required this.name});

  final AppUser me;
  final AppUser? partner;
  final Pair pair;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countdowns = ref.watch(countdownsProvider).value ?? const <Countdown>[];
    final c = countdowns.firstOrNull;
    final days = c?.daysLeft(DateTime.now());
    final mood = partner?.mood;
    final status = partner?.status;
    final first = me.displayName.trim().split(' ').first;
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 18 ? 'Hey' : 'Good evening';
    final top = MediaQuery.paddingOf(context).top;
    final wilted = pair.plant.health == PlantHealth.wilted;

    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: top + 250,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [const Color(0xFF7D6EF5), const Color(0xFFA699FF), Brand.lavender.withValues(alpha: 0)],
                stops: const [0, 0.6, 1],
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(Space.m, top + Space.s, Space.m, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  GlassPill(
                    padding: const EdgeInsets.all(4),
                    child: AvatarPair(
                      me: me.displayName,
                      partner: partner?.displayName ?? '',
                      mePhoto: me.photoUrl,
                      partnerPhoto: partner?.photoUrl,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: Space.s),
                  GlassPill(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Set your mood',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.mood_rounded, color: Brand.indigo),
                          onPressed: () => context.push('/mood'),
                        ),
                        IconButton(
                          tooltip: 'Widgets',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.widgets_outlined, color: Brand.indigo),
                          onPressed: () => context.push('/widgets'),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  const Flexible(child: SpeechBubble('Let’s feel closer!')),
                ],
              ),
              SizedBox(
                height: 128,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$greeting, $first',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.tt.headlineSmall?.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (mood != null) '$name feels ${mood.emoji} ${mood.label.toLowerCase()}',
                              if (status != null && status.text.isNotEmpty) status.text,
                              if (mood == null && (status == null || status.text.isEmpty)) 'Ready for a good day with $name?',
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.tt.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                          ),
                        ],
                      ),
                    ),
                    Buddy(size: 104, mood: wilted ? BuddyMood.sleepy : BuddyMood.happy)
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .moveY(begin: 0, end: -6, duration: 1600.ms, curve: Curves.easeInOut),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      emoji: '🔥',
                      label: 'Streak',
                      value: '${pair.streak.count}',
                      unit: pair.streak.count == 1 ? 'day' : 'days',
                      onTap: () => context.push('/plant'),
                    ),
                  ),
                  const SizedBox(width: Space.s + 2),
                  Expanded(
                    child: StatTile(
                      emoji: wilted ? '🥀' : '🌱',
                      label: 'Plant',
                      value: '${pair.plant.stage}',
                      unit: wilted ? 'needs love' : 'of 8 grown',
                      onTap: () => context.push('/plant'),
                    ),
                  ),
                  const SizedBox(width: Space.s + 2),
                  Expanded(
                    child: StatTile(
                      emoji: c?.emoji ?? '📅',
                      label: c == null ? 'Next date' : 'Countdown',
                      value: c == null ? '+' : (days == 0 ? 'Today' : '$days'),
                      unit: c == null ? 'add one' : (days == 0 ? c.title : (days == 1 ? 'day left' : 'days left')),
                      onTap: () => context.push(c == null ? '/countdowns/edit' : '/countdowns'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Daily rituals that keep the streak alive.
typedef _Ritual = ({String emoji, String title, String subtitle, bool done, Color tint, VoidCallback onTap});

List<_Ritual> _ritualsFor(BuildContext context, WidgetRef ref, AppUser me, Pair pair, String name) {
  final q = ref.watch(todayQuestionProvider).value;
  final tap = ref.watch(latestTapProvider).value;
  final cc = context.cc;
  return [
    (
      emoji: '📸',
      title: 'Send a photo',
      subtitle: 'Land on $name’s home screen',
      done: _isToday(pair.latestItemByUser[me.uid]?.sentAt),
      tint: cc.accentTint,
      onTap: () => context.push('/send'),
    ),
    (
      emoji: '☀️',
      title: 'Answer today’s question',
      subtitle: q == null ? 'A new one every morning' : q.text,
      done: q?.myAnswer != null,
      tint: cc.secondaryTint,
      onTap: () => context.push('/question'),
    ),
    (
      emoji: '💗',
      title: 'Send a heart tap',
      subtitle: 'A soft buzz that says “thinking of you”',
      done: tap != null && tap.senderId == me.uid && _isToday(tap.createdAt),
      tint: cc.plantTint,
      onTap: () async {
        hapticMedium();
        final ok = await runAction(context, () => ref.read(backendProvider).sendTap());
        if (ok && context.mounted) showToast(context, '$name will feel that 💗');
      },
    ),
  ];
}

class _ProgressCard extends ConsumerWidget {
  const _ProgressCard({required this.me, required this.pair, required this.name});

  final AppUser me;
  final Pair pair;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rituals = _ritualsFor(context, ref, me, pair, name);
    final done = rituals.where((r) => r.done).length;
    final next = rituals.where((r) => !r.done).firstOrNull;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.card),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Brand.indigo, Brand.indigoDeep],
        ),
        boxShadow: const [BoxShadow(color: Color(0x405B50E0), blurRadius: 24, offset: Offset(0, 12))],
      ),
      child: Stack(
        children: [
          Positioned(
            left: -14,
            bottom: -30,
            child: Buddy(
              size: 112,
              withBody: true,
              color: const Color(0xFFB4A5FF),
              mood: done == rituals.length ? BuddyMood.love : BuddyMood.happy,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(112, Space.m, Space.m, Space.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Today’s progress', style: context.tt.titleSmall?.copyWith(color: Colors.white)),
                    ),
                    Text('$done/${rituals.length}', style: context.tt.titleSmall?.copyWith(color: Colors.white)),
                  ],
                ),
                const SizedBox(height: Space.s + 2),
                SegmentedProgress(done: done, total: rituals.length),
                const SizedBox(height: Space.s + 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _DarkChip(done == rituals.length ? 'All done 🎉' : '${rituals.length - done} left'),
                    if (next != null) _DarkChip('Next: ${next.title}'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DarkChip extends StatelessWidget {
  const _DarkChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Text(label, style: context.tt.labelSmall?.copyWith(color: Colors.white, fontSize: 11)),
    );
  }
}

class _Rituals extends ConsumerWidget {
  const _Rituals({required this.me, required this.pair, required this.name});

  final AppUser me;
  final Pair pair;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rituals = _ritualsFor(context, ref, me, pair, name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Today’s rituals'),
        for (final (i, r) in rituals.indexed) ...[
          if (i > 0) const SizedBox(height: Space.s + 2),
          RitualTile(
            emoji: r.emoji,
            title: r.title,
            subtitle: r.subtitle,
            done: r.done,
            tint: r.tint,
            onTap: r.onTap,
          ),
        ],
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
    final cs = context.cs;
    return Semantics(
      button: true,
      label: 'Latest from $name. ${l.caption}. Open to reply',
      child: GestureDetector(
        onTap: () => context.push('/reply'),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.card),
            boxShadow: const [BoxShadow(color: Color(0x2A2A1B66), blurRadius: 28, offset: Offset(0, 12))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.card),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AppImage(image),
                  // Readability scrim: light at the top for the chip, deep at the bottom.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, 0.25, 0.55, 1],
                        colors: [Color(0x33000000), Color(0x00000000), Color(0x00000000), Color(0xB3000000)],
                      ),
                    ),
                  ),
                  Positioned(
                    top: Space.m - 4,
                    left: Space.m - 4,
                    child: _GlassChip(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: context.cc.gradient),
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: Text(
                            name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(name, style: context.tt.labelMedium?.copyWith(color: Colors.white, fontSize: 13)),
                        Text(
                          '  ·  ${timeAgo(l.sentAt)}',
                          style: context.tt.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.8)),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: Space.m,
                    right: Space.m - 4,
                    bottom: Space.m - 4,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: l.caption.isEmpty
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsets.only(bottom: 6, right: Space.s),
                                  child: Text(
                                    l.caption,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.tt.titleMedium?.copyWith(color: Colors.white, height: 1.25),
                                  ),
                                ),
                        ),
                        Material(
                          color: Colors.white,
                          shape: const StadiumBorder(),
                          child: InkWell(
                            customBorder: const StadiumBorder(),
                            onTap: () => context.push('/reply'),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.reply_rounded, size: 18, color: cs.primary),
                                  const SizedBox(width: 6),
                                  Text('Reply', style: context.tt.labelLarge?.copyWith(color: cs.primary, fontSize: 14)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Frosted pill used for overlays on top of photos.
class _GlassChip extends StatelessWidget {
  const _GlassChip({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
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
