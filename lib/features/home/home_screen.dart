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
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

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
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 130),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _QueuedBanner(),
                  _ProgressCard(me: me, pair: pair, name: name),
                  _Rituals(me: me, pair: pair, name: name),
                  const _LoveInbox(),
                  const _GoodnightCard(),
                  if (installed == 0) ...[
                    const SizedBox(height: 16),
                    _WidgetNudge(onTap: () => context.push('/widgets')),
                  ],
                  _Title('Latest from $name'),
                  _LatestCard(latest: latest, name: name),
                  const SizedBox(height: 18),
                  _HeartTap(name: name),
                  const SizedBox(height: 18),
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

/// "2 waiting to send": sends made offline that go out once back online.
class _QueuedBanner extends ConsumerWidget {
  const _QueuedBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(queuedSendsProvider).value ?? 0;
    if (n == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(color: Brand.purpleTint, borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.schedule_send_rounded, color: Brand.purple),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$n waiting to send · they’ll go out when you’re back online',
                  style: context.tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
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

/// Violet greeting header (Figma "home screen"): glass couple pill and
/// shortcuts, big greeting, the two mascots and three stat tiles that sit
/// on the header's bottom edge.
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
      clipBehavior: Clip.none,
      children: [
        Positioned(left: 0, right: 0, top: 0, height: top + 247, child: const HeroBackdrop()),
        // Mascots peek out on the right, just behind the stat tiles.
        Positioned(
          right: -6,
          top: top + 36,
          child: Image.asset('assets/home/header_mascots.png', width: 144, height: 159)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(begin: 0, end: -6, duration: 1800.ms, curve: Curves.easeInOut),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, top + 12, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _Glass(
                        onTap: () => context.push('/relationship'),
                        padding: const EdgeInsets.fromLTRB(6, 5, 16, 5),
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
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                'You & $name',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.tt.labelLarge?.copyWith(color: Colors.white, fontSize: 15),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _Glass(
                    tooltip: 'Set your mood',
                    onTap: () => context.push('/mood'),
                    child: me.mood == null
                        ? const Icon(Icons.sentiment_satisfied_alt_outlined, color: Colors.white, size: 22)
                        : Text(me.mood!.emoji, style: const TextStyle(fontSize: 19, height: 1.1)),
                  ),
                  const SizedBox(width: 8),
                  _Glass(
                    tooltip: 'Widgets',
                    onTap: () => context.push('/widgets'),
                    child: const Icon(Icons.dashboard_customize_outlined, color: Colors.white, size: 21),
                  ),
                  const SizedBox(width: 8),
                  const _ChatButton(),
                ],
              ),
              SizedBox(
                height: 119,
                child: Padding(
                  padding: const EdgeInsets.only(right: 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Shrinks to fit beside the mascots instead of cutting
                      // the greeting off ("Good mornin…").
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '$greeting, $first',
                          maxLines: 1,
                          style: context.tt.headlineLarge?.copyWith(color: Colors.white, fontSize: 38, height: 1.1),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (mood != null) '$name feels ${mood.emoji} ${mood.label.toLowerCase()}',
                          if (status != null && status.text.isNotEmpty) status.text,
                          if (mood == null && (status == null || status.text.isEmpty))
                            'Ready for a good day with $name?',
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.tt.bodyLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      icon: Icons.local_fire_department_outlined,
                      iconColor: const Color(0xFFD6246E),
                      tint: Brand.pinkTint,
                      label: 'Streak',
                      value: '${pair.streak.count}',
                      unit: pair.streak.count == 1 ? 'day' : 'days',
                      onTap: () => context.push('/plant'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      icon: Icons.spa_outlined,
                      iconColor: Brand.green,
                      tint: Brand.greenTint,
                      label: 'Plant',
                      value: '${pair.plant.stage}',
                      unit: wilted ? 'needs love' : 'of 8 grown',
                      onTap: () => context.push('/plant'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      icon: Icons.calendar_month_outlined,
                      iconColor: Brand.purple,
                      tint: Brand.purpleTint,
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

/// Section title on the home feed (Figma: Fredoka 22).
class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 12),
      child: Text(text, style: context.tt.titleLarge?.copyWith(fontSize: 22)),
    );
  }
}

/// Daily rituals that keep the streak alive.
typedef _Ritual = ({
  IconData icon,
  Color iconColor,
  String title,
  String subtitle,
  bool done,
  Color tint,
  VoidCallback onTap,
});

List<_Ritual> _ritualsFor(BuildContext context, WidgetRef ref, AppUser me, Pair pair, String name) {
  final q = ref.watch(todayQuestionProvider).value;
  final tap = ref.watch(latestTapProvider).value;
  return [
    (
      icon: Icons.photo_camera_outlined,
      iconColor: const Color(0xFFD6246E),
      title: 'Send a photo',
      subtitle: 'Land on $name’s home screen',
      done: _isToday(pair.latestItemByUser[me.uid]?.sentAt),
      tint: Brand.pinkTint,
      onTap: () => context.push('/send'),
    ),
    (
      icon: Icons.wb_sunny_outlined,
      iconColor: const Color(0xFF9A6200),
      title: 'Answer today’s question',
      subtitle: q == null ? 'A new one every morning' : q.text,
      done: q?.myAnswer != null,
      tint: const Color(0xFFFFF1CC),
      onTap: () => context.push('/question'),
    ),
    (
      icon: Icons.favorite_border_rounded,
      iconColor: Brand.purple,
      title: 'Send a heart tap',
      subtitle: 'A soft buzz that says “thinking of you”',
      // My own last tap, so a later tap from the partner doesn't untick it.
      done: _isToday(pair.lastTapByUser[me.uid]) || (tap != null && tap.senderId == me.uid && _isToday(tap.createdAt)),
      tint: Brand.purpleTint,
      onTap: () async {
        hapticMedium();
        final ok = await runAction(context, () => ref.read(backendProvider).sendTap());
        if (ok && context.mounted) showToast(context, '$name will feel that 💗');
      },
    ),
  ];
}

/// Pink "Today's progress" card with the mascot peeking in.
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
    const ink = Brand.ink;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFFF9CCB),
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [
          BoxShadow(color: Color(0x66FF5C9E), blurRadius: 30, offset: Offset(0, 18), spreadRadius: -12),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -6,
            bottom: -18,
            child: Image.asset('assets/home/progress_mascot.png', width: 116, height: 127),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 104, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Today’s progress', style: context.tt.titleLarge?.copyWith(color: ink, fontSize: 18)),
                    ),
                    Text('$done/${rituals.length}', style: context.tt.titleLarge?.copyWith(color: ink, fontSize: 18)),
                  ],
                ),
                const SizedBox(height: 14),
                SegmentedProgress(
                  done: done,
                  total: rituals.length,
                  height: 8,
                  fill: Brand.purple,
                  track: Colors.white.withValues(alpha: 0.6),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _WhiteChip(done == rituals.length ? 'All done 🎉' : '${rituals.length - done} left'),
                    if (next != null) _WhiteChip('Next: ${next.title}'),
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

class _WhiteChip extends StatelessWidget {
  const _WhiteChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(100)),
      child: Text(label, style: context.tt.labelMedium?.copyWith(color: Brand.ink, fontSize: 13)),
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
        const _Title('Today’s rituals'),
        for (final (i, r) in rituals.indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          RitualTile(
            icon: r.icon,
            iconColor: r.iconColor,
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

/// Flat tinted row with a white icon tile and a chevron (letters, widget
/// nudge). [dashed] draws the dotted outline from the design.
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.iconColor,
    required this.color,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.dashed = false,
  });

  final IconData icon;
  final Color iconColor;
  final Color color;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(24);
    final body = Material(
      color: dark ? iconColor.withValues(alpha: 0.14) : color,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: dark ? context.cc.card : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.tt.titleSmall?.copyWith(fontSize: 15.5)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: context.tt.bodyMedium?.copyWith(color: context.cc.muted, fontSize: 13.5)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: context.cs.onSurface),
            ],
          ),
        ),
      ),
    );
    if (!dashed) return body;
    return CustomPaint(
      foregroundPainter: const _DashedBorderPainter(color: Brand.blue300, radius: 24),
      child: body,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius((Offset.zero & size).deflate(0.75), Radius.circular(radius));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color || old.radius != radius;
}

