import 'dart:math' as math;

import 'package:closer_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

export 'package:closer_app/core/ui/buddy.dart';

/// Clean, flat page backdrop behind the main tabs (pale primary-50 in light
/// mode, deep navy in dark), as in the design system's screens.
class SoftBackground extends StatelessWidget {
  const SoftBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: context.cs.surface, child: child);
  }
}

/// Home header (Figma "home screen"): solid violet with rounded bottom
/// corners, a pink glow behind the mascots and the outlined name pattern.
class HeroBackdrop extends StatelessWidget {
  const HeroBackdrop({super.key, this.radius = 40});

  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
      child: const ColoredBox(
        color: Brand.royal,
        child: Stack(
          children: [
            Positioned.fill(child: DuosyPattern(color: Color(0x29FFFFFF))),
            Positioned(
              right: -140,
              top: -20,
              width: 440,
              height: 440,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(colors: [Color(0xBFFF9AD5), Color(0x00FF9AD5)], stops: [0, 0.66]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rows of outlined "Duosy" words tilted 10° — the brand pattern behind the
/// splash, onboarding and the home header.
class DuosyPattern extends StatelessWidget {
  const DuosyPattern({required this.color, super.key, this.fontSize = 66});

  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color;
    final style = TextStyle(
      fontFamily: AppTheme.displayFamily,
      fontWeight: FontWeight.w600,
      fontSize: fontSize,
      height: 1.7,
      foreground: stroke,
    );
    return IgnorePointer(
      child: ClipRect(
        child: OverflowBox(
          maxWidth: 1400,
          maxHeight: 1600,
          child: Transform.rotate(
            angle: -10 * math.pi / 180,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 12; i++)
                  Transform.translate(
                    offset: Offset(i.isEven ? 0 : -100, 0),
                    child: Text('Duosy Duosy Duosy Duosy Duosy', maxLines: 1, softWrap: false, style: style),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Soft violet lift under white cards (Figma: #6A3DF0 @ 28%, blurred).
const softCardShadow = [BoxShadow(color: Color(0x2E6A3DF0), blurRadius: 26, offset: Offset(0, 14), spreadRadius: -10)];

/// Frosted pill (header icon groups, small tags) — reads well on top of the
/// gradient hero.
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
      color: dark ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.92),
      shape: StadiumBorder(
        side: BorderSide(color: Colors.white.withValues(alpha: dark ? 0.14 : 0.6)),
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
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(14),
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(4),
        ),
        boxShadow: Shadows.soft,
      ),
      child: Text(text, style: context.tt.labelSmall?.copyWith(color: Brand.royal)),
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
        color: done ? Brand.purple : Colors.transparent,
        border: done ? null : Border.all(color: Brand.blue100, width: 2),
      ),
      child: done ? Icon(Icons.check_rounded, color: Colors.white, size: size * 0.66) : null,
    );
  }
}

/// List row (Figma "Today's rituals"): tinted icon tile, title + subtitle,
/// trailing check (or custom).
class RitualTile extends StatelessWidget {
  const RitualTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    super.key,
    this.done = false,
    this.onTap,
    this.tint,
    this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool done;
  final VoidCallback? onTap;
  final Color? tint;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(24);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: dark ? null : softCardShadow),
      child: Material(
        color: context.cc.card,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 15, 12),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: dark ? iconColor.withValues(alpha: 0.18) : (tint ?? context.cs.surfaceContainer),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, size: 22, color: iconColor),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.tt.titleSmall?.copyWith(
                          fontSize: 15.5,
                          decoration: done ? TextDecoration.lineThrough : null,
                          decorationColor: context.cc.muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.tt.bodyMedium?.copyWith(color: context.cc.muted, fontSize: 13.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                trailing ?? CheckDot(done: done),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// White stat tile on the header edge (Figma: 110 × 143, round icon badge,
/// label, big Fredoka value, unit).
class StatTile extends StatelessWidget {
  const StatTile({
    required this.icon,
    required this.iconColor,
    required this.tint,
    required this.label,
    required this.value,
    required this.unit,
    super.key,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color tint;
  final String label;
  final String value;
  final String unit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(28);
    return Container(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: dark ? null : softCardShadow),
      child: Material(
        color: context.cc.card,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 14),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dark ? iconColor.withValues(alpha: 0.18) : tint,
                  ),
                  child: Icon(icon, size: 21, color: iconColor),
                ),
                const SizedBox(height: 8),
                Text(label, style: context.tt.labelMedium?.copyWith(color: context.cc.muted)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(value, style: context.tt.headlineMedium?.copyWith(height: 1.15)),
                ),
                Text(
                  unit,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.bodyMedium?.copyWith(color: context.cc.muted, fontWeight: FontWeight.w700),
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
