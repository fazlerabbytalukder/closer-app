import 'dart:math' as math;

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Colours used only by the dark splash/onboarding screens (Figma "Splash &
/// Onboarding Screen" frame).
abstract final class _C {
  static const bg = Color(0xFF17142E);
  static const tile = Color(0xFF2A2659);
  static const violetGlow = Color(0xFF8A4DFF);
  static const pinkGlow = Color(0xFFFF72C0);
  static const lilac = Color(0xFFC6B6FF);
  static const patternStroke = Color(0x38A98BFF); // #A98BFF @ 22%
  static const pink = Color(0xFFFF8FC4);
  static const heart = Color(0xFFFF5C9E);
  static const mint = Color(0xFF8CF0DA);
  static const violet = Color(0xFF6A3DF0);
}

/// Every screen in the frame is drawn on a 390 × 844 canvas.
const _designWidth = 390.0;

const _fredoka = AppTheme.displayFamily;
const _nunito = AppTheme.fontFamily;

// ---------------------------------------------------------------------------
// Splash
// ---------------------------------------------------------------------------

/// Branded splash: "Duosy" wordmark over the outlined-name pattern with the
/// two mascots peeking in from the bottom. Shown while auth loads (for at
/// least [SplashGate.minDuration]).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  /// The splash is shown first by `main()` and then again by the router;
  /// the entrance animation should only play the first time.
  static bool _entered = false;

  @override
  Widget build(BuildContext context) {
    final replay = _entered;
    _entered = true;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _C.bg,
        body: LayoutBuilder(
          builder: (context, box) {
            final s = box.maxWidth / _designWidth;
            return Stack(
              children: [
                const Positioned.fill(child: _NamePattern()),
                _Glow(left: -150, top: 384, size: 720, color: _C.violetGlow, alpha: 0.85, scale: s),
                _Glow(left: 90, top: 504, size: 460, color: _C.pinkGlow, alpha: 0.55, scale: s),
                // Mascots sit on the bottom edge on any screen height.
                Positioned(
                  left: 0,
                  bottom: 0,
                  width: 513 * s,
                  height: 456 * s,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      maxHeight: 567 * s,
                      child: Image.asset('assets/onboarding/splash_mascots.png', width: 513 * s, height: 567 * s)
                          .animate(autoPlay: !replay, value: replay ? 1 : 0)
                          .fadeIn(duration: 500.ms)
                          .slideY(begin: 0.12, end: 0, duration: 700.ms, curve: Curves.easeOutBack),
                    ),
                  ),
                ),
                _Sparkle(left: 320, top: 330, size: 22, color: _C.pink, scale: s, delay: 400),
                _Sparkle(left: 40, top: 372, size: 12, color: _C.lilac, scale: s, delay: 700),
                Positioned.fill(
                  child: SafeArea(
                    child: Padding(
                      padding: EdgeInsets.only(left: 32 * s, top: 48 * s),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Pill(text: 'Couple & Bestie Widget', scale: s)
                              .animate(autoPlay: !replay, value: replay ? 1 : 0)
                              .fadeIn(delay: 150.ms, duration: 400.ms)
                              .slideX(begin: -0.1, end: 0),
                          SizedBox(height: 18 * s),
                          Text(
                                'Duosy',
                                style: TextStyle(
                                  fontFamily: _fredoka,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 88 * s,
                                  height: 1,
                                  color: Colors.white,
                                  letterSpacing: -1,
                                ),
                              )
                              .animate(autoPlay: !replay, value: replay ? 1 : 0)
                              .fadeIn(delay: 250.ms, duration: 500.ms)
                              .scaleXY(begin: 0.92, end: 1),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.scale});

  final String text;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34 * scale,
      padding: EdgeInsets.symmetric(horizontal: 16 * scale),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17 * scale)),
      child: Center(
        widthFactor: 1,
        child: Text(
          text,
          style: TextStyle(fontFamily: _nunito, fontWeight: FontWeight.w800, fontSize: 13 * scale, color: Brand.ink),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Onboarding
// ---------------------------------------------------------------------------

class _Page {
  const _Page(this.title, this.body, this.art);

  final String title;
  final String body;
  final Widget art;
}

/// Three-step intro shown once, before sign-in. Swipe or tap Next; Skip and
/// Get Started both mark the intro as seen, which sends the router on to
/// the sign-in screen.
class IntroScreen extends ConsumerStatefulWidget {
  const IntroScreen({super.key});

  @override
  ConsumerState<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends ConsumerState<IntroScreen> {
  final _controller = PageController();
  int _index = 0;

  static const _pages = [
    _Page(
      'Right on Their Home Screen',
      'Send a photo, note or doodle that lands straight on their widget.',
      _HomeScreenArt(),
    ),
    _Page(
      'For Couples & Besties',
      'Countdowns, streaks, a shared plant and daily questions, made for two.',
      _TilesArt(),
    ),
    _Page('Private, Just for Two', 'No strangers, no public profiles. Only you and your person.', _PrivateArt()),
  ];

  bool get _last => _index == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() => ref.read(introSeenProvider.notifier).markSeen();

  void _next() {
    if (_last) return _finish();
    _controller.nextPage(duration: 380.ms, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_index];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _C.bg,
        body: LayoutBuilder(
          builder: (context, box) {
            final s = box.maxWidth / _designWidth;
            return Stack(
              children: [
                const Positioned.fill(child: _NamePattern()),
                // Art for every page, laid out on the 390-wide design canvas.
                Positioned.fill(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (_, i) => SafeArea(
                      bottom: false,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Transform.translate(
                          // Design frames include a 44pt status bar.
                          offset: Offset(0, -44 * s + 8),
                          child: SizedBox(
                            width: _designWidth * s,
                            height: 560 * s,
                            child: FittedBox(
                              alignment: Alignment.topLeft,
                              child: SizedBox(width: _designWidth, height: 560, child: _pages[i].art),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Fade the art into the text area (Figma: bottom 444pt, 0 → 30% → solid).
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: box.maxHeight * 0.48,
                  child: const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x0017142E), _C.bg, _C.bg],
                          stops: [0, 0.3, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: AnimatedOpacity(
                          opacity: _last ? 0 : 1,
                          duration: 200.ms,
                          child: TextButton(
                            onPressed: _last ? null : _finish,
                            style: TextButton.styleFrom(foregroundColor: _C.lilac),
                            child: const Text(
                              'Skip',
                              style: TextStyle(fontFamily: _nunito, fontWeight: FontWeight.w800, fontSize: 15),
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Dots(count: _pages.length, index: _index),
                            const SizedBox(height: 20),
                            KeyedSubtree(
                              key: ValueKey(_index),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    page.title,
                                    style: const TextStyle(
                                      fontFamily: _fredoka,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 30,
                                      height: 1.2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    page.body,
                                    style: const TextStyle(
                                      fontFamily: _nunito,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                      height: 1.55,
                                      color: _C.lilac,
                                    ),
                                  ),
                                ],
                              ).animate().fadeIn(duration: 320.ms).slideY(begin: 0.08, end: 0, curve: Curves.easeOut),
                            ),
                            const SizedBox(height: 36),
                            _WhiteButton(label: _last ? 'Get Started' : 'Next', arrow: !_last, onPressed: _next),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: 250.ms,
            curve: Curves.easeOut,
            margin: const EdgeInsets.only(right: 6),
            width: i == index ? 28 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: i == index ? 1 : 0.3),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

class _WhiteButton extends StatelessWidget {
  const _WhiteButton({required this.label, required this.onPressed, this.arrow = false});

  final String label;
  final VoidCallback onPressed;
  final bool arrow;

  @override
  Widget build(BuildContext context) {
    // Plain white pill (Figma: 334 × 56, #1E1B3A label) — deliberately not a
    // themed FilledButton, whose gloss/elevation layers show on white.
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: Material(
        color: Colors.white,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          splashColor: _C.violet.withValues(alpha: 0.12),
          highlightColor: _C.violet.withValues(alpha: 0.06),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontFamily: _nunito,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: Brand.ink,
                ),
              ),
              if (arrow) ...[
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, size: 18, color: Brand.ink),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page art (390 × 560 design canvas, positions straight from Figma)
// ---------------------------------------------------------------------------

/// Onboarding 1: a phone whose home screen shows a Duosy note widget.
class _HomeScreenArt extends StatelessWidget {
  const _HomeScreenArt();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const _Glow(left: -105, top: 0, size: 600, color: _C.violetGlow, alpha: 0.6),
        const _Glow(left: 160, top: 180, size: 380, color: _C.pinkGlow, alpha: 0.4),
        // Phone body.
        Positioned(
          left: 81,
          top: 97,
          width: 229,
          height: 439,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _C.bg.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(44),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1.5),
            ),
          ),
        ),
        Positioned(
          left: 163,
          top: 112,
          width: 64,
          height: 18,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
          ),
        ),
        // App icon grid.
        for (var r = 0; r < 2; r++)
          for (var c = 0; c < 4; c++)
            Positioned(
              left: 96.0 + c * 52,
              top: 377.0 + r * 52,
              width: 42,
              height: 42,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
        const Positioned(
          left: 81,
          width: 229,
          top: 351,
          child: Text(
            'Duosy',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: _nunito, fontWeight: FontWeight.w800, fontSize: 12, color: _C.lilac),
          ),
        ),
        // The note widget.
        Positioned(
          left: 96,
          top: 142,
          width: 198,
          height: 198,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [BoxShadow(color: _C.violetGlow.withValues(alpha: 0.7), blurRadius: 40)],
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 100,
                  top: 96,
                  child: Image.asset('assets/onboarding/ob1_mascot.png', width: 118, height: 146)
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .moveY(begin: 0, end: -4, duration: 1600.ms, curve: Curves.easeInOut),
                ),
                const Positioned(
                  left: 19,
                  top: 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NEW NOTE',
                        style: TextStyle(
                          fontFamily: _nunito,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          letterSpacing: 1,
                          color: Brand.grey700,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Thinking\nof you',
                        style: TextStyle(
                          fontFamily: _fredoka,
                          fontWeight: FontWeight.w600,
                          fontSize: 25,
                          height: 1.08,
                          color: Brand.ink,
                        ),
                      ),
                      SizedBox(height: 6),
                      CustomPaint(size: Size(80, 6), painter: _SquigglePainter()),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 450.ms).scaleXY(begin: 0.94, end: 1, curve: Curves.easeOutBack),
        ),
        // "Sent" chip.
        Positioned(
          left: 26,
          top: 310,
          child: Transform.rotate(
            angle: -0.12,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
              decoration: BoxDecoration(
                color: _C.mint,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 14, offset: Offset(4, 8))],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.send_rounded, size: 14, color: Brand.ink),
                  SizedBox(width: 6),
                  Text(
                    'Sent',
                    style: TextStyle(fontFamily: _nunito, fontWeight: FontWeight.w800, fontSize: 13, color: Brand.ink),
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(delay: 350.ms).slideX(begin: -0.3, end: 0, curve: Curves.easeOutBack),
        ),
        Positioned(
          left: 300,
          top: 124,
          child:
              Transform.rotate(
                    angle: 0.26,
                    child: Image.asset('assets/onboarding/ob1_heart.png', width: 38, height: 35),
                  )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scaleXY(begin: 0.92, end: 1.08, duration: 900.ms, curve: Curves.easeInOut),
        ),
        const _Sparkle(left: 42, top: 190, size: 18, color: _C.lilac),
      ],
    );
  }
}

/// Onboarding 2: four widget tiles — countdown, streak, plant, question.
class _TilesArt extends StatelessWidget {
  const _TilesArt();

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(fontFamily: _nunito, fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 1);
    const big = TextStyle(fontFamily: _fredoka, fontWeight: FontWeight.w600, fontSize: 46, height: 1);
    const caption = TextStyle(fontFamily: _nunito, fontWeight: FontWeight.w700, fontSize: 12, height: 1.3);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const _Glow(left: -105, top: 0, size: 600, color: _C.violetGlow, alpha: 0.6),
        const _Glow(left: -160, top: 200, size: 380, color: _C.pinkGlow, alpha: 0.4),
        _Tile(
          left: 28,
          top: 114,
          angle: -0.04,
          color: _C.pink,
          delay: 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('COUNTDOWN', style: label.copyWith(color: Brand.ink)),
              const Spacer(),
              Text('12', style: big.copyWith(color: Brand.ink)),
              const SizedBox(height: 4),
              Text('days to go', style: caption.copyWith(color: Brand.ink)),
            ],
          ),
        ),
        _Tile(
          left: 199,
          top: 114,
          angle: 0.03,
          color: _C.tile,
          border: true,
          delay: 80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('STREAK', style: label.copyWith(color: _C.lilac)),
                  const Spacer(),
                  Image.asset('assets/onboarding/ob2_flame.png', width: 14, height: 19),
                ],
              ),
              const Spacer(),
              Text('7', style: big.copyWith(color: Colors.white)),
              const SizedBox(height: 4),
              Text('days in a row', style: caption.copyWith(color: _C.lilac)),
            ],
          ),
        ),
        _Tile(
          left: 28,
          top: 279,
          angle: 0.03,
          color: _C.mint,
          delay: 160,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Text('OUR PLANT', style: label.copyWith(color: Brand.ink)),
              Positioned(
                right: -8,
                bottom: 2,
                child: Image.asset('assets/onboarding/ob2_plant.png', width: 78, height: 62)
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .rotate(begin: -0.01, end: 0.01, duration: 1400.ms, curve: Curves.easeInOut),
              ),
              Positioned(
                left: 0,
                bottom: 0,
                child: Text(
                  'Watered\ntoday',
                  style: caption.copyWith(color: Brand.ink, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
        _Tile(
          left: 199,
          top: 278,
          angle: -0.04,
          color: _C.violet,
          delay: 240,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('DAILY QUESTION', style: label.copyWith(color: Colors.white.withValues(alpha: 0.85))),
              const Spacer(),
              const Text(
                'What made you smile today?',
                style: TextStyle(
                  fontFamily: _fredoka,
                  fontWeight: FontWeight.w600,
                  fontSize: 19,
                  height: 1.2,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.left,
    required this.top,
    required this.angle,
    required this.color,
    required this.child,
    required this.delay,
    this.border = false,
  });

  final double left;
  final double top;
  final double angle;
  final Color color;
  final Widget child;
  final int delay;
  final bool border;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      width: 162,
      height: 156,
      child:
          Transform.rotate(
                angle: angle,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(26),
                    border: border ? Border.all(color: Colors.white.withValues(alpha: 0.16)) : null,
                    boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 28, offset: Offset(0, 16))],
                  ),
                  child: child,
                ),
              )
              .animate()
              .fadeIn(delay: delay.ms, duration: 400.ms)
              .scaleXY(begin: 0.9, end: 1, delay: delay.ms, duration: 500.ms, curve: Curves.easeOutBack),
    );
  }
}

/// Onboarding 3: the mascots inside a private circle, locked.
class _PrivateArt extends StatelessWidget {
  const _PrivateArt();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const _Glow(left: -105, top: -20, size: 600, color: _C.violetGlow, alpha: 0.65),
        const _Glow(left: 5, top: 90, size: 380, color: _C.pinkGlow, alpha: 0.4),
        Positioned(
          left: 26,
          top: 111,
          width: 339,
          height: 339,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1.5),
            ),
          ),
        ),
        Positioned(
          left: 71,
          top: 156,
          width: 249,
          height: 249,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _C.bg.withValues(alpha: 0.55),
              border: Border.all(color: Colors.white.withValues(alpha: 0.34), width: 1.5),
            ),
          ),
        ),
        // Strangers stay outside the circle.
        for (final (i, p) in const [(31.0, 139.0), (327.0, 197.0), (45.0, 372.0)].indexed)
          Positioned(
            left: p.$1,
            top: p.$2,
            child: Opacity(opacity: 0.7, child: Image.asset('assets/onboarding/ob3_orbit.png', width: 37, height: 37))
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .moveY(begin: 0, end: i.isEven ? -5 : 5, duration: (1500 + i * 300).ms, curve: Curves.easeInOut),
          ),
        Positioned(
          left: 92,
          top: 158,
          child: Image.asset('assets/onboarding/ob3_mascots.png', width: 210, height: 232)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(begin: 0, end: -6, duration: 1800.ms, curve: Curves.easeInOut),
        ),
        // Lock badge.
        Positioned(
          left: 161,
          top: 371,
          width: 68,
          height: 68,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _C.bg,
              boxShadow: [
                BoxShadow(
                  color: _C.violetGlow.withValues(alpha: 0.55),
                  blurRadius: 28,
                  spreadRadius: -6,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.all(6),
            child: const DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white),
              child: Icon(Icons.lock_outline_rounded, color: _C.violet, size: 24),
            ),
          ).animate().scaleXY(begin: 0.6, end: 1, delay: 250.ms, duration: 500.ms, curve: Curves.easeOutBack),
        ),
        const _Sparkle(left: 300, top: 128, size: 20, color: _C.pink),
        const _Sparkle(left: 318, top: 356, size: 12, color: _C.lilac, delay: 500),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

