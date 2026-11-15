import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// A finished recording.
typedef VoiceClip = ({String path, int durationMs});

/// Records voice notes to an .m4a file (AAC), with a live level meter.
class VoiceRecorder {
  final _rec = AudioRecorder();
  final _levels = StreamController<double>.broadcast();
  StreamSubscription<Amplitude>? _ampSub;
  DateTime? _startedAt;

  /// 0..1 loudness, about 10 times a second while recording.
  Stream<double> get levels => _levels.stream;

  bool get isRecording => _startedAt != null;

  Duration get elapsed => _startedAt == null ? Duration.zero : DateTime.now().difference(_startedAt!);

  /// Returns false when the microphone permission is refused.
  Future<bool> start() async {
    if (!await _rec.hasPermission()) return false;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _rec.start(const RecordConfig(numChannels: 1, bitRate: 64000), path: path);
    _startedAt = DateTime.now();
    _ampSub = _rec.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((a) {
      // dBFS: about -45 is quiet, 0 is loud.
      _levels.add(((a.current + 45) / 45).clamp(0.0, 1.0));
    });
    return true;
  }

  Future<VoiceClip?> stop() async {
    final started = _startedAt;
    _startedAt = null;
    await _ampSub?.cancel();
    final path = await _rec.stop();
    if (path == null || started == null) return null;
    return (path: path, durationMs: DateTime.now().difference(started).inMilliseconds);
  }

  Future<void> cancel() async {
    _startedAt = null;
    await _ampSub?.cancel();
    await _rec.cancel();
  }

  Future<void> dispose() async {
    await _ampSub?.cancel();
    await _levels.close();
    await _rec.dispose();
  }
}

String formatDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// The bar shown while recording: pulsing dot, timer, live levels, and
/// cancel / send.
class RecordingBar extends StatefulWidget {
  const RecordingBar({required this.recorder, required this.onCancel, required this.onDone, super.key, this.maxDuration = const Duration(minutes: 5)});

  final VoiceRecorder recorder;
  final VoidCallback onCancel;
  final VoidCallback onDone;
  final Duration maxDuration;

  @override
  State<RecordingBar> createState() => _RecordingBarState();
}

class _RecordingBarState extends State<RecordingBar> {
  final _bars = List<double>.filled(28, 0.05, growable: true);
  StreamSubscription<double>? _sub;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _sub = widget.recorder.levels.listen((v) {
      if (!mounted) return;
      setState(() {
        _bars
          ..removeAt(0)
          ..add(math.max(0.05, v));
      });
    });
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      if (widget.recorder.isRecording && widget.recorder.elapsed >= widget.maxDuration) widget.onDone();
      setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(tooltip: 'Cancel recording', icon: const Icon(Icons.delete_outline_rounded), onPressed: widget.onCancel),
        Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle))
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .fade(begin: 1, end: 0.2, duration: 600.ms),
        const SizedBox(width: 8),
        Text(formatDuration(widget.recorder.elapsed), style: context.tt.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 32,
            child: Row(
              children: [
                for (final b in _bars)
                  Expanded(
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        width: 3,
                        height: 4 + 28 * b,
                        decoration: BoxDecoration(color: context.cc.accent, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(tooltip: 'Send voice message', icon: const Icon(Icons.send_rounded), onPressed: widget.onDone),
      ],
    );
  }
}

/// Plays a voice note (storage ref or local file). Starting one stops any
/// other that's playing.
class VoicePlayer extends ConsumerStatefulWidget {
  const VoicePlayer({required this.mediaPath, required this.durationMs, super.key, this.color, this.onDark = false, this.seed = 0});

  final String? mediaPath;
  final int durationMs;
  final Color? color;

  /// Light controls for coloured bubbles.
  final bool onDark;

  /// Varies the decorative waveform per message.
  final int seed;

  @override
  ConsumerState<VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends ConsumerState<VoicePlayer> {
  static _VoicePlayerState? _current;

  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  Duration _pos = Duration.zero;
  bool _playing = false;
  bool _loading = false;

  late final List<double> _wave = () {
    final r = math.Random(widget.seed);
    return List.generate(32, (i) => 0.25 + r.nextDouble() * 0.75);
  }();

  @override
  void dispose() {
    if (_current == this) _current = null;
    unawaited(_stateSub?.cancel());
    unawaited(_posSub?.cancel());
    unawaited(_player?.dispose());
    super.dispose();
  }

  Future<void> _stop() async {
    await _player?.pause();
    if (mounted) setState(() => _playing = false);
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _stop();
      return;
    }
    if (_current != null && _current != this) await _current!._stop();
    _current = this;
    try {
      var player = _player;
      if (player == null) {
        setState(() => _loading = true);
        final src = await ref.read(backendProvider).resolveImage(widget.mediaPath);
        if (src == null) throw const FileSystemException('missing');
        final created = AudioPlayer();
        player = created;
        _player = created;
        if (src.startsWith('http')) {
          await created.setUrl(src);
        } else {
          await created.setFilePath(src);
        }
        _posSub = created.positionStream.listen((p) {
          if (mounted) setState(() => _pos = p);
        });
        _stateSub = created.playerStateStream.listen((s) async {
          if (s.processingState == ProcessingState.completed) {
            await created.pause();
            await created.seek(Duration.zero);
            if (mounted) setState(() => _playing = false);
          }
        });
      }
      setState(() {
        _loading = false;
        _playing = true;
      });
      await player.play();
    } on Object catch (e) {
      debugPrint('Voice playback failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _playing = false;
        });
        showToast(context, 'Couldn’t play that voice message', icon: Icons.volume_off_rounded);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = Duration(milliseconds: widget.durationMs);
    final progress = total.inMilliseconds == 0 ? 0.0 : (_pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final fg = widget.onDark ? Colors.white : (widget.color ?? context.cc.accent);
    final dim = fg.withValues(alpha: 0.35);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: _loading
              ? Padding(padding: const EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2, color: fg))
              : IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: _playing ? 'Pause' : 'Play voice message',
                  icon: Icon(_playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: fg, size: 36),
                  onPressed: widget.mediaPath == null ? null : _toggle,
                ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 130,
          height: 28,
          child: Row(
            children: [
              for (var i = 0; i < _wave.length; i++)
                Expanded(
                  child: Center(
                    child: Container(
                      width: 2.5,
                      height: 4 + 22 * _wave[i],
                      decoration: BoxDecoration(
                        color: i / _wave.length <= progress ? fg : dim,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          formatDuration(_playing || _pos > Duration.zero ? total - _pos : total),
          style: context.tt.labelSmall?.copyWith(color: fg, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    );
  }
}
