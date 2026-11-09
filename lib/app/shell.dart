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

  /// Thickness of the slab's visible side edge.
  static const _thickness = 5.0;

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
    final faceSize = Size(size.width, size.height - _thickness);
    final face = _shape(faceSize);
    final side = face.shift(const Offset(0, _thickness));
    final faceRect = Offset.zero & faceSize;

    final faceTop = dark ? const Color(0xFF353A4B) : Colors.white;
    final faceBottom = dark ? const Color(0xFF242836) : const Color(0xFFF1EEFF);
    final sideTop = dark ? const Color(0xFF181B25) : const Color(0xFFD9D2FF);
    final sideBottom = dark ? const Color(0xFF0E1018) : const Color(0xFFB9AEF5);

    // 1. Ambient + contact shadows under the whole slab.
    canvas
      ..drawPath(
        side.shift(const Offset(0, 8)),
        Paint()
          ..color = const Color(0xFF5B50E0).withValues(alpha: dark ? 0.35 : 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
      )
      ..drawPath(
        side.shift(const Offset(0, 2)),
        Paint()
          ..color = const Color(0xFF2A2170).withValues(alpha: dark ? 0.5 : 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      )
      // 2. Side edge (slab thickness).
      ..drawPath(
        side,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [sideTop, sideBottom],
          ).createShader(Offset.zero & size),
      )
      // 3. Top-lit face.
      ..drawPath(
        face,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [faceTop, faceBottom],
          ).createShader(faceRect),
      )
      // 4. Glossy rim: bright along the top, fading out towards the bottom.
      ..drawPath(
        face,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: dark ? 0.25 : 1),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(faceRect),
      );

    // 5. Spherical dot resting in the notch.
    final c = Offset(notchX, depth / 2 - 1);
    const r = 5.5;
    canvas
      ..drawCircle(
        c + const Offset(0, 2),
        r,
        Paint()
          ..color = dotColor.withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      )
      ..drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.4, -0.5),
            radius: 0.9,
            colors: [Color.lerp(dotColor, Colors.white, 0.65)!, dotColor, Color.lerp(dotColor, Colors.black, 0.25)!],
            stops: const [0, 0.55, 1],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
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
    final fg = selected ? context.cs.primary : context.cs.onSurface.withValues(alpha: 0.8);
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
              child: Icon(
                icon,
                key: ValueKey(selected),
                color: fg,
                size: 26,
                shadows: [
                  if (selected)
                    Shadow(color: fg.withValues(alpha: 0.45), blurRadius: 8, offset: const Offset(0, 3))
                  else
                    const Shadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1)),
                ],
              ),
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
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
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
            color: context.cs.onSurface.withValues(alpha: 0.8),
            child: Icon(Icons.add_circle_outline_rounded, color: context.cs.primary, size: 26),
          ),
        ),
      ),
    );
  }
}