/// Rows of outlined "Duosy" words tilted 10°, behind every intro screen.
class _NamePattern extends StatelessWidget {
  const _NamePattern();

  @override
  Widget build(BuildContext context) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = _C.patternStroke;
    final style = TextStyle(
      fontFamily: _fredoka,
      fontWeight: FontWeight.w600,
      fontSize: 66,
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

/// Soft radial glow (Figma radial gradients that fade out at 66–68%).
class _Glow extends StatelessWidget {
  const _Glow({
    required this.left,
    required this.top,
    required this.size,
    required this.color,
    required this.alpha,
    this.scale = 1,
  });

  final double left;
  final double top;
  final double size;
  final Color color;
  final double alpha;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left * scale,
      top: top * scale,
      width: size * scale,
      height: size * scale,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: alpha),
                color.withValues(alpha: 0),
              ],
              stops: const [0, 0.67],
            ),
          ),
        ),
      ),
    );
  }
}

/// Four-point twinkle.
class _Sparkle extends StatelessWidget {
  const _Sparkle({
    required this.left,
    required this.top,
    required this.size,
    required this.color,
    this.scale = 1,
    this.delay = 0,
  });

  final double left;
  final double top;
  final double size;
  final Color color;
  final double scale;
  final int delay;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left * scale,
      top: top * scale,
      child: CustomPaint(size: Size.square(size * scale), painter: _SparklePainter(color))
          .animate(onPlay: (c) => c.repeat(reverse: true), delay: delay.ms)
          .scaleXY(begin: 0.7, end: 1.1, duration: 1100.ms, curve: Curves.easeInOut)
          .fade(begin: 0.6, end: 1, duration: 1100.ms),
    );
  }
}

class _SparklePainter extends CustomPainter {
  const _SparklePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final c = Offset(w / 2, h / 2);
    final path = Path()
      ..moveTo(c.dx, 0)
      ..quadraticBezierTo(c.dx + w * 0.08, c.dy - h * 0.08, w, c.dy)
      ..quadraticBezierTo(c.dx + w * 0.08, c.dy + h * 0.08, c.dx, h)
      ..quadraticBezierTo(c.dx - w * 0.08, c.dy + h * 0.08, 0, c.dy)
      ..quadraticBezierTo(c.dx - w * 0.08, c.dy - h * 0.08, c.dx, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.color != color;
}

/// Hand-drawn pink underline under "Thinking of you".
class _SquigglePainter extends CustomPainter {
  const _SquigglePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(0, size.height / 2);
    const waves = 4;
    final step = size.width / waves;
    for (var i = 0; i < waves; i++) {
      final x = i * step;
      path
        ..quadraticBezierTo(x + step / 4, i.isEven ? 0 : size.height, x + step / 2, size.height / 2)
        ..quadraticBezierTo(x + step * 3 / 4, i.isEven ? size.height : 0, x + step, size.height / 2);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = _C.heart
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SquigglePainter old) => false;
}