class _WidgetNudge extends StatelessWidget {
  const _WidgetNudge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _NoticeCard(
      icon: Icons.phone_iphone_rounded,
      iconColor: Brand.purple,
      color: const Color(0xFFF3EEFF),
      title: 'Add the Duosy widget to your home screen so you never miss a thing',
      dashed: true,
      onTap: onTap,
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
    final who = l.secret ? 'Secret admirer' : name;
    return Semantics(
      button: true,
      label: 'Latest from $who. ${l.caption}. Open to reply',
      child: GestureDetector(
        onTap: () => context.push('/reply'),
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(36), boxShadow: softCardShadow),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(36),
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
                        colors: [Color(0x26000000), Color(0x00000000), Color(0x00000000), Color(0x59000000)],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 14,
                    left: 14,
                    child: _GlassChip(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Brand.purple),
                          child: Text(
                            l.secret ? '🕵️' : (name.isEmpty ? '?' : name.characters.first.toUpperCase()),
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const SizedBox(width: 2),
                        Text(who, style: context.tt.labelMedium?.copyWith(color: Brand.ink, fontSize: 13)),
                        Text(
                          '  ·  ${timeAgo(l.sentAt)}',
                          style: context.tt.labelMedium?.copyWith(color: Brand.grey700, fontSize: 13),
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
                                    style: context.tt.titleLarge?.copyWith(color: Colors.white, height: 1.2),
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
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.reply_rounded, size: 20, color: Brand.purple),
                                  const SizedBox(width: 6),
                                  Text('Reply', style: context.tt.labelLarge?.copyWith(color: Brand.purple)),
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
          padding: const EdgeInsets.fromLTRB(5, 5, 14, 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(999),
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
        color: cc.card,
        borderRadius: BorderRadius.circular(32),
        boxShadow: dark ? null : softCardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          children: [
            // Floating confetti: little hearts and sparkles drifting softly.
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 12, 18),
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
                              padding: const EdgeInsets.fromLTRB(10, 5, 12, 5),
                              decoration: BoxDecoration(
                                color: dark ? Brand.pink.withValues(alpha: 0.16) : Brand.pinkTint,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.mail_outline_rounded, size: 15, color: Color(0xFFB0124F)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Love tap',
                                    style: context.tt.labelMedium?.copyWith(
                                      color: dark ? Colors.white70 : const Color(0xFFB0124F),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text('Thinking of ${widget.name}?', style: context.tt.titleLarge?.copyWith(fontSize: 22)),
                            const SizedBox(height: 6),
                            if (fromPartner)
                              _Bubble(
                                text:
                                    '${widget.name} ${tap.info.message} ${tap.info.emoji} · ${timeAgo(tap.createdAt)}',
                              ).animate().fadeIn(duration: 300.ms).slideX(begin: -0.1, end: 0, curve: Curves.easeOutBack)
                            else
                              Text(
                                'Tap the heart, or send a little message',
                                style: context.tt.bodyLarge?.copyWith(color: cc.muted),
                              ),
                          ],
                        ),
                      ),
                      _heartButton(cc, pink),
                    ],
                  ),
                  const SizedBox(height: 12),
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
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final k in TapKind.all.where((k) => k != TapKind.heart))
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Material(
                color: dark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFF3EEFF),
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => _tap(k),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    child: Text(k.label, style: context.tt.labelMedium),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

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
                decoration: BoxDecoration(shape: BoxShape.circle, color: Brand.pink.withValues(alpha: 0.18)),
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
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFFF8FC4), Brand.pink],
                            ),
                            border: Border.all(color: Brand.pinkTint, width: 6),
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

