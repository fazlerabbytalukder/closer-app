import 'dart:async';
import 'dart:math' as math;

import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/soft_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Soft gradient backdrop + floating notched bottom navigation bar, with the
/// Send action in the centre (plan 9.3).
class AppShell extends StatelessWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    void go(int branch) {
      unawaited(HapticFeedback.selectionClick());
      shell.goBranch(branch, initialLocation: branch == shell.currentIndex);
    }

    // Branch indices: 0 home, 1 together, 2 memories, 3 me.
    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: SoftBackground(child: shell),
      bottomNavigationBar: _BottomBar(
        selectedSlot: shell.currentIndex >= 2 ? shell.currentIndex + 1 : shell.currentIndex,
        children: [
          _NavItem(icon: Icons.home_outlined, label: 'Home', selected: shell.currentIndex == 0, onTap: () => go(0)),
          _NavItem(
            icon: Icons.wb_sunny_outlined,
            label: 'Together',
            selected: shell.currentIndex == 1,
            onTap: () => go(1),
          ),
          const _SendButton(),
          _NavItem(
            icon: Icons.photo_library_outlined,
            label: 'Memories',
            selected: shell.currentIndex == 2,
            onTap: () => go(2),
          ),
          _NavItem(
            icon: Icons.person_outline_rounded,
            label: 'Me',
            selected: shell.currentIndex == 3,
            onTap: () => go(3),
          ),
        ],
      ),
    );
  }
}

/// Floating rounded bar with a smooth notch cut into its top edge above the
/// selected tab; a small dot rides in the notch and slides between tabs.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.children, required this.selectedSlot});

  final List<Widget> children;

  /// Index into [children] the notch sits above.
  final int selectedSlot;

  static const _barHeight = 77.0;
  static const _notchDepth = 11.0;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.m, 0, Space.m, math.max(bottomInset, Space.m)),
      child: SizedBox(
        height: _barHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final slotWidth = constraints.maxWidth / children.length;
            return TweenAnimationBuilder<double>(
              tween: Tween(end: slotWidth * (selectedSlot + 0.5)),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              builder: (context, notchX, child) => CustomPaint(
                painter: _NotchedBarPainter(
                  notchX: notchX,
                  depth: _notchDepth,
                  dark: dark,
                  dotColor: context.cs.primary,
                ),
                child: child,
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: _notchDepth - 2, bottom: _NotchedBarPainter._thickness),
                child: Row(children: [for (final c in children) Expanded(child: c)]),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Paints the bar as a raised 3D slab: soft drop shadow, a darker "side"
/// edge beneath the face, a top-lit gradient face with a glossy rim, and a
/// spherical indicator dot resting in the notch.
class _NotchedBarPainter extends CustomPainter {
  _NotchedBarPainter({required this.notchX, required this.depth, required this.dark, required this.dotColor});

  final double notchX;
  final double depth;
  final bool dark;
  final Color dotColor;

  static const _radius = 24.0;
  static const _halfWidth = 22.0;

  /// Bottom inset kept for the row padding (flat bar: no visible side edge).
  static const _thickness = 0.0;

  Path _shape(Size size) {
    final x = notchX;
    final bar = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(_radius)));
    // Dip carved out of the top edge, centred exactly on the tab (works even
    // over the rounded corners, so no clamping is needed).
    final notch = Path()
      ..moveTo(x - _halfWidth, -1)
      ..cubicTo(x - _halfWidth * 0.45, -1, x - _halfWidth * 0.6, depth, x, depth)
      ..cubicTo(x + _halfWidth * 0.6, depth, x + _halfWidth * 0.45, -1, x + _halfWidth, -1)
      ..close();
    return Path.combine(PathOperation.difference, bar, notch);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final face = _shape(size);

    // 1. Soft, blue-tinted drop shadow (flat card elevation).
    canvas
      ..drawPath(
        face.shift(const Offset(0, 6)),
        Paint()
          ..color = (dark ? Colors.black : const Color(0xFF1737E2)).withValues(alpha: dark ? 0.45 : 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      )
      // 2. Flat face.
      ..drawPath(face, Paint()..color = dark ? Brand.darkSurface : Colors.white)
      // 3. Hairline border.
      ..drawPath(
        face,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = dark ? const Color(0xFF283048) : const Color(0xFFE6EBF5),
      );

    // 4. Solid indicator dot resting in the notch.
    canvas.drawCircle(Offset(notchX, depth / 2 - 1), 5, Paint()..color = dotColor);
  }

  @override
  bool shouldRepaint(_NotchedBarPainter old) =>
      old.notchX != notchX || old.dark != dark || old.dotColor != dotColor || old.depth != depth;
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? context.cs.primary : context.cc.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ExcludeSemantics(
          child: _NavLabel(
            label: label,
            color: fg,
            bold: selected,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Icon(icon, key: ValueKey(selected), color: fg, size: 25),
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon (or button) stacked over a small caption — shared by tabs and Send.
class _NavLabel extends StatelessWidget {
  const _NavLabel({required this.child, required this.label, required this.color, this.bold = false});

  final Widget child;
  final String label;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        child,
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: context.tt.labelSmall?.copyWith(
              color: color,
              fontSize: 12,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Send to their widget',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          unawaited(HapticFeedback.selectionClick());
          unawaited(context.push('/send'));
        },
        child: ExcludeSemantics(
          child: _NavLabel(
            label: 'Send',
            color: context.cc.muted,
            // Gradient "plus" tile, like the design's primary action.
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Brand.royalLight, Brand.royal],
                ),
                boxShadow: [
                  BoxShadow(color: Brand.royal.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3)),
                ],
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}
