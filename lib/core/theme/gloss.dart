import 'package:material_ui/material_ui.dart';

/// Flat diagonal sheen painted over a button's own background colour.
///
/// Mirrors the design system's button gradient (#6878EA → #0722D8): a
/// translucent white wash in the top-left corner that fades out towards the
/// bottom-right, so any base colour reads as a soft two-tone gradient
/// without being changed. Used by the theme's button `backgroundBuilder`s
/// and by round icon buttons.
class Gloss extends StatelessWidget {
  const Gloss({
    super.key,
    this.child,
    this.circle = false,
    this.pressed = false,
    this.enabled = true,
    this.strength = 1,
    this.radius = 12,
  });

  /// Builds a `ButtonStyle.backgroundBuilder` that applies the sheen.
  static ButtonLayerBuilder builder({double strength = 1, double radius = 12}) =>
      (context, states, child) => Gloss(
        pressed: states.contains(WidgetState.pressed),
        enabled: !states.contains(WidgetState.disabled),
        strength: strength,
        radius: radius,
        child: child,
      );

  final Widget? child;
  final bool circle;
  final bool pressed;
  final bool enabled;

  /// 0..1 — lower for light buttons.
  final double strength;

  /// Corner radius of the button shape (ignored when [circle]).
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child ?? const SizedBox.shrink();
    return CustomPaint(
      painter: _SheenPainter(circle: circle, pressed: pressed, strength: strength, radius: radius),
      child: child,
    );
  }
}

class _SheenPainter extends CustomPainter {
  _SheenPainter({required this.circle, required this.pressed, required this.strength, required this.radius});

  final bool circle;
  final bool pressed;
  final double strength;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final r = circle ? size.shortestSide / 2 : radius;
    final a = (pressed ? 0.18 : 0.38) * strength;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(r)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: a),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_SheenPainter old) =>
      old.circle != circle || old.pressed != pressed || old.strength != strength || old.radius != radius;
}
