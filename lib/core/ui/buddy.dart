import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Mood of the little bear buddy.
enum BuddyMood {
  happy,
  sleepy,
  love,
  sad,
  angry,
  surprised;

  /// Best match for a free-form mood emoji ("😢" → sad).
  static BuddyMood fromEmoji(String? emoji) {
    final e = emoji ?? '';
    bool any(String set) => set.characters.any(e.contains);
    if (any('😢😭😔😞🥺😿💔😟🙁☹😓😥')) return BuddyMood.sad;
    if (any('😠😡🤬😤👿💢')) return BuddyMood.angry;
    if (any('🥰😍😘❤💕💖💗💞😻🤗')) return BuddyMood.love;
    if (any('😴🥱💤😪')) return BuddyMood.sleepy;
    if (any('😮😲😯🤯😱🙀')) return BuddyMood.surprised;
    return BuddyMood.happy;
  }
}

/// Cute, softly shaded ("3D") bear buddy, drawn in code so it scales
/// crisply. It breathes, blinks, looks around and acts out its [mood]:
///
/// * happy: open smile, waves a paw
/// * love: heart eyes, hugs a beating heart, hearts float up
/// * sleepy: closed eyes, slow breathing, "z z z"
/// * sad: droopy brows, frown, a tear rolls down
/// * angry: frowning brows, red cheeks, shaking fists, steam puffs
/// * surprised: big eyes, raised brows, "O" mouth, hands up
///
/// Tap it and it hops and reacts (when [interactive]).
class Buddy extends StatefulWidget {
  const Buddy({
    super.key,
    this.size = 96,
    this.color = const Color(0xFFFF9A4D),
    this.mood = BuddyMood.happy,
    this.withBody = false,
    this.interactive = true,
  });

  final double size;
  final Color color;
  final BuddyMood mood;
  final bool withBody;
  final bool interactive;

  @override
  State<Buddy> createState() => _BuddyState();
}

class _BuddyState extends State<Buddy> with TickerProviderStateMixin {
  /// Free-running clock (seconds) for idle motion.
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 60));

  /// The hop when tapped.
  late final AnimationController _hop = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));

  /// Mood shown for a moment after a tap.
  BuddyMood? _reaction;
  int _taps = 0;

  @override
  void initState() {
    super.initState();
    _clock.repeat();
  }

  @override
  void dispose() {
    _clock.dispose();
    _hop.dispose();
    super.dispose();
  }

  Future<void> _tap() async {
    const reactions = [BuddyMood.love, BuddyMood.surprised, BuddyMood.happy];
    final r = reactions[_taps++ % reactions.length];
    HapticFeedback.lightImpact().ignore();
    setState(() => _reaction = r);
    await _hop.forward(from: 0);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted && _reaction == r) setState(() => _reaction = null);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final w = widget.size;
    final paint = AnimatedBuilder(
      animation: Listenable.merge([_clock, _hop]),
      builder: (context, _) => CustomPaint(
        size: Size(w, widget.withBody ? w * 1.25 : w),
        painter: _BuddyPainter(
          color: widget.color,
          mood: _reaction ?? widget.mood,
          withBody: widget.withBody,
          t: still ? 0 : _clock.value * 60,
          hop: _hop.value,
        ),
      ),
    );
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: widget.interactive
            ? GestureDetector(behavior: HitTestBehavior.opaque, onTap: _tap, child: paint)
            : paint,
      ),
    );
  }
}

class _BuddyPainter extends CustomPainter {
  _BuddyPainter({required this.color, required this.mood, required this.withBody, required this.t, required this.hop});

  final Color color;
  final BuddyMood mood;
  final bool withBody;

  /// Seconds, for idle motion.
  final double t;

  /// 0..1 progress of the tap hop.
  final double hop;

  static const _ink = Color(0xFF2B2240);
  static const _cream = Color(0xFFFFF3E8);
  static const _heartRed = Color(0xFFFF4F7B);

  late double w;
  late double cx;

