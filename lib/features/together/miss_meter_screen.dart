import 'dart:math' as math;

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/soft_ui.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

/// Deep pink of the meter (Figma "miss-o-meter screen").
const _meterPink = Color(0xFFD6246E);

/// "How much do you miss me?" — both pick privately, then a joint reveal
/// with two gauges filling up at the same time.
class MissMeterScreen extends ConsumerStatefulWidget {
  const MissMeterScreen({super.key});

  @override
  ConsumerState<MissMeterScreen> createState() => _MissMeterScreenState();
}

class _MissMeterScreenState extends ConsumerState<MissMeterScreen> {
  double _value = 60;
  bool _busy = false;

  Future<void> _submit() async {
    setState(() => _busy = true);
    final ok = await runAction(context, () => ref.read(backendProvider).submitMissMeter(_value.round()));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) hapticMedium();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authUidProvider).value;
    final name = ref.watch(partnerNameProvider);
    final today = ref.watch(todayMissMeterProvider);
    final history = (ref.watch(missMetersProvider).value ?? const <MissMeter>[])
        .where((m) => m.revealed && m.date != today?.date)
        .take(7)
        .toList();
    final partnerAnswered = today?.answeredBy.any((u) => u != me) ?? false;

    return Scaffold(
      body: Column(
        children: [
          const PlainPageHeader(title: 'Miss-o-meter', boxed: true),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                if (today != null && today.revealed && me != null)
                  _Reveal(meter: today, me: me, name: name)
                else if (today?.myValue != null)
                  _Waiting(value: today!.myValue!, name: name)
                else
                  _Picker(
                    value: _value,
                    name: name,
                    partnerAnswered: partnerAnswered,
                    busy: _busy,
                    onChanged: (v) {
                      if ((v / 10).floor() != (_value / 10).floor()) hapticSoft();
                      setState(() => _value = v);
                    },
                    onSubmit: _submit,
                  ),
                if (history.isNotEmpty && me != null) ...[
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 10),
                    child: Text('Past days', style: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  for (final m in history) _HistoryRow(meter: m, me: me, name: name),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _emojiFor(int v) => switch (v) {
  < 15 => '🙂',
  < 35 => '🥲',
  < 60 => '🥺',
  < 85 => '😭',
  _ => '🚀',
};

/// White rounded card with the soft violet shadow.
class _MeterCard extends StatelessWidget {
  const _MeterCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
      decoration: BoxDecoration(
        color: context.cc.card,
        borderRadius: BorderRadius.circular(28),
        boxShadow: dark ? null : softCardShadow,
      ),
      child: child,
    );
  }
}

/// Half-circle gauge on a lavender track: either rounded dashes or one
/// solid arc, filled up to [fraction].
class _Gauge extends StatelessWidget {
  const _Gauge({
    required this.fraction,
    required this.color,
    required this.child,
    this.width = 190,
    this.dashed = true,
  });

  final double fraction;
  final Color color;
  final Widget child;
  final double width;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final stroke = width * 0.085;
    return SizedBox(
      width: width,
      height: width / 2 + stroke / 2,
      child: CustomPaint(
        painter: _GaugePainter(
          fraction: fraction.clamp(0, 1),
          color: color,
          track: dark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFEDE7FF),
          stroke: stroke,
          dashed: dashed,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: stroke * 0.2),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({
    required this.fraction,
    required this.color,
    required this.track,
    required this.stroke,
    required this.dashed,
  });

  final double fraction;
  final Color color;
  final Color track;
  final double stroke;
  final bool dashed;

  static const _dashes = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - stroke / 2;
    final rect = Rect.fromCircle(center: Offset(size.width / 2, size.width / 2), radius: r);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, p..color = track);
    p.color = color;
    if (!dashed) {
      if (fraction > 0) canvas.drawArc(rect, math.pi, math.pi * fraction, false, p);
      return;
    }
    // Rounded dashes, lit one by one as the value grows.
    final lit = (fraction * _dashes).ceil();
    const slot = math.pi / _dashes;
    final cap = stroke / 2 / r; // round caps stick out by half the stroke
    for (var i = 0; i < lit; i++) {
      canvas.drawArc(rect, math.pi + i * slot + slot * 0.2 + cap, slot * 0.6 - cap * 2, false, p);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction || old.color != color || old.track != track || old.dashed != dashed;
}

class _Picker extends StatelessWidget {
  const _Picker({
    required this.value,
    required this.name,
    required this.partnerAnswered,
    required this.busy,
    required this.onChanged,
    required this.onSubmit,
  });

  final double value;
  final String name;
  final bool partnerAnswered;
  final bool busy;
  final ValueChanged<double> onChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final v = value.round();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return _MeterCard(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              'How much do you miss $name today?',
              textAlign: TextAlign.center,
              style: context.tt.headlineSmall?.copyWith(fontSize: 22, height: 1.2),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            partnerAnswered
                ? '$name already answered 👀 Your turn!'
                : 'Your answer stays secret until $name answers too',
            textAlign: TextAlign.center,
            style: context.tt.bodySmall?.copyWith(color: context.cc.muted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 26),
          _Gauge(
            fraction: v / MissMeter.max,
            color: _meterPink,
            child: Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: SoftTone.pink.fill(context), shape: BoxShape.circle),
              child: AnimatedSwitcher(
                duration: 200.ms,
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: Text(_emojiFor(v), key: ValueKey(_emojiFor(v)), style: const TextStyle(fontSize: 36)),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '$v%',
            style: context.tt.displaySmall?.copyWith(fontWeight: FontWeight.w700, color: _meterPink, fontSize: 38),
          ),
          Text(MissMeter.describe(v), style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 8,
              activeTrackColor: Brand.royal,
              inactiveTrackColor: dark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFEDE7FF),
              thumbColor: Colors.white,
              thumbShape: const _RingThumb(),
              overlayColor: Brand.royal.withValues(alpha: 0.12),
              trackShape: const RoundedRectSliderTrackShape(),
              tickMarkShape: SliderTickMarkShape.noTickMark,
              valueIndicatorColor: Brand.royal,
            ),
            child: Slider(
              max: MissMeter.max.toDouble(),
              divisions: MissMeter.max,
              value: value,
              label: '$v%',
              onChanged: onChanged,
            ),
          ),
          const SizedBox(height: 12),
          PillButton(label: 'Lock in my answer', icon: Icons.lock_outline_rounded, loading: busy, onPressed: onSubmit),
        ],
      ),
    );
  }
}