/// Lavender "Question of the day" card.
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(32);
    return Material(
      color: dark ? Brand.purple.withValues(alpha: 0.16) : Brand.purpleTint,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: () => context.push('/question'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 6, 14, 6),
                    decoration: BoxDecoration(
                      color: dark ? context.cc.card : Colors.white,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wb_sunny_outlined, size: 15, color: Brand.purple),
                        const SizedBox(width: 6),
                        Text('Question of the day', style: context.tt.labelMedium?.copyWith(color: Brand.purple)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (q.revealed)
                    const Text('🎉')
                  else if (partnerAnswered && !answered)
                    const Icon(Icons.hourglass_empty_rounded, color: Brand.purple, size: 22),
                ],
              ),
              const SizedBox(height: 14),
              Text(q.text, style: context.tt.headlineSmall?.copyWith(fontSize: 26, height: 1.15)),
              const SizedBox(height: 8),
              Text(status, style: context.tt.bodyLarge?.copyWith(color: context.cc.muted)),
            ],
          ),
        ),
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
        child: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 21),
      ),
    );
  }
}

/// Frosted-glass control on the violet header (Figma: white 18% fill, 40%
/// outline): a 44 px circle, or a pill when [padding] is given.
class _Glass extends StatelessWidget {
  const _Glass({required this.child, required this.onTap, this.padding, this.tooltip});

  final Widget child;
  final VoidCallback onTap;
  final EdgeInsets? padding;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final round = padding == null;
    const side = BorderSide(color: Color(0x66FFFFFF));
    final shape = round ? const CircleBorder(side: side) : const StadiumBorder(side: side);
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
                ? SizedBox.square(dimension: 44, child: Center(child: child))
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
    final (title, route) = letters.isNotEmpty
        ? ('A letter from $name just opened', '/letters/${letters.first.id}')
        : surprises > 0
        ? ('$name sent you a surprise', '/surprises')
        : ('Today’s reason from $name is here', '/reasons');
    final more = fresh.length - 1;
    final icon = letters.isNotEmpty
        ? Icons.mail_outline_rounded
        : surprises > 0
        ? Icons.card_giftcard_rounded
        : Icons.favorite_border_rounded;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: _NoticeCard(
        icon: icon,
        iconColor: Brand.green,
        color: Brand.greenTint,
        title: title,
        subtitle: more > 0 ? 'Tap to open · $more more waiting' : 'Tap to open',
        onTap: () => context.push(route),
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
