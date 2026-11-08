import 'package:flutter/material.dart';

class Stroke {
  Stroke({required this.color, required this.width, required this.eraser});

  final Color color;
  final double width;
  final bool eraser;
  final points = <Offset>[];
}

/// Holds doodle strokes with undo.
class DoodleController extends ChangeNotifier {
  final strokes = <Stroke>[];
  Color color = const Color(0xFFFF6B8A);
  double width = 8;
  bool eraser = false;

  bool get isEmpty => strokes.isEmpty;

  void start(Offset p) {
    strokes.add(Stroke(color: color, width: width, eraser: eraser)..points.add(p));
    notifyListeners();
  }

  void extend(Offset p) {
    if (strokes.isEmpty) return;
    strokes.last.points.add(p);
    notifyListeners();
  }

  void undo() {
    if (strokes.isNotEmpty) {
      strokes.removeLast();
      notifyListeners();
    }
  }

  void clear() {
    strokes.clear();
    notifyListeners();
  }

  void setColor(Color c) {
    color = c;
    eraser = false;
    notifyListeners();
  }

  void setWidth(double w) {
    width = w;
    notifyListeners();
  }

  void toggleEraser() {
    eraser = !eraser;
    notifyListeners();
  }
}

/// Finger-drawing surface. Strokes are smoothed with quadratic curves
/// through midpoints; the eraser clears pixels within its own layer so it
/// works over a photo too.
class DoodleCanvas extends StatelessWidget {
  const DoodleCanvas({required this.controller, super.key, this.enabled = true});

  final DoodleController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: enabled ? (d) => controller.start(d.localPosition) : null,
      onPanUpdate: enabled ? (d) => controller.extend(d.localPosition) : null,
      child: ListenableBuilder(
        listenable: controller,
        builder: (_, _) => CustomPaint(
          painter: _DoodlePainter(controller.strokes, controller.strokes.fold(0, (a, s) => a + s.points.length)),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _DoodlePainter extends CustomPainter {
  _DoodlePainter(this.strokes, this.version);

  final List<Stroke> strokes;
  final int version;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    for (final s in strokes) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.eraser ? s.width * 2.5 : s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..blendMode = s.eraser ? BlendMode.clear : BlendMode.srcOver;
      final pts = s.points;
      if (pts.length == 1) {
        canvas.drawCircle(pts.first, paint.strokeWidth / 2, paint..style = PaintingStyle.fill);
        continue;
      }
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length - 1; i++) {
        final mid = (pts[i] + pts[i + 1]) / 2;
        path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(pts.last.dx, pts.last.dy);
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DoodlePainter old) => true;
}
