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

/// Violet header for pushed pages (Figma "relationship", "mood and status",
/// "widgets" screens): frosted back button and white title on the brand
/// backdrop. An optional [child] card overlaps the rounded bottom edge.
///
/// Use it as the first item of a scroll view in a Scaffold without an
/// AppBar; it pads for the status bar itself.
class VioletPageHeader extends StatelessWidget {
  const VioletPageHeader({required this.title, super.key, this.child, this.backdropHeight = 104});

  final String title;
  final Widget? child;

  /// Height of the violet area below the status bar.
  final double backdropHeight;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: top + backdropHeight),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 0, right: 0, top: 0, height: top + backdropHeight, child: const HeroBackdrop(radius: 32)),
          Padding(
            padding: EdgeInsets.fromLTRB(20, top + 14, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Tooltip(
                      message: MaterialLocalizations.of(context).backButtonTooltip,
                      child: Material(
                        color: Colors.white.withValues(alpha: 0.22),
                        shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.45))),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => Navigator.of(context).maybePop(),
                          child: const SizedBox(
                            width: 40,
                            height: 40,
                            child: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.tt.headlineSmall?.copyWith(color: Colors.white, fontSize: 26),
                      ),
                    ),
                  ],
                ),
                if (child != null) ...[const SizedBox(height: 20), child!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Light page header (Figma "your plant screen"): white round back button,
/// large dark title and optional white round action buttons, on the page
/// background. Pads for the status bar itself.
class PlainPageHeader extends StatelessWidget {
  const PlainPageHeader({required this.title, super.key, this.actions = const []});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, top + 12, 20, 8),
      child: Row(
        children: [
          CircleIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.tt.headlineSmall?.copyWith(fontSize: 26),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// White round button with a violet icon and a soft shadow.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({required this.icon, required this.tooltip, required this.onTap, super.key});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: dark ? null : softCardShadow),
        child: Material(
          color: context.cc.card,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 22, color: context.cs.primary)),
          ),
        ),
      ),
    );
  }
}

/// Coloured tint + icon pairs used for icon tiles and soft cards across the
/// Figma screens (violet, blue, pink, mint, yellow).
enum SoftTone {
  violet(Color(0xFFEFE9FF), Color(0xFF6A3DF0)),
  blue(Color(0xFFE3E6FF), Color(0xFF2F3BD6)),
  pink(Color(0xFFFFE3F0), Color(0xFFC2185B)),
  mint(Color(0xFFDDFBF4), Color(0xFF0F8F80)),
  yellow(Color(0xFFFFF1CC), Color(0xFF8A5A00)),
  red(Color(0xFFFFE4E6), Color(0xFFE11D48));

  SoftTone(this.background, this.icon);

  final Color background;
  final Color icon;

  /// Card fill for this tone; a dim version in dark mode.
  Color fill(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? icon.withValues(alpha: 0.18) : background;
}

/// Small rounded-square tile with an outline icon (white by default).
class IconTile extends StatelessWidget {
  const IconTile({required this.icon, required this.tone, super.key, this.size = 40, this.filled = false});

  final IconData icon;
  final SoftTone tone;
  final double size;

  /// Tinted fill instead of white.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? tone.fill(context) : context.cc.card,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, size: size * 0.5, color: tone.icon),
    );
  }
}

/// Section title used on the redesigned pages ("Relationship type", "Status").
class PageSectionTitle extends StatelessWidget {
  const PageSectionTitle(this.title, {super.key, this.top = 24});

  final String title;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: 10),
      child: Text(title, style: context.tt.titleLarge?.copyWith(fontSize: 19)),
    );
  }
}

/// Filled white text field with a rounded outline (Figma inputs), with the
/// character count shown inside on the right.
InputDecoration softFieldDecoration(
  BuildContext context, {
  required String hint,
  int? max,
  int length = 0,
  Widget? clear,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: context.cs.outlineVariant.withValues(alpha: 0.6)),
  );
  return InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: context.cc.card,
    counterText: '',
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(borderSide: BorderSide(color: context.cs.primary, width: 1.6)),
    suffixIcon:
        clear ??
        (max == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Text('$length/$max', style: context.tt.labelSmall?.copyWith(color: context.cc.muted)),
              )),
    suffixIconConstraints: const BoxConstraints(minHeight: 24, minWidth: 24),
  );
}