/// White slider thumb with a violet ring (Figma).
class _RingThumb extends SliderComponentShape {
  const _RingThumb();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(22, 22);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    context.canvas
      ..drawCircle(
        center + const Offset(0, 2),
        11,
        Paint()
          ..color = const Color(0x336A3DF0)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      )
      ..drawCircle(center, 11, Paint()..color = Colors.white)
      ..drawCircle(
        center,
        9,
        Paint()
          ..color = Brand.royal
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.value, required this.name});

  final int value;
  final String name;

  @override
  Widget build(BuildContext context) {
    return _MeterCard(
      child: Column(
        children: [
          _Gauge(
            fraction: value / MissMeter.max,
            color: _meterPink,
            child: Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: SoftTone.pink.fill(context), shape: BoxShape.circle),
              child: const Text(
                '⏳',
                style: TextStyle(fontSize: 32),
              ).animate(onPlay: (c) => c.repeat(reverse: true)).rotate(begin: -0.04, end: 0.04, duration: 900.ms),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Locked in: $value% ${_emojiFor(value)}',
            textAlign: TextAlign.center,
            style: context.tt.headlineSmall?.copyWith(fontSize: 22),
          ),
          const SizedBox(height: 6),
          Text(
            'Waiting for $name to answer. You’ll both see the results at the same time.',
            textAlign: TextAlign.center,
            style: context.tt.bodySmall?.copyWith(color: context.cc.muted, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Two gauges filling up side by side, numbers counting, then the verdict.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.meter, required this.me, required this.name});

  final MissMeter meter;
  final String me;
  final String name;

  @override
  Widget build(BuildContext context) {
    final mine = meter.values[me] ?? meter.myValue ?? 0;
    final theirs = meter.values.entries.where((e) => e.key != me).map((e) => e.value).firstOrNull ?? 0;
    final diff = (mine - theirs).abs();
    final verdict = diff <= 5
        ? 'Perfectly in sync 💞 You miss each other just the same.'
        : mine > theirs
        ? 'You win this round — you miss $name more 🥺'
        : '$name misses you more today 🥹';

    return _MeterCard(
      child: Column(
        children: [
          Text('The results are in!', style: context.tt.headlineSmall?.copyWith(fontSize: 22)),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: _ResultGauge(label: 'You', value: mine, color: _meterPink, dashed: false),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ResultGauge(label: name, value: theirs, color: Brand.royal, dashed: true),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
                verdict,
                textAlign: TextAlign.center,
                style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.35),
              )
              .animate(delay: 1600.ms)
              .fadeIn(duration: 400.ms)
              .scale(begin: const Offset(0.9, 0.9), curve: Curves.easeOutBack),
          const SizedBox(height: 6),
          Text(
            'Come back tomorrow for a new round',
            style: context.tt.bodySmall?.copyWith(color: context.cc.muted, fontWeight: FontWeight.w600),
          ).animate(delay: 1900.ms).fadeIn(),
        ],
      ),
    );
  }
}

/// One person's result: gauge with the emoji inside, big % and name.
class _ResultGauge extends StatelessWidget {
  const _ResultGauge({required this.label, required this.value, required this.color, required this.dashed});

  final String label;
  final int value;
  final Color color;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value / MissMeter.max),
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        final shown = (t * MissMeter.max).round();
        return Column(
          children: [
            _Gauge(
              fraction: t,
              color: color,
              width: 118,
              dashed: dashed,
              child: Text(_emojiFor(shown), style: const TextStyle(fontSize: 30)),
            ),
            const SizedBox(height: 6),
            Text(
              '$shown%',
              style: context.tt.headlineMedium?.copyWith(color: color, fontWeight: FontWeight.w700, fontSize: 30),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.tt.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        );
      },
    );
  }
}

/// Lavender row: date, then white "You 89% 🚀" / "Sam 92% 🚀" pills.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.meter, required this.me, required this.name});

  final MissMeter meter;
  final String me;
  final String name;

  @override
  Widget build(BuildContext context) {
    final mine = meter.values[me] ?? 0;
    final theirs = meter.values.entries.where((e) => e.key != me).map((e) => e.value).firstOrNull ?? 0;
    final date = DateTime.tryParse(meter.date);
    final dark = Theme.of(context).brightness == Brightness.dark;

    Widget pill(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: 0.12) : Colors.white,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: context.tt.labelSmall?.copyWith(fontWeight: FontWeight.w800)),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
        decoration: BoxDecoration(color: SoftTone.violet.fill(context), borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            Expanded(
              child: Text(
                date == null ? meter.date : DateFormat('EEE d MMM').format(date),
                style: context.tt.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            pill('You $mine% ${_emojiFor(mine)}'),
            const SizedBox(width: 6),
            Flexible(child: pill('$name $theirs% ${_emojiFor(theirs)}')),
          ],
        ),
      ),
    );
  }
}
