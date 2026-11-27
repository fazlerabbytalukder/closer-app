import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/soft_ui.dart';
import 'package:closer_app/core/ui/voice.dart';
import 'package:closer_app/features/love/love_widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// Night sky (Figma "goodnight screen"): deep navy, a touch lighter at the top.
const _night = [Color(0xFF221F4A), Color(0xFF17153A), Color(0xFF12102E)];
const _ink = Color(0xFFF4F1FF);
const _soft = Color(0xB3F4F1FF);

/// Gold of the moon and the twinkling stars.
const _gold = Color(0xFFFFC94D);

/// Hot pink of the "Say goodnight" button and the kiss.
const _hotPink = Color(0xFFFF5C9E);

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
    final history = (ref.watch(goodnightsProvider).value ?? const <Goodnight>[])
        .where((g) => g.night != tonight?.night)
        .take(7)
        .toList();
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final mine = me == null ? null : tonight?.entries[me];
    final theirs = partnerUid == null ? null : tonight?.entries[partnerUid];
    final complete = mine != null && theirs != null;
    final top = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: _night.last,
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: _night),
              ),
            ),
          ),
          const Positioned.fill(child: _Stars()),
          Column(
            children: [
              // Header: frosted round back button and white title.
              Padding(
                padding: EdgeInsets.fromLTRB(20, top + 12, 20, 4),
                child: Row(
                  children: [
                    HeaderIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 12),
                    Text('Goodnight', style: context.tt.headlineSmall?.copyWith(color: _ink, fontSize: 22)),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                  children: [
                    // Moon and mascot, then the centred title.
                    const _NightHero(),
                    const SizedBox(height: 10),
                    Text(
                      complete ? 'Sweet dreams, you two 💫' : 'Time to say goodnight',
                      textAlign: TextAlign.center,
                      style: context.tt.headlineSmall?.copyWith(color: _ink, fontSize: 25),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        complete
                            ? 'You both said goodnight tonight.'
                            : Goodnight.isEvening(now)
                            ? 'Share the best part of your day with $name.'
                            : 'The ritual is for the evening, but you can say goodnight early.',
                        textAlign: TextAlign.center,
                        style: context.tt.bodySmall?.copyWith(color: _soft, fontWeight: FontWeight.w600, height: 1.45),
                      ),
                    ),
                    const SizedBox(height: 22),
                    if (mine == null) const _GoodnightForm() else _EntryCard(title: 'You', entry: mine),
                    const SizedBox(height: 22),
                    if (theirs != null)
                      _EntryCard(title: name, entry: theirs)
                    else
                      _GlassCard(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: const Icon(Icons.nightlight_outlined, size: 18, color: _ink),
                                )
                                .animate(onPlay: (c) => c.repeat(reverse: true))
                                .fade(begin: 0.6, end: 1, duration: 1200.ms),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                mine == null ? '$name hasn’t said goodnight yet' : 'Waiting for $name’s goodnight…',
                                style: context.tt.labelLarge?.copyWith(color: _ink, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (complete) const _KissRain(),
                    if (history.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Past nights',
                        style: context.tt.titleMedium?.copyWith(color: _ink, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      for (final g in history) _PastNight(night: g, me: me, partnerUid: partnerUid, name: name),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Gold crescent moon beside the white mascot, both floating gently.
class _NightHero extends StatelessWidget {
  const _NightHero();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 116,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Transform.rotate(angle: -0.5, child: const Icon(Icons.nightlight_round, size: 46, color: _gold)),
              )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(begin: 0, end: -5, duration: 2.seconds, curve: Curves.easeInOut),
          const SizedBox(width: 2),
          Image.asset('assets/together/streak_mascot.png', width: 96, height: 106)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(begin: 0, end: -4, duration: 2400.ms, curve: Curves.easeInOut),
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
          for (var i = 0; i < 24; i++)
            Align(
              alignment: Alignment(r.nextDouble() * 2 - 1, r.nextDouble() * 2 - 1),
              child:
                  Text(
                        i.isEven ? '✦' : '·',
                        style: TextStyle(color: i % 3 == 0 ? _gold : Colors.white, fontSize: 5 + r.nextDouble() * 8),
                      )
                      .animate(onPlay: (c) => c.repeat(reverse: true), delay: r.nextInt(2000).ms)
                      .fade(begin: 0.15, end: 0.9, duration: (1200 + r.nextInt(1600)).ms),
            ),
        ],
      ),
    );
  }
}

/// See-through night card with a hairline border.
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: child,
    );
  }
}

