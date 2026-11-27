import 'dart:io';

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/soft_ui.dart';
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
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 92,
    );
    if (x != null) onChanged(x.path);
  }

  @override
  Widget build(BuildContext context) {
    final p = path;
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (p == null) {
      // Lavender pill with violet text (Duosy secondary button).
      return PillButton(
        label: label,
        icon: Icons.add_photo_alternate_outlined,
        height: 52,
        glow: false,
        color: SoftTone.violet.fill(context),
        foreground: dark ? Colors.white : Brand.royal,
        onPressed: _pick,
      );
    }
    // The photo in a white card, with round white remove / change buttons.
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: context.cc.card,
        borderRadius: BorderRadius.circular(26),
        boxShadow: dark ? null : softCardShadow,
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Image.file(File(p), fit: BoxFit.cover),
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: CircleIconButton(icon: Icons.close_rounded, tooltip: 'Remove photo', onTap: () => onChanged(null)),
          ),
          Positioned(
            bottom: 10,
            right: 10,
            child: CircleIconButton(icon: Icons.edit_outlined, tooltip: 'Change photo', onTap: _pick),
          ),
        ],
      ),
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
