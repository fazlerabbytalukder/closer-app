import 'dart:async';
import 'dart:io';

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/data/closer_backend.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/screen_guard.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;

/// Downloads a chat photo (storage ref or local path) into memory.
Future<Uint8List> loadChatMedia(CloserBackend backend, String? path) async {
  final url = path == null ? null : await backend.resolveImage(path);
  if (url == null) throw const CloserException('This photo is gone');
  if (url.startsWith('http')) {
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) throw const CloserException('Couldn’t load the photo. Check your connection.');
    return res.bodyBytes;
  }
  final file = File(url.startsWith('file://') ? Uri.parse(url).toFilePath() : url);
  if (!file.existsSync()) throw const CloserException('This photo is gone');
  return await file.readAsBytes();
}

/// Saves a chat photo to the phone's gallery.
Future<void> savePhotoToPhone(CloserBackend backend, String? path) async {
  if (!await Gal.hasPermission() && !await Gal.requestPermission()) {
    throw const CloserException('Allow photo access to save it');
  }
  final bytes = await loadChatMedia(backend, path);
  try {
    await Gal.putImageBytes(bytes, album: 'Closer', name: 'closer_${DateTime.now().millisecondsSinceEpoch}');
  } on GalException catch (e) {
    throw CloserException('Couldn’t save the photo (${e.type.name})');
  }
}

/// Asks how many times the snap may be opened; null = cancelled.
Future<int?> showSnapSendSheet(BuildContext context, String localPath, String name) {
  var views = 1;
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.m),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('👻 Send a snap', style: ctx.tt.titleLarge),
              const SizedBox(height: 4),
              Text(
                '$name can open it ${views == 1 ? 'once' : 'twice'} for ${ChatMessage.snapSeconds} seconds. '
                'They can’t save it, and you’ll know if they screenshot it.',
                textAlign: TextAlign.center,
                style: ctx.tt.bodySmall?.copyWith(color: ctx.cc.muted),
              ),
              const SizedBox(height: Space.m),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.42),
                  child: Image.file(File(localPath), fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: Space.m),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('Opens once'), icon: Icon(Icons.looks_one_rounded)),
                  ButtonSegment(value: 2, label: Text('Opens twice'), icon: Icon(Icons.looks_two_rounded)),
                ],
                selected: {views},
                onSelectionChanged: (s) => setSheet(() => views = s.first),
              ),
              const SizedBox(height: Space.m),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Send snap'),
                  onPressed: () => Navigator.pop(ctx, views),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Full-screen, timed view of a snap. Counts the opening first, blocks
/// screenshots (Android), and closes itself after [ChatMessage.snapSeconds].
class SnapViewer extends ConsumerStatefulWidget {
  const SnapViewer({required this.message, required this.name, super.key});

  final ChatMessage message;
  final String name;

  /// The snap on screen now, so a screenshot notice can name it.
  static ChatMessage? showing;

  static Future<void> open(BuildContext context, ChatMessage message, String name) => Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => SnapViewer(message: message, name: name),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ),
  );

  @override
  ConsumerState<SnapViewer> createState() => _SnapViewerState();
}

class _SnapViewerState extends ConsumerState<SnapViewer> with SingleTickerProviderStateMixin {
  late final AnimationController _timer = AnimationController(
    vsync: this,
    duration: const Duration(seconds: ChatMessage.snapSeconds),
  );
  Uint8List? _bytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    SnapViewer.showing = widget.message;
    unawaited(ScreenGuard.secure());
    unawaited(_load());
  }

  Future<void> _load() async {
    final backend = ref.read(backendProvider);
    try {
      // Fetch first: the last opening deletes the photo.
      final bytes = await loadChatMedia(backend, widget.message.mediaPath);
      await backend.openSnap(widget.message.id);
      if (!mounted) return;
      setState(() => _bytes = bytes);
      await _timer.forward();
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      debugPrint('Snap open failed: $e');
      if (mounted) setState(() => _error = e is CloserException ? e.message : 'Couldn’t open this snap. Try again.');
    }
  }

  @override
  void dispose() {
    if (SnapViewer.showing?.id == widget.message.id) SnapViewer.showing = null;
    unawaited(ScreenGuard.release());
    _timer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (bytes != null)
              Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true)
            else
              Center(
                child: _error == null
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Padding(
                        padding: const EdgeInsets.all(Space.l),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
              ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedBuilder(
                      animation: _timer,
                      builder: (_, _) => ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: 1 - _timer.value,
                          minHeight: 3,
                          color: Colors.white,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ),
                    const SizedBox(height: Space.s),
                    Text(
                      '👻 Snap from ${widget.name}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 6)]),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