  Color _shade(double dl) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness + dl).clamp(0.0, 1.0)).toColor();
  }

  /// Soft 3D fill: lit from the top left.
  Paint _ball(Rect r, Color base, {double light = 0.13, double dark = -0.14}) {
    final hsl = HSLColor.fromColor(base);
    Color l(double d) => hsl.withLightness((hsl.lightness + d).clamp(0.0, 1.0)).toColor();
    return Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.45),
        radius: 1.05,
        colors: [l(light), base, l(dark)],
        stops: const [0, 0.55, 1],
      ).createShader(r);
  }

  @override
  void paint(Canvas canvas, Size size) {
    w = size.width;
    cx = w / 2;

    // Idle motion.
    final sleepy = mood == BuddyMood.sleepy;
    final breath = math.sin(t * (sleepy ? 1.4 : 2.4)) * (sleepy ? 0.03 : 0.018);
    final shake = mood == BuddyMood.angry ? math.sin(t * 38) * w * 0.008 : 0.0;
    final hopY = -math.sin(math.pi * hop) * w * 0.14;
    final squash = hop > 0 && hop < 0.15 ? 1 - hop * 0.6 : 1.0;
    final tilt = switch (mood) {
      BuddyMood.sad => -0.08 + math.sin(t * 0.8) * 0.02,
      BuddyMood.sleepy => 0.12 + math.sin(t * 1.4) * 0.04,
      BuddyMood.love => math.sin(t * 2.2) * 0.07,
      _ => math.sin(t * 1.1) * 0.04,
    };

    final groundY = withBody ? w * 1.22 : w * 0.95;

    // Ground shadow (shrinks while hopping).
    final shadowScale = 1 - math.sin(math.pi * hop) * 0.35;
    canvas
      ..drawOval(
        Rect.fromCenter(center: Offset(cx, groundY), width: w * 0.62 * shadowScale, height: w * 0.08 * shadowScale),
        Paint()
          ..color = const Color(0x33000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.03),
      )
      ..save()
      ..translate(shake, hopY)
      // Squash on take-off, from the feet.
      ..translate(cx, groundY)
      ..scale(1 + (1 - squash) * 0.5, squash)
      ..translate(-cx, -groundY);

    if (withBody) _body(canvas, breath);

    // Head, tilted around the neck, bobbing with the breath.
    final neck = Offset(cx, withBody ? w * 0.82 : w * 0.84);
    canvas
      ..save()
      ..translate(neck.dx, neck.dy + breath * w * 0.4)
      ..rotate(tilt)
      ..translate(-neck.dx, -neck.dy);
    _head(canvas);
    canvas.restore();

    if (!withBody) _headOnlyPaws(canvas);
    canvas.restore();

    _effects(canvas);
  }

  // ------------------------------------------------------------------ body

  void _body(Canvas canvas, double breath) {
    final bodyC = Offset(cx, w * 1.0);
    final bw = w * 0.66 * (1 + breath);
    final bh = w * 0.5 * (1 - breath * 0.5);
    final bodyRect = Rect.fromCenter(center: bodyC, width: bw, height: bh);

    // Feet.
    for (final s in [-1.0, 1.0]) {
      final f = Rect.fromCenter(center: Offset(cx + s * w * 0.17, w * 1.19), width: w * 0.22, height: w * 0.12);
      canvas
        ..drawOval(f, _ball(f, _shade(-0.04)))
        ..drawOval(
          Rect.fromCenter(center: f.center.translate(0, w * 0.005), width: w * 0.1, height: w * 0.05),
          Paint()..color = _cream.withValues(alpha: 0.9),
        );
    }

    canvas
      ..drawOval(bodyRect, _ball(bodyRect, color))
      ..drawOval(
        Rect.fromCenter(center: bodyC.translate(0, w * 0.04), width: bw * 0.56, height: bh * 0.62),
        _ball(bodyRect, _cream, light: 0.02, dark: -0.06),
      );

    _arms(canvas);
  }

  void _arms(Canvas canvas) {
    // Angle from straight down; positive = out to the side, up past 1.6.
    double spreadL;
    double spreadR;
    switch (mood) {
      case BuddyMood.happy:
        spreadL = 0.4;
        // Wave for ~1.6 s every 5 s.
        final phase = t % 5;
        spreadR = phase < 1.6 ? 2.3 + math.sin(phase * 11) * 0.35 : 0.4;
      case BuddyMood.love:
        // Hugging the heart.
        spreadL = spreadR = -0.75 + math.sin(t * 6) * 0.04;
      case BuddyMood.sleepy:
        spreadL = 0.22;
        spreadR = 0.22;
      case BuddyMood.sad:
        spreadL = spreadR = 0.12 + math.sin(t * 0.8) * 0.02;
      case BuddyMood.angry:
        // Fists up and shaking.
        spreadL = 1.25 + math.sin(t * 30) * 0.08;
        spreadR = 1.25 + math.sin(t * 30 + 1) * 0.08;
      case BuddyMood.surprised:
        spreadL = spreadR = 2.55 + math.sin(t * 5) * 0.05;
    }

    // Love: the heart sits on the belly, under the paws.
    if (mood == BuddyMood.love) {
      final beat = 1 + math.max(0, math.sin(t * 7)) * 0.12;
      _heart(canvas, Offset(cx, w * 1.0), w * 0.26 * beat, _heartPaint(Offset(cx, w * 1.0), w * 0.26));
    }

    for (final s in [-1.0, 1.0]) {
      final spread = s < 0 ? spreadL : spreadR;
      final shoulder = Offset(cx + s * w * 0.26, w * 0.86);
      final angle = math.pi / 2 - s * spread;
      final len = w * 0.2;
      final aw = w * 0.13;
      canvas
        ..save()
        ..translate(shoulder.dx, shoulder.dy)
        ..rotate(angle - math.pi / 2);
      final arm = RRect.fromLTRBR(-aw / 2, -aw / 2, aw / 2, len, Radius.circular(aw / 2));
      canvas
        ..drawRRect(arm, _ball(arm.outerRect, color))
        // Paw pad.
        ..drawCircle(Offset(0, len - aw * 0.32), aw * 0.22, Paint()..color = _cream.withValues(alpha: 0.85))
        ..restore();
    }
  }

  /// Head-only buddy: a paw pops up to wave, or two paws hold a heart.
  void _headOnlyPaws(Canvas canvas) {
    if (mood == BuddyMood.happy) {
      final phase = t % 5;
      if (phase > 1.8) return;
      final rise =
          Curves.easeOut.transform((phase / 0.3).clamp(0.0, 1.0)) *
          Curves.easeIn.transform(((1.8 - phase) / 0.3).clamp(0.0, 1.0));
      final pivot = Offset(cx + w * 0.36, w * 0.92);
      canvas
        ..save()
        ..translate(pivot.dx, pivot.dy + (1 - rise) * w * 0.2)
        ..rotate(-0.3 + math.sin(phase * 11) * 0.3);
      final paw = Rect.fromCenter(center: Offset(0, -w * 0.08), width: w * 0.16, height: w * 0.2);
      canvas
        ..drawOval(paw, _ball(paw, color))
        ..drawCircle(Offset(0, -w * 0.11), w * 0.035, Paint()..color = _cream)
        ..restore();
    } else if (mood == BuddyMood.love) {
      final c = Offset(cx, w * 0.9);
      final beat = 1 + math.max(0, math.sin(t * 7)) * 0.12;
      _heart(canvas, c, w * 0.22 * beat, _heartPaint(c, w * 0.22));
      for (final s in [-1.0, 1.0]) {
        final paw = Rect.fromCenter(center: c.translate(s * w * 0.1, w * 0.03), width: w * 0.12, height: w * 0.1);
        canvas.drawOval(paw, _ball(paw, color));
      }
    }
  }

  // ------------------------------------------------------------------ head

  void _head(Canvas canvas) {
    final headR = w * 0.36;
    final headC = Offset(cx, w * 0.52);
    final headRect = Rect.fromCenter(center: headC, width: headR * 2.1, height: headR * 1.9);

    // Ears (twitch now and then; droop when sad).
    final earTwitch = (t % 7) < 0.25 ? math.sin((t % 7) * 50) * 0.12 : 0.0;
    final droop = mood == BuddyMood.sad ? headR * 0.12 : 0.0;
    for (final s in [-1.0, 1.0]) {
      final ear = Offset(cx + s * headR * (0.78 + droop / headR * 0.4), headC.dy - headR * 0.8 + droop);
      canvas
        ..save()
        ..translate(ear.dx, ear.dy)
        ..rotate(s * earTwitch)
        ..translate(-ear.dx, -ear.dy);
      final outer = Rect.fromCircle(center: ear, radius: headR * 0.34);
      canvas
        ..drawOval(outer, _ball(outer, color))
        ..drawCircle(ear.translate(0, headR * 0.02), headR * 0.19, _ball(outer, const Color(0xFFFFB3C7), light: 0.08))
        ..restore();
    }

    // Head with a soft 3D gradient and a rim of light.
    canvas
      ..drawOval(headRect, _ball(headRect, color))
      ..drawOval(
        Rect.fromCenter(center: headC.translate(-headR * 0.42, -headR * 0.5), width: headR * 0.7, height: headR * 0.36),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.28)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, headR * 0.12),
      );

    // Angry: red flush on the forehead.
    if (mood == BuddyMood.angry) {
      final pulse = 0.35 + math.sin(t * 6) * 0.15;
      canvas.drawOval(
        Rect.fromCenter(center: headC.translate(0, -headR * 0.45), width: headR * 1.4, height: headR * 0.6),
        Paint()
          ..color = const Color(0xFFFF3B3B).withValues(alpha: pulse)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, headR * 0.2),
      );
    }

    // Muzzle.
    final muzzle = headC.translate(0, headR * 0.36);
    final muzzleRect = Rect.fromCenter(center: muzzle, width: headR * 0.98, height: headR * 0.72);
    canvas.drawOval(muzzleRect, _ball(muzzleRect, _cream, light: 0.03, dark: -0.08));

    // Nose, glossy.
    final noseRect = Rect.fromCenter(
      center: muzzle.translate(0, -headR * 0.13),
      width: headR * 0.32,
      height: headR * 0.21,
    );
    canvas
      ..drawOval(noseRect, _ball(noseRect, _ink, light: 0.25, dark: -0.05))
      ..drawOval(
        Rect.fromCenter(
          center: noseRect.center.translate(-headR * 0.05, -headR * 0.04),
          width: headR * 0.1,
          height: headR * 0.05,
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.7),
      );

    _mouth(canvas, muzzle, headR);
    _eyes(canvas, headC, headR);
  }

  void _mouth(Canvas canvas, Offset muzzle, double r) {
    final line = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, w * 0.018)
      ..strokeCap = StrokeCap.round;
    final m = muzzle.translate(0, r * 0.06);
    switch (mood) {
      case BuddyMood.happy:
      case BuddyMood.love:
        // Open smile with a little tongue.
        final rect = Rect.fromCenter(center: m.translate(0, r * 0.02), width: r * 0.36, height: r * 0.3);
        final mouth = Path()
          ..moveTo(rect.left, rect.top)
          ..quadraticBezierTo(rect.center.dx, rect.top + r * 0.04, rect.right, rect.top)
          ..arcToPoint(Offset(rect.left, rect.top), radius: Radius.circular(r * 0.18))
          ..close();
        canvas
          ..drawPath(mouth, Paint()..color = const Color(0xFF7A2E3E))
          ..save()
          ..clipPath(mouth)
          ..drawCircle(Offset(rect.center.dx, rect.bottom), r * 0.12, Paint()..color = const Color(0xFFFF7A9C))
          ..restore();
      case BuddyMood.sleepy:
        canvas.drawOval(
          Rect.fromCenter(
            center: m.translate(0, r * 0.04),
            width: r * 0.12,
            height: r * (0.1 + math.sin(t * 1.4) * 0.03),
          ),
          Paint()..color = const Color(0xFF7A2E3E),
        );
      case BuddyMood.sad:
        canvas.drawArc(
          Rect.fromCenter(center: m.translate(0, r * 0.14), width: r * 0.3, height: r * 0.2),
          math.pi * 1.1,
          math.pi * 0.8,
          false,
          line,
        );
      case BuddyMood.angry:
        // Gritted, wobbly frown.
        final path = Path()..moveTo(m.dx - r * 0.18, m.dy + r * 0.1);
        for (var i = 1; i <= 4; i++) {
          path.lineTo(m.dx - r * 0.18 + i * r * 0.09, m.dy + r * (i.isOdd ? 0.04 : 0.1));
        }
        canvas.drawPath(path, line);
      case BuddyMood.surprised:
        final o = Rect.fromCenter(
          center: m.translate(0, r * 0.06),
          width: r * 0.16,
          height: r * (0.2 + math.sin(t * 5) * 0.02),
        );
        canvas.drawOval(o, Paint()..color = const Color(0xFF7A2E3E));
    }
  }

  void _eyes(Canvas canvas, Offset headC, double r) {
    final eyeY = headC.dy - r * 0.08;
    final line = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, w * 0.02)
      ..strokeCap = StrokeCap.round;

    // Blink: a quick close every ~3.8 s (double blink now and then).
    final bp = t % 3.8;
    final blink = bp < 0.14 || (t % 11.4 > 3.8 && t % 11.4 < 4.1 && bp > 0.22 && bp < 0.34);
    final lookX = math.sin(t * 0.45) * r * 0.035;
    final lookY = mood == BuddyMood.sad ? r * 0.04 : 0.0;

    for (final s in [-1.0, 1.0]) {
      final e = Offset(cx + s * r * 0.42, eyeY);

      // Blush.
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx + s * r * 0.68, eyeY + r * 0.3), width: r * 0.32, height: r * 0.18),
        Paint()
          ..color = (mood == BuddyMood.angry ? const Color(0xFFFF4040) : const Color(0xFFFF7A9C)).withValues(
            alpha: mood == BuddyMood.love ? 0.75 : 0.5,
          )
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.05),
      );

      switch (mood) {
        case BuddyMood.love:
          final beat = 1 + math.max(0, math.sin(t * 7 + s)) * 0.18;
          _heart(canvas, e, r * 0.3 * beat, _heartPaint(e, r * 0.3));
        case BuddyMood.sleepy:
          canvas.drawArc(
            Rect.fromCenter(center: e, width: r * 0.26, height: r * 0.18),
            0.15,
            math.pi - 0.3,
            false,
            line,
          );
        case BuddyMood.happy when blink:
        case BuddyMood.sad when blink:
        case BuddyMood.surprised when blink:
          canvas.drawLine(e.translate(-r * 0.1, 0), e.translate(r * 0.1, 0), line);
        case BuddyMood.angry:
          // -s points to the middle of the face: angry brows slope down
          // toward it.
          // The frowning brow cuts off the top of the eye.
          canvas
            ..save()
            ..clipPath(
              Path()
                ..moveTo(e.dx - s * r * 0.14, e.dy - r * 0.03)
                ..lineTo(e.dx + s * r * 0.22, e.dy - r * 0.2)
                ..lineTo(e.dx + s * r * 0.22, e.dy + r * 0.3)
                ..lineTo(e.dx - s * r * 0.14, e.dy + r * 0.3)
                ..close(),
            );
          _eyeBall(canvas, e.translate(lookX * 0.3, r * 0.03), r * 0.11, r);
          canvas
            ..restore()
            ..drawLine(e.translate(-s * r * 0.14, -r * 0.03), e.translate(s * r * 0.22, -r * 0.2), line);
        case BuddyMood.happy:
          _eyeBall(canvas, e.translate(lookX, 0), r * 0.12, r);
        case BuddyMood.sad:
          _eyeBall(canvas, e.translate(lookX * 0.4, lookY), r * 0.12, r, wet: true);
          // Worried brows: higher toward the middle of the face.
          canvas.drawLine(e.translate(-s * r * 0.12, -r * 0.32), e.translate(s * r * 0.16, -r * 0.2), line);
        case BuddyMood.surprised:
          _eyeBall(canvas, e, r * 0.15, r, wet: true);
          canvas.drawArc(
            Rect.fromCenter(center: e.translate(0, -r * 0.32), width: r * 0.26, height: r * 0.12),
            math.pi * 1.1,
            math.pi * 0.8,
            false,
            line,
          );
      }
    }

    // Sad: a tear rolls down one cheek every few seconds.
    if (mood == BuddyMood.sad) {
      final p = (t % 3.2) / 3.2;
      final start = Offset(cx - r * 0.5, eyeY + r * 0.12);
      final drop = start.translate(-r * 0.04 * p, r * 0.6 * Curves.easeIn.transform(p));
      final a = p < 0.8 ? 1.0 : (1 - p) / 0.2;
      final tear = Path()
        ..moveTo(drop.dx, drop.dy - r * 0.1)
        ..quadraticBezierTo(drop.dx + r * 0.07, drop.dy, drop.dx, drop.dy + r * 0.05)
        ..quadraticBezierTo(drop.dx - r * 0.07, drop.dy, drop.dx, drop.dy - r * 0.1);
      canvas.drawPath(tear, Paint()..color = const Color(0xFF7CC4FF).withValues(alpha: a));
    }
  }

  /// Glossy eye with two catch-lights.
  void _eyeBall(Canvas canvas, Offset c, double radius, double r, {bool wet = false}) {
    final rect = Rect.fromCircle(center: c, radius: radius);
    canvas
      ..drawOval(rect, _ball(rect, _ink, light: 0.2, dark: -0.05))
      ..drawCircle(
        c.translate(-radius * 0.35, -radius * 0.38),
        radius * (wet ? 0.42 : 0.34),
        Paint()..color = Colors.white,
      )
      ..drawCircle(
        c.translate(radius * 0.35, radius * 0.3),
        radius * 0.16,
        Paint()..color = Colors.white.withValues(alpha: 0.85),
      );
  }

  // --------------------------------------------------------------- effects

  /// Floating hearts, z's, steam and "!" around the buddy.
  void _effects(Canvas canvas) {
    final top = w * 0.12;
    switch (mood) {
      case BuddyMood.love:
        for (var i = 0; i < 3; i++) {
          final p = ((t * 0.5) + i / 3) % 1;
          final x = cx + w * (0.32 + i * 0.06) * (i.isEven ? 1 : -1) + math.sin(p * 8 + i) * w * 0.04;
          final y = top + w * 0.25 - p * w * 0.4;
          final a = p < 0.15 ? p / 0.15 : (1 - p);
          _heart(canvas, Offset(x, y), w * (0.08 + i * 0.015), Paint()..color = _heartRed.withValues(alpha: a * 0.9));
        }
      case BuddyMood.sleepy:
        for (var i = 0; i < 3; i++) {
          final p = ((t * 0.35) + i / 3) % 1;
          final a = p < 0.2 ? p / 0.2 : (1 - p);
          _text(
            canvas,
            'z',
            Offset(cx + w * (0.3 + p * 0.15), top + w * 0.1 - p * w * 0.3),
            w * (0.1 + p * 0.06),
            const Color(0xFF7C6CF2).withValues(alpha: a),
          );
        }
      case BuddyMood.angry:
        for (final s in [-1.0, 1.0]) {
          final p = ((t * 0.9) + (s > 0 ? 0.5 : 0)) % 1;
          final c = Offset(cx + s * w * (0.42 + p * 0.06), top + w * 0.14 - p * w * 0.18);
          canvas.drawCircle(
            c,
            w * (0.035 + p * 0.045),
            Paint()
              ..color = Colors.white.withValues(alpha: (1 - p) * 0.85)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.01),
          );
        }
      case BuddyMood.surprised:
        final bounce = math.sin(t * 8).abs() * w * 0.03;
        _text(canvas, '!', Offset(cx + w * 0.38, top - bounce), w * 0.18, const Color(0xFFFFB020));
      case BuddyMood.happy:
        // A little sparkle now and then.
        final p = (t % 4) / 4;
        if (p < 0.3) {
          final a = math.sin(p / 0.3 * math.pi);
          _sparkle(canvas, Offset(cx - w * 0.4, top + w * 0.12), w * 0.06 * a, Colors.white.withValues(alpha: a));
        }
      case BuddyMood.sad:
        break;
    }
  }

  void _text(Canvas canvas, String s, Offset at, double fontSize, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w900, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  void _sparkle(Canvas canvas, Offset c, double s, Color color) {
    final p = Path()
      ..moveTo(c.dx, c.dy - s)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + s, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + s)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - s, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - s);
    canvas.drawPath(p, Paint()..color = color);
  }

  Paint _heartPaint(Offset c, double s) => Paint()
    ..shader = const RadialGradient(
      center: Alignment(-0.4, -0.5),
      colors: [Color(0xFFFF9DB5), _heartRed, Color(0xFFD62E5C)],
      stops: [0, 0.55, 1],
    ).createShader(Rect.fromCircle(center: c, radius: s * 0.6));

  void _heart(Canvas canvas, Offset c, double s, Paint p) {
    final path = Path()
      ..moveTo(c.dx, c.dy + s * 0.35)
      ..cubicTo(c.dx - s * 0.6, c.dy - s * 0.05, c.dx - s * 0.3, c.dy - s * 0.55, c.dx, c.dy - s * 0.2)
      ..cubicTo(c.dx + s * 0.3, c.dy - s * 0.55, c.dx + s * 0.6, c.dy - s * 0.05, c.dx, c.dy + s * 0.35)
      ..close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_BuddyPainter old) =>
      old.t != t || old.hop != hop || old.mood != mood || old.color != color || old.withBody != withBody;
}
