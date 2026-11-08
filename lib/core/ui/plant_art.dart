import 'dart:math' as math;

import 'package:closer_app/core/models/models.dart';
import 'package:flutter/material.dart';

/// The shared plant, drawn in code so it scales and animates smoothly.
/// Stage 0 = seed in a pot … stage 8 = big plant in full bloom.
class PlantArt extends StatelessWidget {
  const PlantArt({
    required this.stage,
    super.key,
    this.health = PlantHealth.healthy,
    this.size = 160,
    this.sway = 0,
  });

  final int stage;
  final PlantHealth health;
  final double size;

  /// -1..1, used for a gentle idle sway animation.
  final double sway;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Plant at stage $stage${health == PlantHealth.wilted ? ', wilted' : ''}',
      image: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: _PlantPainter(stage.clamp(0, 8), health == PlantHealth.wilted, sway),
      ),
    );
  }
}

class _PlantPainter extends CustomPainter {
  _PlantPainter(this.stage, this.wilted, this.sway);

  final int stage;
  final bool wilted;
  final double sway;

  static const _pot = Color(0xFFE08A5E);
  static const _potDark = Color(0xFFC86F45);
  static const _soil = Color(0xFF6B4A3A);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final leaf = wilted ? const Color(0xFFB5B26A) : const Color(0xFF5DBB63);
    final leafDark = wilted ? const Color(0xFF9A9455) : const Color(0xFF3F9A4A);
    final petal = wilted ? const Color(0xFFD8A8B2) : const Color(0xFFFF6B8A);

    // Pot.
    final potTop = h * 0.68;
    final potPath = Path()
      ..moveTo(w * 0.28, potTop)
      ..lineTo(w * 0.72, potTop)
      ..lineTo(w * 0.66, h * 0.96)
      ..quadraticBezierTo(w * 0.5, h * 0.99, w * 0.34, h * 0.96)
      ..close();
    canvas
      ..drawPath(potPath, Paint()..color = _pot)
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.24, potTop - h * 0.05, w * 0.52, h * 0.08),
          Radius.circular(h * 0.03),
        ),
        Paint()..color = _potDark,
      )
      ..drawOval(
        Rect.fromLTWH(w * 0.29, potTop - h * 0.045, w * 0.42, h * 0.04),
        Paint()..color = _soil,
      );

    // Face on the pot (cute!).
    final eye = Paint()..color = const Color(0xFF5A3426);
    canvas
      ..drawCircle(Offset(w * 0.43, h * 0.8), w * 0.012, eye)
      ..drawCircle(Offset(w * 0.57, h * 0.8), w * 0.012, eye);
    final smile = Path()
      ..moveTo(w * 0.46, h * 0.835)
      ..quadraticBezierTo(w * 0.5, wilted ? h * 0.82 : h * 0.86, w * 0.54, h * 0.835);
    canvas.drawPath(
      smile,
      Paint()
        ..color = const Color(0xFF5A3426)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.012
        ..strokeCap = StrokeCap.round,
    );

    final base = Offset(w * 0.5, potTop - h * 0.03);
    if (stage == 0) {
      // Seed.
      canvas.drawOval(
        Rect.fromCenter(center: base.translate(0, -h * 0.015), width: w * 0.07, height: w * 0.05),
        Paint()..color = const Color(0xFFB07A4F),
      );
      return;
    }

    // Stem height grows with stage.
    final stemH = h * (0.1 + stage * 0.055);
    final droop = wilted ? w * 0.12 : 0.0;
    final swayX = sway * w * 0.025;
    final top = base.translate(droop + swayX, -stemH + (wilted ? stemH * 0.25 : 0));
    final ctrl = base.translate(-w * 0.05 + swayX * 0.5, -stemH * 0.55);
    final stem = Path()
      ..moveTo(base.dx, base.dy)
      ..quadraticBezierTo(ctrl.dx, ctrl.dy, top.dx, top.dy);
    canvas.drawPath(
      stem,
      Paint()
        ..color = leafDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * (0.025 + stage * 0.002)
        ..strokeCap = StrokeCap.round,
    );

    // Leaves along the stem.
    final leafCount = math.min(2 + stage, 9);
    final metrics = stem.computeMetrics().first;
    for (var i = 0; i < leafCount; i++) {
      final t = 0.25 + 0.7 * (i / math.max(leafCount - 1, 1));
      final pos = metrics.getTangentForOffset(metrics.length * t)!.position;
      final left = i.isEven;
      final len = w * (0.08 + 0.012 * stage) * (1 - t * 0.35);
      final angle = (left ? -1 : 1) * (wilted ? 0.35 : 0.9) + (wilted ? 0.9 : 0);
      _leaf(canvas, pos, len, (left ? math.pi : 0) + (left ? angle : -angle) * 0.6 + (wilted ? 0.6 : 0), i.isEven ? leaf : leafDark.withValues(alpha: 0.9));
    }

    // Flowers from stage 4.
    if (stage >= 4) {
      final flowers = stage - 3;
      for (var i = 0; i < flowers; i++) {
        final t = i == 0 ? 1.0 : 0.45 + 0.5 * (i / flowers);
        final p = metrics.getTangentForOffset(metrics.length * t)!.position;
        final off = i == 0 ? Offset.zero : Offset((i.isEven ? -1 : 1) * w * 0.1, -h * 0.02);
        _flower(canvas, p + off, w * (i == 0 ? 0.075 : 0.05), petal);
      }
    } else {
      // Bud.
      canvas.drawCircle(top, w * 0.03, Paint()..color = leaf);
    }
  }

  void _leaf(Canvas canvas, Offset at, double len, double angle, Color color) {
    canvas
      ..save()
      ..translate(at.dx, at.dy)
      ..rotate(angle);
    final p = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(len * 0.5, -len * 0.45, len, 0)
      ..quadraticBezierTo(len * 0.5, len * 0.45, 0, 0);
    canvas
      ..drawPath(p, Paint()..color = color)
      ..restore();
  }

  void _flower(Canvas canvas, Offset c, double r, Color petal) {
    for (var i = 0; i < 5; i++) {
      final a = i * 2 * math.pi / 5 - math.pi / 2;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r * 0.75, r * 0.6, Paint()..color = petal);
    }
    canvas.drawCircle(c, r * 0.45, Paint()..color = const Color(0xFFFFD166));
  }

  @override
  bool shouldRepaint(_PlantPainter old) =>
      old.stage != stage || old.wilted != wilted || old.sway != sway;
}
