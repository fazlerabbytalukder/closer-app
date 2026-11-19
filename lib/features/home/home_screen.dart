import 'dart:async';
import 'dart:ui' as ui;

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/widget_bridge.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/theme/gloss.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/soft_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator()),
      );
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
                  const _LoveInbox(),
                  const _GoodnightCard(),
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
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
        ? 'Hey'
        : 'Good evening';
    final top = MediaQuery.paddingOf(context).top;
    final wilted = pair.plant.health == PlantHealth.wilted;

    return Stack(
      children: [
        Positioned(left: 0, right: 0, top: 0, height: top + 232, child: const HeroBackdrop()),
        Padding(
          padding: EdgeInsets.fromLTRB(Space.m, top + Space.s, Space.m, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Flexible(
                    child: _Glass(
                      onTap: () => context.push('/relationship'),
                      padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AvatarPair(
                            me: me.displayName,
                            partner: partner?.displayName ?? '',
                            mePhoto: me.photoUrl,
                            partnerPhoto: partner?.photoUrl,
                            size: 32,
                            ring: Colors.white,
                          ),
                          const SizedBox(width: Space.s),
                          Flexible(
                            child: Text(
                              'You & $name',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.tt.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.s),
                  _Glass(
                    tooltip: 'Set your mood',
                    onTap: () => context.push('/mood'),
                    child: me.mood == null
                        ? const Icon(Icons.mood_rounded, color: Colors.white, size: 22)
                        : Text(me.mood!.emoji, style: const TextStyle(fontSize: 19, height: 1.1)),
                  ),
                  const SizedBox(width: Space.s),
                  _Glass(
                    tooltip: 'Widgets',
                    onTap: () => context.push('/widgets'),
                    child: const Icon(Icons.widgets_rounded, color: Colors.white, size: 21),
                  ),
                  const SizedBox(width: Space.s),
                  const _ChatButton(),
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
                              if (mood == null && (status == null || status.text.isEmpty))
                                'Ready for a good day with $name?',
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.tt.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                          ),
                        ],
                      ),
                    ),
                    Buddy(size: 104, mood: wilted ? BuddyMood.sad : BuddyMood.fromEmoji(mood?.emoji))
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
                      onTap: () => context.push(c == null ? '/calendar/edit' : '/calendar'),
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
        boxShadow: const [BoxShadow(color: Color(0x401737E2), blurRadius: 24, offset: Offset(0, 12))],
      ),
      child: Stack(
        children: [
          Positioned(
            left: -14,
            bottom: -30,
            child: Buddy(
              size: 112,
              withBody: true,
              color: const Color(0xFF8FB0FF),
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
          RitualTile(emoji: r.emoji, title: r.title, subtitle: r.subtitle, done: r.done, tint: r.tint, onTap: r.onTap),
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
    final who = l.secret ? 'Secret admirer' : name;
    return Semantics(
      button: true,
      label: 'Latest from $who. ${l.caption}. Open to reply',
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
                            l.secret ? '🕵️' : (name.isEmpty ? '?' : name.characters.first.toUpperCase()),
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(who, style: context.tt.labelMedium?.copyWith(color: Colors.white, fontSize: 13)),
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
                                  Text(
                                    'Reply',
                                    style: context.tt.labelLarge?.copyWith(color: cs.primary, fontSize: 14),
                                  ),
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

  /// Emoji floating up from the heart, per burst id.
  final _burstEmoji = <int, String>{};

  Future<void> _tap([TapKind kind = TapKind.heart]) async {
    hapticMedium();
    _ctrl.forward(from: 0);
    final id = DateTime.now().microsecondsSinceEpoch;
    setState(() {
      _bursts.add(id);
      _burstEmoji[id] = kind.emoji;
    });
    final ok = await runAction(context, () => ref.read(backendProvider).sendTap(kind: kind.id));
    if (ok && mounted) {
      showToast(
        context,
        kind == TapKind.heart ? '${widget.name} will feel that 💗' : 'Sent “${kind.label}” ${kind.emoji}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authUidProvider).value;
    final tap = ref.watch(latestTapProvider).value;
    final fromPartner = tap != null && tap.senderId != me && DateTime.now().difference(tap.createdAt).inHours < 1;
    final cc = context.cc;
    final dark = Theme.of(context).brightness == Brightness.dark;
    const pink = Color(0xFFFF8FB1);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.card),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark ? [cc.accentTint, pink.withValues(alpha: 0.16)] : const [Color(0xFFF1EDFF), Color(0xFFFFE6EF)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: dark ? 0.08 : 0.9), width: 1.5),
        boxShadow: dark
            ? null
            : [BoxShadow(color: pink.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.card),
        child: Stack(
          children: [
            // Floating confetti: little hearts and sparkles drifting softly.
            ..._decor(const Offset(0.50, 0.12), '💕', 14, 0),
            ..._decor(const Offset(0.60, 0.70), '✨', 12, 600),
            ..._decor(const Offset(0.04, 0.80), '♡', 16, 1200, color: pink),
            ..._decor(const Offset(0.93, 0.08), '✦', 12, 300, color: cc.accent),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.s, Space.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: (dark ? Colors.white : pink).withValues(alpha: dark ? 0.1 : 0.16),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '💌 Love tap',
                                style: context.tt.labelSmall?.copyWith(
                                  color: dark ? Colors.white70 : const Color(0xFFE0557F),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: Space.s),
                            Text(
                              'Thinking of ${widget.name}? 🥰',
                              style: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            if (fromPartner)
                              _Bubble(
                                text:
                                    '${widget.name} ${tap.info.message} ${tap.info.emoji} · ${timeAgo(tap.createdAt)}',
                              ).animate().fadeIn(duration: 300.ms).slideX(begin: -0.1, end: 0, curve: Curves.easeOutBack)
                            else
                              Text(
                                'Tap the heart, or send a little message 👇',
                                style: context.tt.bodyMedium?.copyWith(color: cc.muted),
                              ),
                          ],
                        ),
                      ),
                      _heartButton(cc, pink),
                    ],
                  ),
                  const SizedBox(height: Space.s),
                  _kindChips(dark, pink),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "I can't stop thinking about you" one-tap messages.
  Widget _kindChips(bool dark, Color pink) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final k in TapKind.all.where((k) => k != TapKind.heart))
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Material(
                color: dark ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.85),
                shape: StadiumBorder(side: BorderSide(color: pink.withValues(alpha: 0.35))),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => _tap(k),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: Text(
                      '${k.emoji} ${k.label}',
                      style: context.tt.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// A small symbol at a relative position that bobs gently forever.
  List<Widget> _decor(Offset at, String glyph, double size, int delayMs, {Color? color}) => [
    Positioned.fill(
      child: Align(
        alignment: Alignment(at.dx * 2 - 1, at.dy * 2 - 1),
        child: IgnorePointer(
          child:
              Text(
                    glyph,
                    style: TextStyle(fontSize: size, color: color?.withValues(alpha: 0.55)),
                  )
                  .animate(onPlay: (c) => c.repeat(reverse: true), delay: delayMs.ms)
                  .moveY(begin: 0, end: -6, duration: 1800.ms, curve: Curves.easeInOut)
                  .fade(begin: 0.45, end: 0.9, duration: 1800.ms),
        ),
      ),
    ),
  ];

  Widget _heartButton(CloserColors cc, Color pink) {
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Soft halo that keeps pulsing outward, inviting a tap.
          Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(shape: BoxShape.circle, color: pink.withValues(alpha: 0.25)),
              )
              .animate(onPlay: (c) => c.repeat())
              .scale(
                begin: const Offset(0.9, 0.9),
                end: const Offset(1.25, 1.25),
                duration: 1600.ms,
                curve: Curves.easeOut,
              )
              .fadeOut(duration: 1600.ms),
          for (final b in _bursts)
            Text(_burstEmoji[b] ?? '💗', key: ValueKey(b), style: const TextStyle(fontSize: 22))
                .animate(
                  onComplete: (_) => setState(() {
                    _bursts.remove(b);
                    _burstEmoji.remove(b);
                  }),
                )
                .moveY(begin: 0, end: -70, duration: 900.ms, curve: Curves.easeOut)
                .moveX(begin: 0, end: (b % 3 - 1) * 18.0, duration: 900.ms)
                .fadeOut(delay: 400.ms, duration: 500.ms),
          Semantics(
            button: true,
            label: 'Send a thinking-of-you tap to ${widget.name}',
            child: GestureDetector(
              onTap: _tap,
              child: ScaleTransition(
                scale: TweenSequence<double>([
                  TweenSequenceItem(tween: Tween(begin: 1, end: 0.8), weight: 1),
                  TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.15), weight: 1),
                  TweenSequenceItem(tween: Tween(begin: 1.15, end: 1), weight: 1),
                ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut)),
                child:
                    Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [pink, cc.accent],
                            ),
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: pink.withValues(alpha: 0.45),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Gloss(
                            circle: true,
                            strength: 0.8,
                            child: Center(child: Icon(Icons.favorite_rounded, color: Colors.white, size: 34)),
                          ),
                        )
                        // Gentle heartbeat while idle.
                        .animate(onPlay: (c) => c.repeat())
                        .scale(
                          begin: const Offset(1, 1),
                          end: const Offset(1.08, 1.08),
                          duration: 220.ms,
                          curve: Curves.easeOut,
                        )
                        .then()
                        .scale(
                          begin: const Offset(1, 1),
                          end: const Offset(1 / 1.08, 1 / 1.08),
                          duration: 260.ms,
                          curve: Curves.easeIn,
                        )
                        .then(delay: 1100.ms),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Little speech bubble with a tail, for "Sam tapped you just now 💗".
class _Bubble extends StatelessWidget {
  const _Bubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: 0.1) : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        boxShadow: dark ? null : const [BoxShadow(color: Color(0x14E0557F), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Text(text, style: context.tt.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
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

/// Chat shortcut with the unread count.
class _ChatButton extends ConsumerWidget {
  const _ChatButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadChatProvider);
    return Badge(
      isLabelVisible: unread > 0,
      backgroundColor: Brand.pink,
      offset: const Offset(-2, 2),
      label: Text(unread > 9 ? '9+' : '$unread'),
      child: _Glass(
        tooltip: unread > 0 ? 'Chat, $unread unread' : 'Chat',
        onTap: () => context.push('/chat'),
        child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 20),
      ),
    );
  }
}

/// Frosted-glass control on the gradient header: a 42 px circle, or a pill
/// when [padding] is given.
class _Glass extends StatelessWidget {
  const _Glass({required this.child, required this.onTap, this.padding, this.tooltip});

  final Widget child;
  final VoidCallback onTap;
  final EdgeInsets? padding;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final round = padding == null;
    final shape = round
        ? const CircleBorder(side: BorderSide(color: Color(0x4DFFFFFF)))
        : const StadiumBorder(side: BorderSide(color: Color(0x4DFFFFFF)));
    Widget body = ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.white.withValues(alpha: 0.18),
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: () {
              HapticFeedback.selectionClick().ignore();
              onTap();
            },
            child: round
                ? SizedBox.square(dimension: 42, child: Center(child: child))
                : Padding(padding: padding!, child: child),
          ),
        ),
      ),
    );
    if (tooltip != null) body = Tooltip(message: tooltip, child: body);
    return body;
  }
}

/// In the evening: the goodnight ritual, until you've both done it.
class _GoodnightCard extends ConsumerWidget {
  const _GoodnightCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    if (!Goodnight.isEvening(now)) return const SizedBox.shrink();
    final me = ref.watch(authUidProvider).value;
    final partner = ref.watch(partnerUidProvider);
    final name = ref.watch(partnerNameProvider);
    final tonight = ref.watch(tonightProvider);
    final mine = tonight?.doneBy(me) ?? false;
    final theirs = tonight?.doneBy(partner) ?? false;
    if (mine && theirs) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Space.m),
      child: CloserCard(
        onTap: () => context.push('/goodnight'),
        gradient: const LinearGradient(colors: [Color(0xFF2D2760), Color(0xFF5A3F84)]),
        child: Row(
          children: [
            const Text(
              '🌙',
              style: TextStyle(fontSize: 34),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).rotate(begin: -0.03, end: 0.03, duration: 1500.ms),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    theirs ? '$name said goodnight 💤' : 'Goodnight ritual',
                    style: context.tt.titleMedium?.copyWith(color: Colors.white),
                  ),
                  Text(
                    mine ? 'Waiting for $name…' : 'Share the best moment of your day',
                    style: context.tt.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}

/// Unlocked reasons, letters and surprises waiting to be opened.
class _LoveInbox extends ConsumerWidget {
  const _LoveInbox();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fresh = ref.watch(newCapsulesProvider);
    if (fresh.isEmpty) return const SizedBox.shrink();
    final name = ref.watch(partnerNameProvider);
    final letters = fresh.where((c) => c.kind == CapsuleKind.letter).toList();
    final surprises = fresh.where((c) => c.kind == CapsuleKind.surprise).length;
    final (emoji, title, route) = letters.isNotEmpty
        ? ('💌', 'A letter from $name just opened', '/letters/${letters.first.id}')
        : surprises > 0
        ? ('🎁', '$name sent you a surprise', '/surprises')
        : ('💗', 'Today’s reason from $name is here', '/reasons');
    final more = fresh.length - 1;
    return Padding(
      padding: const EdgeInsets.only(top: Space.m),
      child: CloserCard(
        onTap: () => context.push(route),
        gradient: const LinearGradient(colors: [Color(0xFFFFE6EF), Color(0xFFFFF3D6)]),
        child: Row(
          children: [
            Text(
              emoji,
              style: const TextStyle(fontSize: 34),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 1, end: 1.12, duration: 700.ms),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.tt.titleMedium?.copyWith(color: Brand.ink)),
                  Text(
                    more > 0 ? 'Tap to open · $more more waiting' : 'Tap to open',
                    style: context.tt.bodyMedium?.copyWith(color: Brand.grey700),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Brand.grey700),
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
