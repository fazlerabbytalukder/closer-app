import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// "How much do you miss me?" — both pick privately, then a joint reveal
/// with two bars racing up at the same time.
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
      appBar: AppBar(title: const Text('Miss-o-meter')),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
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
            const SectionHeader('Past days'),
            for (final m in history) _HistoryRow(meter: m, me: me, name: name),
          ],
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
    return CloserCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF1EDFF), Color(0xFFFFE6EF)],
      ),
      padding: const EdgeInsets.all(Space.l),
      child: Column(
        children: [
          Text('How much do you miss $name today?', textAlign: TextAlign.center, style: context.tt.titleLarge?.copyWith(color: Brand.ink)),
          const SizedBox(height: Space.xs),
          Text(
            partnerAnswered ? '$name already answered 👀 Your turn!' : 'Your answer stays secret until $name answers too',
            textAlign: TextAlign.center,
            style: context.tt.bodyMedium?.copyWith(color: Brand.grey700),
          ),
          const SizedBox(height: Space.l),
          AnimatedSwitcher(
            duration: 200.ms,
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Text(_emojiFor(v), key: ValueKey(_emojiFor(v)), style: const TextStyle(fontSize: 72)),
          ),
          Text('$v%', style: context.tt.displaySmall?.copyWith(fontWeight: FontWeight.w700, color: Brand.pink)),
          Text(MissMeter.describe(v), style: context.tt.titleMedium?.copyWith(color: Brand.ink)),
          const SizedBox(height: Space.m),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 10,
              activeTrackColor: Brand.pink,
              inactiveTrackColor: Colors.white,
              thumbColor: Brand.pink,
              overlayColor: Brand.pink.withValues(alpha: 0.15),
            ),
            child: Slider(
              max: MissMeter.max.toDouble(),
              divisions: MissMeter.max,
              value: value,
              label: '$v%',
              onChanged: onChanged,
            ),
          ),
          const SizedBox(height: Space.m),
          CloserButton(
            label: 'Lock in my answer',
            icon: Icons.lock_rounded,
            kind: CloserButtonKind.accent,
            loading: busy,
            onPressed: onSubmit,
          ),
        ],
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.value, required this.name});

  final int value;
  final String name;

  @override
  Widget build(BuildContext context) {
    return CloserCard(
      padding: const EdgeInsets.all(Space.l),
      child: Column(
        children: [
          const Text('⏳', style: TextStyle(fontSize: 56))
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .rotate(begin: -0.04, end: 0.04, duration: 900.ms),
          const SizedBox(height: Space.s),
          Text('Locked in: $value% ${_emojiFor(value)}', style: context.tt.titleLarge),
          const SizedBox(height: Space.xs),
          Text(
            'Waiting for $name to answer. You’ll both see the results at the same time.',
            textAlign: TextAlign.center,
            style: context.tt.bodyMedium?.copyWith(color: context.cc.muted),
          ),
        ],
      ),
    );
  }
}

/// Two bars filling up side by side, numbers counting, then the verdict.
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

    return CloserCard(
      padding: const EdgeInsets.all(Space.l),
      child: Column(
        children: [
          Text('The results are in!', style: context.tt.titleLarge),
          const SizedBox(height: Space.l),
          SizedBox(
            height: 220,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Bar(label: 'You', value: mine, color: context.cc.accent),
                _Bar(label: name, value: theirs, color: Brand.pink),
              ],
            ),
          ),
          const SizedBox(height: Space.m),
          Text(verdict, textAlign: TextAlign.center, style: context.tt.titleMedium)
              .animate(delay: 1600.ms)
              .fadeIn(duration: 400.ms)
              .scale(begin: const Offset(0.9, 0.9), curve: Curves.easeOutBack),
          const SizedBox(height: Space.xs),
          Text('Come back tomorrow for a new round', style: context.tt.bodySmall?.copyWith(color: context.cc.muted))
              .animate(delay: 1900.ms)
              .fadeIn(),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value / MissMeter.max),
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        final shown = (t * MissMeter.max).round();
        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(_emojiFor(shown), style: const TextStyle(fontSize: 28)),
            Text('$shown%', style: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Container(
              width: 64,
              height: 8 + 130 * t,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [color, Color.lerp(color, Colors.white, 0.4)!],
                ),
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 6))],
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 90,
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: context.tt.labelLarge),
            ),
          ],
        );
      },
    );
  }
}

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
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: CloserCard(
        padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s + 4),
        child: Row(
          children: [
            Expanded(
              child: Text(date == null ? meter.date : DateFormat('EEE d MMM').format(date), style: context.tt.titleSmall),
            ),
            Text('You $mine% ${_emojiFor(mine)}', style: context.tt.bodyMedium),
            const SizedBox(width: Space.m),
            Text('$name $theirs% ${_emojiFor(theirs)}', style: context.tt.bodyMedium?.copyWith(color: context.cc.muted)),
          ],
        ),
      ),
    );
  }
}