InputDecoration _nightInput(String hint) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0x99F4F1FF), fontWeight: FontWeight.w600),
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.07),
    counterStyle: const TextStyle(color: _soft, fontWeight: FontWeight.w600),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(borderSide: const BorderSide(color: Color(0xFFB9A6FF), width: 1.4)),
  );
}

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
      () => ref
          .read(backendProvider)
          .sendGoodnight(
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
    final label = context.tt.labelLarge?.copyWith(color: _ink, fontWeight: FontWeight.w800);
    final showPhotoButton = _photo == null;
    final showVoiceButton = !_recording && _voice == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Your goodnight', style: label),
        const SizedBox(height: 8),
        TextField(
          controller: _message,
          style: const TextStyle(color: _ink, fontWeight: FontWeight.w600),
          cursorColor: _ink,
          maxLength: GoodnightEntry.maxText,
          minLines: 1,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: _nightInput('Goodnight message for $name'),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 10,
          children: [
            for (final p in _presets)
              Material(
                color: Colors.white.withValues(alpha: 0.08),
                shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.16))),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => setState(() => _message.text = p),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      p,
                      style: context.tt.labelMedium?.copyWith(color: _ink, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 26),
        Text('Best moment of my day', style: label),
        const SizedBox(height: 8),
        TextField(
          controller: _moment,
          style: const TextStyle(color: _ink, fontWeight: FontWeight.w600),
          cursorColor: _ink,
          maxLength: GoodnightEntry.maxText,
          minLines: 1,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: _nightInput('Something that made you smile today'),
        ),
        if (_photo != null) ...[
          const SizedBox(height: 4),
          PhotoField(path: _photo, onChanged: (p) => setState(() => _photo = p)),
          const SizedBox(height: 12),
        ],
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
              Expanded(
                child: VoicePlayer(mediaPath: _voice!.path, durationMs: _voice!.durationMs, onDark: true),
              ),
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
          ),
        // "Add a photo of it" and "Voice note" side by side.
        if (showPhotoButton || showVoiceButton) ...[
          const SizedBox(height: 8),
          if (_recording || _voice != null) const SizedBox(height: 10),
          Row(
            children: [
              if (showPhotoButton)
                Expanded(
                  child: PhotoField(
                    path: null,
                    onChanged: (p) => setState(() => _photo = p),
                    label: 'Add a photo of it',
                    onDark: true,
                  ),
                ),
              if (showPhotoButton && showVoiceButton) const SizedBox(width: 10),
              if (showVoiceButton)
                Expanded(
                  child: NightPill(icon: Icons.mic_none_rounded, label: 'Voice note', onTap: _record),
                ),
            ],
          ),
        ],
        const SizedBox(height: 26),
        // Pink "Add a goodnight kiss" pill; brighter once it's included.
        Center(
          child: GestureDetector(
            onTap: () {
              hapticMedium();
              setState(() => _kiss = !_kiss);
            },
            child: AnimatedContainer(
              duration: 300.ms,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: _kiss ? _hotPink.withValues(alpha: 0.45) : _hotPink.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _kiss ? _hotPink : Colors.transparent),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedScale(
                    scale: _kiss ? 1.25 : 1,
                    duration: 300.ms,
                    curve: Curves.easeOutBack,
                    child: const Icon(Icons.favorite_rounded, size: 17, color: Color(0xFFFF8CBB)),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    _kiss ? 'Kiss included 💋' : 'Add a goodnight kiss',
                    style: context.tt.labelLarge?.copyWith(color: const Color(0xFFFFC2DB), fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        PillButton(
          label: 'Say goodnight',
          icon: Icons.nightlight_outlined,
          color: _hotPink,
          height: 52,
          loading: _busy,
          onPressed: _recording ? null : _send,
        ),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.title, required this.entry});

  final String title;
  final GoodnightEntry entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: context.tt.titleMedium?.copyWith(color: _ink, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              if (e.sentAt != null)
                Text(
                  DateFormat('HH:mm').format(e.sentAt!),
                  style: context.tt.labelSmall?.copyWith(color: _soft, fontWeight: FontWeight.w700),
                ),
              if (e.kiss) ...[
                const SizedBox(width: 6),
                const Text(
                  '💋',
                  style: TextStyle(fontSize: 20),
                ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 1, end: 1.2, duration: 700.ms),
              ],
            ],
          ),
          if (e.message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '“${e.message}”',
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _ink,
                height: 1.4,
              ),
            ),
          ],
          if (e.moment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '✨ Best moment',
              style: context.tt.labelMedium?.copyWith(color: _gold, fontWeight: FontWeight.w800),
            ),
            Text(
              e.moment,
              style: context.tt.bodyMedium?.copyWith(color: _ink, fontWeight: FontWeight.w600),
            ),
          ],
          if (e.momentPhotoPath != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(aspectRatio: 4 / 3, child: StoredImage(e.momentPhotoPath)),
            ),
          ],
          if (e.voicePath != null) ...[
            const SizedBox(height: 10),
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
    String line(String who, GoodnightEntry? e) => e == null
        ? '$who: –'
        : '$who: ${e.moment.isNotEmpty ? e.moment : (e.message.isNotEmpty ? e.message : (e.kiss ? '💋' : '🎤'))}';
    final small = context.tt.bodySmall?.copyWith(color: _soft, fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _GlassCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${date == null ? night.night : DateFormat('EEEE d MMMM').format(date)}${mine != null && theirs != null ? '  🌙' : ''}',
              style: context.tt.labelLarge?.copyWith(color: _ink, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(line('You', mine), maxLines: 2, overflow: TextOverflow.ellipsis, style: small),
            Text(line(name, theirs), maxLines: 2, overflow: TextOverflow.ellipsis, style: small),
          ],
        ),
      ),
    );
  }
}