/// Solid violet pill button from the Figma screens ("Share with Sam",
/// "+ Add"): no sheen, bold white label, optional soft violet glow.
class PillButton extends StatelessWidget {
  const PillButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.height = 56,
    this.glow = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final small = height < 44;
    final style = (small ? context.tt.labelLarge : context.tt.titleMedium)?.copyWith(
      fontWeight: FontWeight.w800,
      color: Colors.white,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: !glow || dark || onPressed == null
            ? null
            : const [BoxShadow(color: Color(0x596A3DF0), blurRadius: 24, offset: Offset(0, 12), spreadRadius: -6)],
      ),
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: Material(
          color: onPressed == null ? context.cs.surfaceContainerHigh : Brand.royal,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: small ? 18 : 20, color: Colors.white),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
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

/// Title block for bottom sheets and dialogs in the Figma style: a tinted
/// icon tile, a bold title and a muted line under it.
class SoftSheetHeader extends StatelessWidget {
  const SoftSheetHeader({
    required this.icon,
    required this.title,
    super.key,
    this.subtitle,
    this.tone = SoftTone.violet,
    this.centered = false,
  });

  final Widget icon;
  final String title;
  final String? subtitle;
  final SoftTone tone;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      width: centered ? 60 : 46,
      height: centered ? 60 : 46,
      decoration: BoxDecoration(color: tone.fill(context), borderRadius: BorderRadius.circular(centered ? 20 : 15)),
      alignment: Alignment.center,
      child: IconTheme.merge(
        data: IconThemeData(color: tone.icon, size: centered ? 28 : 22),
        child: icon,
      ),
    );
    final texts = Column(
      crossAxisAlignment: centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: context.tt.titleLarge?.copyWith(fontSize: centered ? 22 : 20, height: 1.15),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: context.tt.bodyMedium?.copyWith(color: context.cc.muted, height: 1.35),
          ),
        ],
      ],
    );
    if (centered) {
      return Column(mainAxisSize: MainAxisSize.min, children: [tile, const SizedBox(height: 14), texts]);
    }
    return Row(
      children: [
        tile,
        const SizedBox(width: 14),
        Expanded(child: texts),
      ],
    );
  }
}

/// A choice in a sheet: white card with a tinted icon tile, bold title and
/// optional muted line; the selected one gets a violet ring, tint and check.
class SoftOptionTile extends StatelessWidget {
  const SoftOptionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    super.key,
    this.subtitle,
    this.tone = SoftTone.violet,
    this.selected = false,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final SoftTone tone;
  final bool selected;
  final bool destructive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = context.cs.primary;
    final t = destructive ? SoftTone.red : tone;
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected ? SoftTone.violet.fill(context) : context.cc.card,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: selected ? accent : Colors.transparent, width: 1.8),
          boxShadow: dark || selected ? null : softCardShadow,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.card),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: selected ? context.cc.card : t.fill(context),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(icon, size: 21, color: selected ? accent : t.icon),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: context.tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: destructive ? t.icon : null,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(subtitle!, style: context.tt.bodySmall?.copyWith(color: context.cc.muted, height: 1.3)),
                        ],
                      ],
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet in the Figma style: lavender surface, rounded top, drag
/// handle, 20px side padding. [children] are laid out with 10px gaps.
Future<T?> showSoftSheet<T>(BuildContext context, {required Widget header, required List<Widget> children}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 18),
              for (final (i, c) in children.indexed) ...[if (i > 0) const SizedBox(height: 10), c],
            ],
          ),
        ),
      ),
    ),
  );
}

/// Centered dialog in the Figma style: icon tile, title, body, a violet
/// pill for the main action and a quiet text button under it.
Future<bool?> showSoftDialog(
  BuildContext context, {
  required Widget icon,
  required String title,
  required String body,
  required String ok,
  String cancel = 'Not now',
  SoftTone tone = SoftTone.violet,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SoftSheetHeader(icon: icon, title: title, subtitle: body, tone: tone, centered: true),
            const SizedBox(height: 22),
            PillButton(label: ok, height: 52, onPressed: () => Navigator.pop(ctx, true)),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(cancel, style: ctx.tt.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    ),
  );
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
