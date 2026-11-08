import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/widget_contract.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/plant_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Widget theme palettes — must match WidgetTheme.kt.
class WidgetPalette {
  const WidgetPalette({
    required this.id,
    required this.name,
    required this.bg,
    required this.surface,
    required this.primary,
    required this.text,
    required this.accent,
  });

  final String id;
  final String name;
  final Color bg;
  final Color surface;
  final Color primary;
  final Color text;
  final Color accent;
}

const widgetPalettes = <String, WidgetPalette>{
  WidgetThemes.classic: WidgetPalette(id: 'classic', name: 'Classic', bg: Color(0xFFFFFFFF), surface: Color(0xFFE6F0FC), primary: Color(0xFF2F7BE6), text: Color(0xFF1C2433), accent: Color(0xFFFF6B8A)),
  WidgetThemes.blush: WidgetPalette(id: 'blush', name: 'Blush', bg: Color(0xFFFFF1F4), surface: Color(0xFFFFDDE5), primary: Color(0xFFFF6B8A), text: Color(0xFF3A1F27), accent: Color(0xFFFF6B8A)),
  WidgetThemes.midnight: WidgetPalette(id: 'midnight', name: 'Midnight', bg: Color(0xFF141A2E), surface: Color(0xFF222B45), primary: Color(0xFF8FB4FF), text: Color(0xFFF2F4FA), accent: Color(0xFFFF8FA6)),
  WidgetThemes.mint: WidgetPalette(id: 'mint', name: 'Mint', bg: Color(0xFFECF8EE), surface: Color(0xFFD3F0D8), primary: Color(0xFF2E9E52), text: Color(0xFF1D3323), accent: Color(0xFFFF6B8A)),
  WidgetThemes.sunset: WidgetPalette(id: 'sunset', name: 'Sunset', bg: Color(0xFFFFF3E6), surface: Color(0xFFFFE0C2), primary: Color(0xFFF07B3F), text: Color(0xFF3B2416), accent: Color(0xFFFF6B8A)),
  WidgetThemes.dynamic: WidgetPalette(id: 'dynamic', name: 'Material You', bg: Color(0xFFF3EDF7), surface: Color(0xFFE8DEF8), primary: Color(0xFF6750A4), text: Color(0xFF1D1B20), accent: Color(0xFFFF6B8A)),
};

WidgetPalette paletteFor(String id) => widgetPalettes[id] ?? widgetPalettes[WidgetThemes.classic]!;

/// Flutter preview of the partner photo widget (same layout rules as the
/// Glance widget).
class PhotoWidgetPreview extends ConsumerWidget {
  const PhotoWidgetPreview({required this.themeId, super.key, this.large = false});

  final String themeId;
  final bool large;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = paletteFor(themeId);
    final me = ref.watch(authUidProvider).value;
    final pair = ref.watch(pairProvider).value;
    final name = ref.watch(partnerNameProvider);
    final latest = me == null ? null : pair?.latestItemByUser[pair.partnerOf(me)];
    final image = ref.watch(imageUrlProvider(latest?.thumbPath)).value;
    return AspectRatio(
      aspectRatio: large ? 1 : 1,
      child: Container(
        decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: latest == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Waiting for $name’s first photo 💌',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.text, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  AppImage(image),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(10, 16, 10, 8),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Color(0x99000000)],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (latest.caption.isNotEmpty)
                            Text(latest.caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                          Text('$name · ${timeAgo(latest.sentAt)}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 10)),
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

class CountdownWidgetPreview extends ConsumerWidget {
  const CountdownWidgetPreview({required this.themeId, super.key});

  final String themeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = paletteFor(themeId);
    final list = ref.watch(countdownsProvider).value ?? const <Countdown>[];
    final c = list.isEmpty ? null : list.first;
    final days = c?.daysLeft(DateTime.now());
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(22)),
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: c == null
              ? [Text('📅', style: const TextStyle(fontSize: 24)), Text('Add a date', style: TextStyle(color: p.text, fontWeight: FontWeight.w700, fontSize: 12))]
              : [
                  Text(c.emoji, style: const TextStyle(fontSize: 20)),
                  Text(days == 0 ? 'Today!' : '$days', style: TextStyle(color: p.primary, fontWeight: FontWeight.w900, fontSize: days == 0 ? 22 : 34, height: 1.1)),
                  Text(
                    days == 0 ? c.title : '${days == 1 ? 'day' : 'days'} to ${c.title}',
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.text, fontWeight: FontWeight.w700, fontSize: 11),
                  ),
                ],
        ),
      ),
    );
  }
}

class PlantWidgetPreview extends ConsumerWidget {
  const PlantWidgetPreview({required this.themeId, super.key});

  final String themeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = paletteFor(themeId);
    final pair = ref.watch(pairProvider).value;
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(22)),
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Expanded(child: FittedBox(child: PlantArt(stage: pair?.plant.stage ?? 0, health: pair?.plant.health ?? PlantHealth.healthy))),
            Text('🔥 ${pair?.streak.count ?? 0}', style: TextStyle(color: p.text, fontWeight: FontWeight.w800, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// A pretend home screen to preview widgets and themes (plan F11).
class FakeHomeScreen extends StatelessWidget {
  const FakeHomeScreen({required this.themeId, super.key});

  final String themeId;

  @override
  Widget build(BuildContext context) {
    Widget app(Color c, IconData i) => Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(12)),
              child: Icon(i, color: Colors.white, size: 22),
            ),
          ],
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.card),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF9DB8F5), Color(0xFFF5B6C8)],
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(flex: 2, child: PhotoWidgetPreview(themeId: themeId)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    CountdownWidgetPreview(themeId: themeId),
                    const SizedBox(height: 12),
                    PlantWidgetPreview(themeId: themeId),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              app(const Color(0xFF34A853), Icons.phone_rounded),
              app(const Color(0xFF4285F4), Icons.chat_bubble_rounded),
              app(const Color(0xFFEA4335), Icons.camera_alt_rounded),
              app(const Color(0xFFFBBC05), Icons.music_note_rounded),
            ],
          ),
        ],
      ),
    );
  }
}
