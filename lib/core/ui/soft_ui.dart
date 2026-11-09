import 'dart:math' as math;

import 'package:closer_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Lavender-to-white wash with a warm peach glow — the soft backdrop used
/// behind the main tabs.
class SoftBackground extends StatelessWidget {
  const SoftBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = context.cs.surface;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? [const Color(0xFF221E3A), base, base]
              : [const Color(0xFFE4DDFF), const Color(0xFFF6F3FF), base],
          stops: const [0, 0.38, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -120,
            bottom: -80,
            child: _Glow(size: 360, color: dark ? const Color(0x33FF9D7A) : const Color(0x66FFD2BC)),
          ),
          Positioned(
            left: -140,
            top: 220,
            child: _Glow(size: 300, color: dark ? const Color(0x227B6CF6) : const Color(0x40C9BEFF)),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

/// Frosted white pill (header icon groups, small tags).
class GlassPill extends StatelessWidget {
  const GlassPill({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? Colors.white.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.72),
      shape: StadiumBorder(
        side: BorderSide(color: Colors.white.withValues(alpha: dark ? 0.12 : 0.9)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Little speech bubble ("Let's start small!").
class SpeechBubble extends StatelessWidget {
  const SpeechBubble(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(4),
        ),
        boxShadow: const [BoxShadow(color: Color(0x145B50E0), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Text(text, style: context.tt.labelSmall?.copyWith(color: Brand.indigo)),
    );
  }
}

/// Row of rounded segments; [done] of [total] filled, the next one shows a
/// "current" dot like a slider knob.
class SegmentedProgress extends StatelessWidget {
  const SegmentedProgress({
    required this.done,
    required this.total,
    super.key,
    this.fill = const Color(0xFFFF9A4D),
    this.track = const Color(0x40FFFFFF),
    this.height = 12,
  });

  final int done;
  final int total;
  final Color fill;
  final Color track;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$done of $total done',
      child: Row(
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                height: height,
                decoration: BoxDecoration(color: i < done ? fill : track, borderRadius: BorderRadius.circular(height)),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.all(2),
                child: i == done - 1
                    ? Container(
                        width: height - 4,
                        height: height - 4,
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      )
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Round check used in ritual lists.
class CheckDot extends StatelessWidget {
  const CheckDot({required this.done, super.key, this.size = 26});

  final bool done;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? Brand.green : Colors.transparent,
        border: done ? null : Border.all(color: context.cs.outlineVariant, width: 2),
      ),
      child: done ? Icon(Icons.check_rounded, color: Colors.white, size: size * 0.66) : null,
    );
  }
}

/// List row: icon tile, title + subtitle, trailing check (or custom).
class RitualTile extends StatelessWidget {
  const RitualTile({
    required this.emoji,
    required this.title,
    required this.subtitle,
    super.key,
    this.done = false,
    this.onTap,
    this.tint,
    this.trailing,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final bool done;
  final VoidCallback? onTap;
  final Color? tint;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? context.cc.card : Colors.white.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint ?? context.cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: Space.m - 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.tt.titleSmall?.copyWith(
                        decoration: done ? TextDecoration.lineThrough : null,
                        decorationColor: context.cc.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
                    ),
                  ],
                ),
              ),
              trailing ?? CheckDot(done: done),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small white stat tile (icon, label, big value, unit).
class StatTile extends StatelessWidget {
  const StatTile({
    required this.emoji,
    required this.label,
    required this.value,
    required this.unit,
    super.key,
    this.onTap,
  });

  final String emoji;
  final String label;
  final String value;
  final String unit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: dark ? null : const [BoxShadow(color: Color(0x1A5B50E0), blurRadius: 24, offset: Offset(0, 10))],
      ),
      child: Material(
        color: context.cc.card,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            child: Column(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 30)),
                const SizedBox(height: 6),
                Text(label, style: context.tt.bodySmall?.copyWith(color: context.cc.muted)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(value, style: context.tt.headlineSmall),
                ),
                Text(
                  unit,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.bodySmall?.copyWith(color: context.cc.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Large title row for the main tabs ("My Habits Tracker" style).
class SoftHeader extends StatelessWidget {
  const SoftHeader(this.title, {super.key, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.m, Space.m),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.tt.headlineSmall),
                if (subtitle != null) Text(subtitle!, style: context.tt.bodyMedium?.copyWith(color: context.cc.muted)),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Mood of the little bear buddy.
enum BuddyMood { happy, sleepy, love }

/// Cute round bear buddy, drawn in code so it scales crisply.
class Buddy extends StatelessWidget {
  const Buddy({
    super.key,
    this.size = 96,
    this.color = const Color(0xFFFF9A4D),
    this.mood = BuddyMood.happy,
    this.withBody = false,
  });

  final double size;
  final Color color;
  final BuddyMood mood;
  final bool withBody;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(size, withBody ? size * 1.25 : size),
        painter: _BuddyPainter(color, mood, withBody),
      ),
    );
  }
}

class _BuddyPainter extends CustomPainter {
  _BuddyPainter(this.color, this.mood, this.withBody);

  final Color color;
  final BuddyMood mood;
  final bool withBody;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final fill = Paint()..color = color;
    final hsl = HSLColor.fromColor(color);
    final darker = Paint()..color = hsl.withLightness((hsl.lightness - 0.12).clamp(0, 1)).toColor();
    final cream = Paint()..color = const Color(0xFFFFF1E6);
    final ink = Paint()..color = const Color(0xFF2B2240);
    final blush = Paint()..color = const Color(0x88FF7A9C);

    final cx = w / 2;
    final headR = w * 0.36;
    final headC = Offset(cx, w * 0.52);

    if (withBody) {
      final bodyRect = Rect.fromCenter(center: Offset(cx, w * 1.0), width: w * 0.66, height: w * 0.5);
      canvas
        ..drawOval(bodyRect, fill)
        ..drawOval(Rect.fromCenter(center: Offset(cx, w * 1.03), width: w * 0.38, height: w * 0.32), cream)
        // paws
        ..drawCircle(Offset(cx - w * 0.3, w * 0.94), w * 0.08, fill)
        ..drawCircle(Offset(cx + w * 0.3, w * 0.94), w * 0.08, fill);
    }

    // Ears.
    for (final s in [-1.0, 1.0]) {
      final ear = Offset(cx + s * headR * 0.78, headC.dy - headR * 0.8);
      canvas
        ..drawCircle(ear, headR * 0.34, fill)
        ..drawCircle(ear, headR * 0.19, darker);
    }

    // Head + soft shadow under chin.
    canvas
      ..drawOval(
        Rect.fromCenter(center: headC.translate(0, headR * 0.06), width: headR * 2.1, height: headR * 1.95),
        darker,
      )
      ..drawOval(Rect.fromCenter(center: headC, width: headR * 2.1, height: headR * 1.9), fill);

    // Muzzle.
    final muzzle = headC.translate(0, headR * 0.34);
    canvas
      ..drawOval(Rect.fromCenter(center: muzzle, width: headR * 0.95, height: headR * 0.7), cream)
      // Nose.
      ..drawOval(
        Rect.fromCenter(center: muzzle.translate(0, -headR * 0.12), width: headR * 0.3, height: headR * 0.2),
        ink,
      );

    // Mouth.
    final mouth = Paint()
      ..color = ink.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, w * 0.018)
      ..strokeCap = StrokeCap.round;
    final m = muzzle.translate(0, headR * 0.02);
    canvas
      ..drawArc(
        Rect.fromCenter(center: m.translate(-headR * 0.1, 0), width: headR * 0.2, height: headR * 0.2),
        0,
        math.pi,
        false,
        mouth,
      )
      ..drawArc(
        Rect.fromCenter(center: m.translate(headR * 0.1, 0), width: headR * 0.2, height: headR * 0.2),
        0,
        math.pi,
        false,
        mouth,
      );

    // Eyes.
    final eyeY = headC.dy - headR * 0.08;
    for (final s in [-1.0, 1.0]) {
      final e = Offset(cx + s * headR * 0.42, eyeY);
      switch (mood) {
        case BuddyMood.happy:
          canvas
            ..drawCircle(e, headR * 0.11, ink)
            ..drawCircle(e.translate(-headR * 0.035, -headR * 0.04), headR * 0.04, Paint()..color = Colors.white);
        case BuddyMood.sleepy:
          canvas.drawArc(
            Rect.fromCenter(center: e, width: headR * 0.24, height: headR * 0.18),
            0,
            math.pi,
            false,
            mouth,
          );
        case BuddyMood.love:
          _heart(canvas, e, headR * 0.26, Paint()..color = const Color(0xFFFF4F7B));
      }
      // Blush.
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx + s * headR * 0.66, eyeY + headR * 0.3),
          width: headR * 0.3,
          height: headR * 0.17,
        ),
        blush,
      );
    }
  }

  void _heart(Canvas canvas, Offset c, double s, Paint p) {
    final path = Path()
      ..moveTo(c.dx, c.dy + s * 0.35)
      ..cubicTo(c.dx - s * 0.6, c.dy - s * 0.05, c.dx - s * 0.3, c.dy - s * 0.55, c.dx, c.dy - s * 0.2)
      ..cubicTo(c.dx + s * 0.3, c.dy - s * 0.55, c.dx + s * 0.6, c.dy - s * 0.05, c.dx, c.dy + s * 0.35)
      ..close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_BuddyPainter old) => old.color != color || old.mood != mood || old.withBody != withBody;
}

/// Transparent, roomy app bar for the main tabs.
PreferredSizeWidget softAppBar(BuildContext context, String title, {List<Widget>? actions}) {
  return AppBar(
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    toolbarHeight: 68,
    titleSpacing: Space.l,
    title: Text(title, style: context.tt.headlineSmall),
    actions: actions,
  );
}
