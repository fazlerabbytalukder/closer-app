import 'package:flutter/material.dart';

/// Glossy "candy" finish painted over a button's own background colour.
///
/// Every layer is translucent white/black, so it works on any colour without
/// changing it: lit top + shaded bottom for volume, a glassy highlight across
/// the upper half, a soft light rim along the bottom edge and a thin darker
/// outline. Used by the theme's button `backgroundBuilder`s and by
/// round icon buttons.
class Gloss extends StatelessWidget {
  const Gloss({
    super.key,
    this.child,
    this.circle = false,
    this.pressed = false,
    this.enabled = true,
    this.strength = 1,
  });

  /// Builds a `ButtonStyle.backgroundBuilder` that applies the gloss.
  static ButtonLayerBuilder builder({double strength = 1}) =>
      (context, states, child) => Gloss(
        pressed: states.contains(WidgetState.pressed),
        enabled: !states.contains(WidgetState.disabled),
        strength: strength,
        child: child,
      );

  final Widget? child;
  final bool circle;
  final bool pressed;
  final bool enabled;

  /// 0..1 — lower for light (white/outlined) buttons.
  final double strength;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child ?? const SizedBox.shrink();
    return CustomPaint(
      painter: _GlossPainter(circle: circle, pressed: pressed, strength: strength),
      child: child,
    );
  }
}

class _GlossPainter extends CustomPainter {
  _GlossPainter({required this.circle, required this.pressed, required this.strength});

  final bool circle;
  final bool pressed;
  final double strength;

  Color _w(double a) => Colors.white.withValues(alpha: (a * strength).clamp(0, 1));
  Color _b(double a) => Colors.black.withValues(alpha: (a * strength).clamp(0, 1));

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final r = circle ? size.shortestSide / 2 : size.height / 2;
    final body = RRect.fromRectAndRadius(rect, Radius.circular(r));
    final inset = circle ? size.width * 0.18 : r * 0.55;
    final hl = Rect.fromLTRB(inset, size.height * 0.06, size.width - inset, size.height * 0.5);

    // 1. Volume: lit top, shaded bottom (flipped a little when pressed).
    canvas
      ..drawRRect(
        body,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: pressed ? [_b(0.16), _b(0.02), _w(0.06)] : [_w(0.14), _b(0), _b(0.22)],
            stops: const [0, 0.5, 1],
          ).createShader(rect),
      )
      // 2. Glassy highlight across the upper half.
      ..drawRRect(
        RRect.fromRectAndRadius(hl, Radius.circular(hl.height / 2)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_w(pressed ? 0.18 : 0.42), _w(0.04)],
          ).createShader(hl),
      )
      // 3. Soft light rim along the bottom inner edge (light passing through).
      ..drawRRect(
        body.deflate(1.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1)
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_w(0), _w(0), _w(pressed ? 0.15 : 0.4)],
            stops: const [0, 0.55, 1],
          ).createShader(rect),
      )
      // 4. Thin darker outline, stronger at the bottom.
      ..drawRRect(
        body.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_b(0.08), _b(0.28)],
          ).createShader(rect),
      );
  }

  @override
  bool shouldRepaint(_GlossPainter old) => old.circle != circle || old.pressed != pressed || old.strength != strength;
}
