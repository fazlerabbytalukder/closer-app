import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/voice.dart';
import 'package:closer_app/features/love/love_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

const _night = [Color(0xFF141838), Color(0xFF2D2760), Color(0xFF5A3F84)];
const _ink = Color(0xFFF4F1FF);
const _soft = Color(0xB3F4F1FF);

/// Goodnight ritual (F10): each night you both send a goodnight message,
/// the best moment of your day, an optional voice note and a kiss.
class GoodnightScreen extends ConsumerWidget {
  const GoodnightScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authUidProvider).value;
    final partnerUid = ref.watch(partnerUidProvider);
    final name = ref.watch(partnerNameProvider);
    final tonight = ref.watch(tonightProvider);
    final history = (ref.watch(goodnightsProvider).value ?? const <Goodnight>[]).where((g) => g.night != tonight?.night).take(7).toList();
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final mine = me == null ? null : tonight?.entries[me];
    final theirs = partnerUid == null ? null : tonight?.entries[partnerUid];
    final complete = mine != null && theirs != null;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: _night.first,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: _ink,
        // The theme's title style would draw dark text on the night sky.
        titleTextStyle: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(color: _ink) ??
            Theme.of(context).textTheme.titleLarge?.copyWith(color: _ink),
        title: const Text('Goodnight'),
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: _night)),
            ),
          ),
          const Positioned.fill(child: _Stars()),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            complete ? 'Sweet dreams, you two 💫' : 'Time to say goodnight',
                            style: context.tt.headlineSmall?.copyWith(color: _ink, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            complete
                                ? 'You both said goodnight tonight.'
                                : Goodnight.isEvening(now)
                                    ? 'Share the best part of your day with $name.'
                                    : 'The ritual is for the evening, but you can say goodnight early.',
                            style: context.tt.bodyMedium?.copyWith(color: _soft),
                          ),
                        ],
                      ),
                    ),
                    const Text('🌙', style: TextStyle(fontSize: 56))
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .moveY(begin: 0, end: -6, duration: 2.seconds, curve: Curves.easeInOut)
                        .rotate(begin: -0.02, end: 0.02, duration: 2.seconds),
                  ],
                ),
                const SizedBox(height: Space.l),
                if (mine == null) const _GoodnightForm() else _EntryCard(title: 'You', entry: mine, mine: true),
                const SizedBox(height: Space.m),
                if (theirs != null)
                  _EntryCard(title: name, entry: theirs, mine: false)
                else
                  _GlassCard(
                    child: Row(
                      children: [
                        const Text('💤', style: TextStyle(fontSize: 28))
                            .animate(onPlay: (c) => c.repeat(reverse: true))
                            .fade(begin: 0.5, end: 1, duration: 1200.ms),
                        const SizedBox(width: Space.m),
                        Expanded(
                          child: Text(
                            mine == null ? '$name hasn’t said goodnight yet' : 'Waiting for $name’s goodnight…',
                            style: context.tt.titleSmall?.copyWith(color: _ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (complete) const _KissRain(),
                if (history.isNotEmpty) ...[
                  const SizedBox(height: Space.l),
                  Text('Past nights', style: context.tt.titleMedium?.copyWith(color: _ink)),
                  const SizedBox(height: Space.s),
                  for (final g in history) _PastNight(night: g, me: me, partnerUid: partnerUid, name: name),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars();

  @override
  Widget build(BuildContext context) {
    final r = math.Random(7);
    return IgnorePointer(
      child: Stack(
        children: [
          for (var i = 0; i < 28; i++)
            Align(
              alignment: Alignment(r.nextDouble() * 2 - 1, r.nextDouble() * 2 - 1),
              child: Text(i.isEven ? '✦' : '·', style: TextStyle(color: Colors.white, fontSize: 6 + r.nextDouble() * 10))
                  .animate(onPlay: (c) => c.repeat(reverse: true), delay: r.nextInt(2000).ms)
                  .fade(begin: 0.15, end: 0.9, duration: (1200 + r.nextInt(1600)).ms),
            ),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: child,
    );
  }
}

InputDecoration _nightInput(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0x80F4F1FF)),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      counterStyle: const TextStyle(color: _soft),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
    );

class _GoodnightForm extends ConsumerStatefulWidget {
  const _GoodnightForm();

  @override
  ConsumerState<_GoodnightForm> createState() => _GoodnightFormState();
}

class _GoodnightFormState extends ConsumerState<_GoodnightForm> {
  final _message = TextEditingController();
  final _moment = TextEditingController();
  final _recorder = VoiceRecorder();
  String? _photo;
  VoiceClip? _voice;
  bool _recording = false;
  bool _kiss = false;
  bool _busy = false;

  static const _presets = ['Sweet dreams 💤', 'Goodnight, love you 🌙', 'Can’t wait for tomorrow ✨', 'Sleep tight 🧸'];

  @override
  void dispose() {
    _message.dispose();
    _moment.dispose();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _record() async {
    try {
      if (!await _recorder.start()) {
        if (mounted) showToast(context, 'Allow the microphone to record a voice note', icon: Icons.mic_off_rounded);
        return;
      }
      if (mounted) setState(() => _recording = true);
    } on Object {
      if (mounted) showToast(context, 'Couldn’t start recording', icon: Icons.mic_off_rounded);
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    final clip = await _recorder.stop();
    if (!mounted) return;
    setState(() {
      _recording = false;
      if (clip != null && clip.durationMs >= 700) _voice = clip;
    });
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => ref.read(backendProvider).sendGoodnight(
            GoodnightEntry(
              message: _message.text,
              moment: _moment.text,
              momentPhotoPath: _photo,
              voicePath: _voice?.path,
              voiceMs: _voice?.durationMs ?? 0,
              kiss: _kiss,
            ),
          ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      hapticMedium();
      showToast(context, 'Goodnight sent 🌙');
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(partnerNameProvider);
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Your goodnight', style: context.tt.titleMedium?.copyWith(color: _ink)),
          const SizedBox(height: Space.s),
          TextField(
            controller: _message,
            style: const TextStyle(color: _ink),
            maxLength: GoodnightEntry.maxText,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: _nightInput('Goodnight message for $name'),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in _presets)
                ActionChip(
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  side: BorderSide.none,
                  label: Text(p, style: const TextStyle(color: _ink)),
                  onPressed: () => setState(() => _message.text = p),
                ),
            ],
          ),
          const SizedBox(height: Space.m),
          Text('Best moment of my day', style: context.tt.titleSmall?.copyWith(color: _ink)),
          const SizedBox(height: Space.xs),
          TextField(
            controller: _moment,
            style: const TextStyle(color: _ink),
            maxLength: GoodnightEntry.maxText,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: _nightInput('Something that made you smile today'),
          ),
          PhotoField(path: _photo, onChanged: (p) => setState(() => _photo = p), label: 'Add a photo of it'),
          const SizedBox(height: Space.m),
          if (_recording)
            Theme(
              data: Theme.of(context).copyWith(textTheme: Theme.of(context).textTheme.apply(bodyColor: _ink)),
              child: RecordingBar(
                recorder: _recorder,
                onCancel: () async {
                  await _recorder.cancel();
                  if (mounted) setState(() => _recording = false);
                },
                onDone: _stopRecording,
              ),
            )
          else if (_voice != null)
            Row(
              children: [
                Expanded(child: VoicePlayer(mediaPath: _voice!.path, durationMs: _voice!.durationMs, onDark: true)),
                IconButton(
                  tooltip: 'Remove voice note',
                  icon: const Icon(Icons.delete_outline_rounded, color: _soft),
                  onPressed: () {
                    final f = File(_voice!.path);
                    setState(() => _voice = null);
                    f.delete().ignore();
                  },
                ),
              ],
            )
          else
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: _ink, side: const BorderSide(color: Color(0x55F4F1FF))),
              onPressed: _record,
              icon: const Icon(Icons.mic_rounded),
              label: const Text('Record a voice note'),
            ),
          const SizedBox(height: Space.m),
          Center(
            child: GestureDetector(
              onTap: () {
                hapticMedium();
                setState(() => _kiss = !_kiss);
              },
              child: AnimatedContainer(
                duration: 300.ms,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: _kiss ? Brand.pink.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _kiss ? Brand.pink : const Color(0x33FFFFFF)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedScale(scale: _kiss ? 1.3 : 1, duration: 300.ms, curve: Curves.easeOutBack, child: const Text('💋', style: TextStyle(fontSize: 24))),
                    const SizedBox(width: 8),
                    Text(_kiss ? 'Kiss included' : 'Add a goodnight kiss', style: context.tt.labelLarge?.copyWith(color: _ink)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.m),
          CloserButton(label: 'Say goodnight', icon: Icons.nightlight_round, kind: CloserButtonKind.accent, loading: _busy, onPressed: _recording ? null : _send),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.title, required this.entry, required this.mine});

  final String title;
  final GoodnightEntry entry;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: context.tt.titleMedium?.copyWith(color: _ink)),
              const Spacer(),
              if (e.sentAt != null) Text(DateFormat('HH:mm').format(e.sentAt!), style: context.tt.labelSmall?.copyWith(color: _soft)),
              if (e.kiss) ...[
                const SizedBox(width: 6),
                const Text('💋', style: TextStyle(fontSize: 20))
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scaleXY(begin: 1, end: 1.2, duration: 700.ms),
              ],
            ],
          ),
          if (e.message.isNotEmpty) ...[
            const SizedBox(height: Space.s),
            Text('“${e.message}”', style: const TextStyle(fontFamily: 'Nunito', fontSize: 18, fontStyle: FontStyle.italic, color: _ink, height: 1.4)),
          ],
          if (e.moment.isNotEmpty) ...[
            const SizedBox(height: Space.s),
            Text('✨ Best moment', style: context.tt.labelMedium?.copyWith(color: _soft)),
            Text(e.moment, style: context.tt.bodyLarge?.copyWith(color: _ink)),
          ],
          if (e.momentPhotoPath != null) ...[
            const SizedBox(height: Space.s),
            ClipRRect(borderRadius: BorderRadius.circular(Radii.small + 4), child: AspectRatio(aspectRatio: 4 / 3, child: StoredImage(e.momentPhotoPath))),
          ],
          if (e.voicePath != null) ...[
            const SizedBox(height: Space.s),
            VoicePlayer(mediaPath: e.voicePath, durationMs: e.voiceMs, onDark: true, seed: e.voicePath.hashCode),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).moveY(begin: 12, end: 0, curve: Curves.easeOutCubic);
  }
}

/// Kisses drifting up once you both said goodnight.
class _KissRain extends StatelessWidget {
  const _KissRain();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: Stack(
        children: [
          for (var i = 0; i < 7; i++)
            Align(
              alignment: Alignment(-0.9 + i * 0.3, 1),
              child: Text(i.isEven ? '💋' : '💗', style: const TextStyle(fontSize: 22))
                  .animate(onPlay: (c) => c.repeat(), delay: (i * 260).ms)
                  .moveY(begin: 0, end: -80, duration: 2400.ms, curve: Curves.easeOut)
                  .fadeOut(delay: 1200.ms, duration: 1200.ms),
            ),
        ],
      ),
    );
  }
}

class _PastNight extends StatelessWidget {
  const _PastNight({required this.night, required this.me, required this.partnerUid, required this.name});

  final Goodnight night;
  final String? me;
  final String? partnerUid;
  final String name;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(night.night);
    final mine = me == null ? null : night.entries[me];
    final theirs = partnerUid == null ? null : night.entries[partnerUid];
    String line(String who, GoodnightEntry? e) =>
        e == null ? '$who: –' : '$who: ${e.moment.isNotEmpty ? e.moment : (e.message.isNotEmpty ? e.message : (e.kiss ? '💋' : '🎤'))}';
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: _GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${date == null ? night.night : DateFormat('EEEE d MMMM').format(date)}${mine != null && theirs != null ? '  🌙' : ''}',
              style: context.tt.titleSmall?.copyWith(color: _ink),
            ),
            const SizedBox(height: 4),
            Text(line('You', mine), maxLines: 2, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall?.copyWith(color: _soft)),
            Text(line(name, theirs), maxLines: 2, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall?.copyWith(color: _soft)),
          ],
        ),
      ),
    );
  }
}
