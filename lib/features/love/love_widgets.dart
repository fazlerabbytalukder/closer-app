import 'dart:io';

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

/// "Opens in 3 days", "Opens tomorrow at 08:00", "Opens in 25 min".
String opensIn(DateTime at, DateTime now) {
  final d = at.difference(now);
  if (d.isNegative || d.inSeconds <= 0) return 'Ready to open';
  if (d.inMinutes < 60) return 'Opens in ${d.inMinutes + 1} min';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final days = day.difference(today).inDays;
  final time = DateFormat('HH:mm').format(at);
  if (days == 0) return 'Opens today at $time';
  if (days == 1) return 'Opens tomorrow at $time';
  if (days < 7) return 'Opens ${DateFormat('EEEE').format(at)} at $time';
  if (days < 60) return 'Opens in $days days';
  return 'Opens ${DateFormat('d MMM yyyy').format(at)}';
}

/// A sealed (or ready) envelope with a wax seal.
class EnvelopeCard extends StatelessWidget {
  const EnvelopeCard({
    required this.title,
    required this.subtitle,
    super.key,
    this.ready = false,
    this.opened = false,
    this.onTap,
    this.height = 120,
  });

  final String title;
  final String subtitle;
  final bool ready;
  final bool opened;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final paper = opened ? const Color(0xFFFFFBF5) : const Color(0xFFFFF1E6);
    Widget card = Material(
      color: paper,
      borderRadius: BorderRadius.circular(Radii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.card),
        onTap: onTap,
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              // Envelope flap.
              Positioned.fill(child: CustomPaint(painter: _FlapPainter(opened: opened))),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.m),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(colors: [Color(0xFFE5506F), Color(0xFFB8304F)]),
                        boxShadow: [BoxShadow(color: const Color(0xFFB8304F).withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 3))],
                      ),
                      child: Text(opened ? '💌' : (ready ? '✨' : '🔒'), style: const TextStyle(fontSize: 20)),
                    ),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.tt.titleMedium?.copyWith(color: Brand.ink, fontFamily: 'Nunito'),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.tt.bodySmall?.copyWith(
                              color: ready ? const Color(0xFFB8304F) : Brand.grey700,
                              fontWeight: ready ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onTap != null) const Icon(Icons.chevron_right_rounded, color: Brand.grey500),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (ready && !opened) {
      card = card
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .shimmer(duration: 1800.ms, color: Colors.white.withValues(alpha: 0.6))
          .scaleXY(begin: 1, end: 1.015, duration: 900.ms, curve: Curves.easeInOut);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.card),
        boxShadow: const [BoxShadow(color: Color(0x1A8A4B2E), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: card,
    );
  }
}

class _FlapPainter extends CustomPainter {
  _FlapPainter({required this.opened});

  final bool opened;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE8C9B0).withValues(alpha: opened ? 0.25 : 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = Path()
      ..moveTo(10, 10)
      ..lineTo(size.width / 2, size.height * (opened ? 0.25 : 0.55))
      ..lineTo(size.width - 10, 10);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_FlapPainter old) => old.opened != opened;
}

/// A wobbling gift box that invites a tap.
class GiftBox extends StatelessWidget {
  const GiftBox({super.key, this.size = 64, this.wobble = true});

  final double size;
  final bool wobble;

  @override
  Widget build(BuildContext context) {
    final box = Text('🎁', style: TextStyle(fontSize: size));
    if (!wobble) return box;
    return box
        .animate(onPlay: (c) => c.repeat())
        .rotate(begin: 0, end: 0.03, duration: 120.ms)
        .then()
        .rotate(begin: 0.03, end: -0.03, duration: 120.ms)
        .then()
        .rotate(begin: -0.03, end: 0, duration: 120.ms)
        .then(delay: 1400.ms);
  }
}

/// Picks a photo from the gallery and shows it, with a remove button.
class PhotoField extends StatelessWidget {
  const PhotoField({required this.path, required this.onChanged, super.key, this.label = 'Add a photo'});

  /// Local file path of the picked photo (before upload).
  final String? path;
  final ValueChanged<String?> onChanged;
  final String label;

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2000, maxHeight: 2000, imageQuality: 92);
    if (x != null) onChanged(x.path);
  }

  @override
  Widget build(BuildContext context) {
    final p = path;
    if (p == null) {
      return OutlinedButton.icon(
        onPressed: _pick,
        icon: const Icon(Icons.add_photo_alternate_rounded),
        label: Text(label),
      );
    }
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.small + 4),
          child: AspectRatio(aspectRatio: 4 / 3, child: Image.file(File(p), fit: BoxFit.cover)),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: IconButton.filledTonal(
            tooltip: 'Remove photo',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => onChanged(null),
          ),
        ),
        Positioned(
          bottom: 6,
          right: 6,
          child: IconButton.filledTonal(tooltip: 'Change photo', icon: const Icon(Icons.edit_rounded), onPressed: _pick),
        ),
      ],
    );
  }
}

/// Image stored by the backend (storage ref or local path).
class StoredImage extends ConsumerWidget {
  const StoredImage(this.path, {super.key, this.fit = BoxFit.cover});

  /// Storage ref or local file path.
  final String? path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(imageUrlProvider(path)).value;
    return AppImage(url, fit: fit);
  }
}

/// Loads and shows a capsule's content (text, photo, gift).
class CapsuleBody extends ConsumerWidget {
  const CapsuleBody({required this.capsule, super.key, this.textStyle, this.center = false});

  final Capsule capsule;
  final TextStyle? textStyle;
  final bool center;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.watch(capsuleContentProvider(capsule));
    return content.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(Space.m),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(Space.m),
        child: Text(e is CloserException ? e.message : 'Couldn’t open this one. Try again later.'),
      ),
      data: (c) {
        final gift = VirtualGift.byId(c.giftId);
        return Column(
          crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            if (gift != null) ...[
              Text(gift.emoji, style: const TextStyle(fontSize: 72)),
              Text(gift.name, style: context.tt.titleLarge),
              const SizedBox(height: Space.s),
            ],
            if (c.photoPath != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.small + 4),
                child: AspectRatio(aspectRatio: 4 / 3, child: StoredImage(c.photoPath)),
              ),
              const SizedBox(height: Space.s),
            ],
            if (c.text.isNotEmpty)
              Text(
                c.text,
                textAlign: center ? TextAlign.center : TextAlign.start,
                style: textStyle ?? context.tt.bodyLarge?.copyWith(height: 1.5),
              ),
          ],
        );
      },
    );
  }
}
