import 'dart:io';
import 'dart:ui' as ui;

import 'package:closer_app/core/models/models.dart';
import 'package:flutter/material.dart';

/// Note card styles (plan F3: "coloured card, a few bundled fonts and
/// backgrounds").
class NoteBackground {
  const NoteBackground(this.id, this.colors, this.ink);

  final String id;
  final List<Color> colors;
  final Color ink;
}

const noteBackgrounds = <NoteBackground>[
  NoteBackground('blush', [Color(0xFFFFC2D1), Color(0xFFFF8FA6)], Color(0xFF4A1426)),
  NoteBackground('sky', [Color(0xFFBFDBFF), Color(0xFF6FA8FF)], Color(0xFF0F2D59)),
  NoteBackground('mint', [Color(0xFFC9F2D0), Color(0xFF7BD389)], Color(0xFF123D1B)),
  NoteBackground('lemon', [Color(0xFFFFF4B8), Color(0xFFFFD166)], Color(0xFF4A3A00)),
  NoteBackground('lavender', [Color(0xFFE2D9FF), Color(0xFFA996FF)], Color(0xFF2A1B66)),
  NoteBackground('night', [Color(0xFF2B3150), Color(0xFF141A2E)], Color(0xFFF7F3FF)),
];

const noteFonts = <String, String>{
  'rounded': 'Nunito',
  'serif': 'serif',
  'mono': 'monospace',
};

NoteBackground noteBackground(String id) =>
    noteBackgrounds.firstWhere((b) => b.id == id, orElse: () => noteBackgrounds.first);

/// Flutter widget version of a note card, used for previews and memories.
class NoteCard extends StatelessWidget {
  const NoteCard({required this.text, required this.style, super.key});

  final String text;
  final NoteStyle style;

  @override
  Widget build(BuildContext context) {
    final bg = noteBackground(style.bg);
    return AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: bg.colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              text.isEmpty ? 'Write something sweet…' : text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: noteFonts[style.font],
                fontSize: _fontSizeFor(text, 34),
                fontWeight: FontWeight.w800,
                height: 1.2,
                color: text.isEmpty ? bg.ink.withValues(alpha: 0.45) : bg.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

double _fontSizeFor(String text, double max) {
  final n = text.length;
  if (n < 20) return max;
  if (n < 50) return max * 0.8;
  if (n < 90) return max * 0.65;
  return max * 0.52;
}

/// Renders a note to a square PNG without needing a widget tree (used by the
/// simulated partner and as the upload for notes).
abstract final class NoteRenderer {
  static Future<File> renderToFile({
    required String text,
    required NoteStyle style,
    required String path,
    int size = 720,
  }) async {
    final bg = noteBackground(style.bg);
    final recorder = ui.PictureRecorder();
    final s = size.toDouble();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, s, s));
    final rect = Rect.fromLTWH(0, 0, s, s);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: bg.colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(rect),
    );
    // Soft decorative hearts.
    final deco = Paint()..color = Colors.white.withValues(alpha: 0.18);
    canvas
      ..drawCircle(Offset(s * 0.12, s * 0.14), s * 0.07, deco)
      ..drawCircle(Offset(s * 0.9, s * 0.86), s * 0.1, deco);

    final scale = s / 340; // NoteCard is designed at ~340 logical px.
    final pb = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: TextAlign.center,
        fontFamily: noteFonts[style.font],
        fontSize: _fontSizeFor(text, 34) * scale,
        fontWeight: FontWeight.w800,
        height: 1.2,
      ),
    )
      ..pushStyle(ui.TextStyle(color: bg.ink))
      ..addText(text);
    final paragraph = pb.build()..layout(ui.ParagraphConstraints(width: s - 48 * scale * 2));
    canvas.drawParagraph(
      paragraph,
      Offset(48 * scale, (s - paragraph.height) / 2),
    );

    final image = await recorder.endRecording().toImage(size, size);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    return file;
  }
}
