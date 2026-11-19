
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

/// Full-bleed gradient hero with rounded bottom corners — the header style
/// of the design system's home screens (deep royal blue fading to cyan,
/// with soft decorative circles).
class HeroBackdrop extends StatelessWidget {
  const HeroBackdrop({super.key, this.radius = 28});

  final double radius;

  @override
  Widget build(BuildContext context) {
    final g = context.cc.gradient;
    return ClipRRect(
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Brand.royal, g.first, g.last],
            stops: const [0, 0.55, 1],
          ),
        ),
        child: Stack(
          children: [
            Positioned(right: -60, top: -40, child: _Bubble(size: 200, alpha: 0.10)),
            Positioned(left: -50, bottom: -70, child: _Bubble(size: 180, alpha: 0.08)),
            Positioned(right: 70, bottom: 20, child: _Bubble(size: 60, alpha: 0.10)),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.size, required this.alpha});

  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: alpha),
        ),
      ),
    );
  }
}

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
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.tile), boxShadow: dark ? null : Shadows.soft),
      child: Material(
        color: context.cc.card,
        borderRadius: BorderRadius.circular(Radii.tile),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.tile),
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
                    borderRadius: BorderRadius.circular(12),
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
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.tile), boxShadow: dark ? null : Shadows.card),
      child: Material(
        color: context.cc.card,
        borderRadius: BorderRadius.circular(Radii.tile),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.tile),
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
