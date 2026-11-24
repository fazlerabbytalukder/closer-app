import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/widget_contract.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/plant_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Widget theme palettes — must match WidgetTheme.kt and the
/// `res/drawable/widget_bg_*.xml` gradients.
class WidgetPalette {
  const WidgetPalette({
    required this.id,
    required this.name,
    required Color bg,
    required this.surface,
    required this.primary,
    required this.text,
    required this.accent,
    this.gradient,
  }) : _solid = bg;

  /// A gradient theme: white text on a diagonal gradient with frosted chips.
  const WidgetPalette.gradient(this.id, this.name, List<Color> colors)
    : gradient = colors,
      _solid = const Color(0x00000000),
      surface = const Color(0x38FFFFFF),
      primary = Colors.white,
      text = Colors.white,
      accent = Colors.white;

  final String id;
  final String name;
  final Color _solid;

  /// Solid background, or the gradient's first colour.
  Color get bg => gradient?.first ?? _solid;

  /// Chips, frames and bubbles drawn over the background.
  final Color surface;
  final Color primary;
  final Color text;
  final Color accent;

  /// Diagonal gradient (top-left → bottom-right); null = solid [bg].
  final List<Color>? gradient;

  Color get muted => text.withValues(alpha: 0.8);

  static const heart = Color(0xFFFF4F7B);
}

const widgetPalettes = <String, WidgetPalette>{
  WidgetThemes.classic: WidgetPalette.gradient('classic', 'Duosy', [
    Color(0xFF1737E2),
    Color(0xFF7A4BE8),
    Color(0xFFFF5C9A),
  ]),
  WidgetThemes.blush: WidgetPalette.gradient('blush', 'Blush', [
    Color(0xFFFF5C8A),
    Color(0xFFFF7FA3),
    Color(0xFFFFB0C8),
  ]),
  WidgetThemes.midnight: WidgetPalette.gradient('midnight', 'Midnight', [
    Color(0xFF141033),
    Color(0xFF2E1F66),
    Color(0xFF5B2E8C),
  ]),
  WidgetThemes.mint: WidgetPalette.gradient('mint', 'Mint', [Color(0xFF0E9F85), Color(0xFF2DBE8F), Color(0xFF7EDDB0)]),
  WidgetThemes.sunset: WidgetPalette.gradient('sunset', 'Sunset', [
    Color(0xFFFF5E62),
    Color(0xFFFF8C5A),
    Color(0xFFFFC371),
  ]),
  WidgetThemes.dynamic: WidgetPalette(
    id: 'dynamic',
    name: 'Material You',
    bg: Color(0xFFF3EDF7),
    surface: Color(0xFFE8DEF8),
    primary: Color(0xFF6750A4),
    text: Color(0xFF1D1B20),
    accent: Color(0xFF6750A4),
  ),
};

WidgetPalette paletteFor(String id) => widgetPalettes[id] ?? widgetPalettes[WidgetThemes.classic]!;

// ------------------------------------------------------------- building blocks

/// The widget's rounded body: the theme gradient with soft light bubbles.
class WidgetFrame extends StatelessWidget {
  const WidgetFrame({required this.palette, required this.child, super.key, this.padding = 10, this.radius = 22});

  final WidgetPalette palette;
  final Widget child;
  final double padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final g = palette.gradient;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: palette.bg,
        gradient: g == null ? null : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: g),
        boxShadow: [BoxShadow(color: palette.bg.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Stack(
        children: [
          if (g != null) ...[
            const Positioned(right: -40, top: -50, child: _LightBubble(size: 120, alpha: 0.12)),
            const Positioned(left: -30, bottom: -40, child: _LightBubble(size: 90, alpha: 0.08)),
          ],
          Positioned.fill(
            child: Padding(padding: EdgeInsets.all(padding), child: child),
          ),
        ],
      ),
    );
  }
}

class _LightBubble extends StatelessWidget {
  const _LightBubble({required this.size, required this.alpha});

  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: alpha),
    ),
  );
}

/// Frosted chip ("💕 Next date").
class WidgetChip extends StatelessWidget {
  const WidgetChip(this.text, {required this.palette, super.key, this.fontSize = 10});

  final String text;
  final WidgetPalette palette;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(999)),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: palette.text, fontWeight: FontWeight.w800, fontSize: fontSize),
    ),
  );
}

/// An emoji in a frosted circle.
class WidgetEmojiBubble extends StatelessWidget {
  const WidgetEmojiBubble(this.emoji, {required this.palette, super.key, this.size = 30});

  final String emoji;
  final WidgetPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: palette.surface, shape: BoxShape.circle),
    child: Text(emoji, style: TextStyle(fontSize: size * 0.5)),
  );
}

/// A photo with an optional dark fade at the bottom for white text.
class WidgetPhoto extends StatelessWidget {
  const WidgetPhoto({required this.palette, super.key, this.url, this.overlay, this.placeholder = '💞', this.badge});

  final WidgetPalette palette;
  final String? url;
  final Widget? overlay;
  final String placeholder;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ColoredBox(
        color: palette.surface,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url == null) Center(child: Text(placeholder, style: const TextStyle(fontSize: 34))) else AppImage(url),
            if (overlay != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(9, 18, 9, 7),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0x4D000000), Color(0xB3000000)],
                    ),
                  ),
                  child: overlay,
                ),
              ),
            if (badge != null) Positioned(top: 6, right: 6, child: badge!),
          ],
        ),
      ),
    );
  }
}

/// Pink heart badge for a fresh "thinking of you" tap.
class WidgetHeartBadge extends StatelessWidget {
  const WidgetHeartBadge({super.key, this.emoji = '❤️'});

  final String emoji;

  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 24,
    alignment: Alignment.center,
    decoration: const BoxDecoration(color: WidgetPalette.heart, shape: BoxShape.circle),
    child: Text(emoji, style: const TextStyle(fontSize: 11)),
  );
}

const _onPhoto = TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11);
const _onPhotoMuted = TextStyle(color: Color(0xD1FFFFFF), fontWeight: FontWeight.w600, fontSize: 9.5);

/// Lays a small (2×2) widget out at its real size and scales it to fit, so
/// it looks the same at any preview size.
class SmallWidgetBox extends StatelessWidget {
  const SmallWidgetBox({required this.child, super.key});

  static const design = 130.0;

  final Widget child;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: FittedBox(
      child: SizedBox.square(dimension: design, child: child),
    ),
  );
}

// ------------------------------------------------------------------- previews

/// Partner photo widget (small), as PartnerPhotoWidget.kt draws it.
class PhotoWidgetPreview extends ConsumerWidget {
  const PhotoWidgetPreview({required this.themeId, super.key});

  final String themeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = paletteFor(themeId);
    final me = ref.watch(authUidProvider).value;
    final pair = ref.watch(pairProvider).value;
    final name = ref.watch(partnerNameProvider);
    final latest = me == null ? null : pair?.latestItemByUser[pair.partnerOf(me)];
    final image = ref.watch(imageUrlProvider(latest?.thumbPath)).value;
    return SmallWidgetBox(
      child: WidgetFrame(
        palette: p,
        padding: 5,
        child: latest == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  WidgetEmojiBubble('💌', palette: p, size: 40),
                  const SizedBox(height: 8),
                  Text(
                    'Waiting for $name’s first photo',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: TextStyle(color: p.text, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ],
              )
            : WidgetPhoto(
                palette: p,
                url: image,
                placeholder: '💌',
                badge: const WidgetHeartBadge(),
                overlay: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (latest.caption.isNotEmpty)
                      Text(latest.caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: _onPhoto),
                    Row(
                      children: [
                        Expanded(
                          child: Text('💌 $name', maxLines: 1, overflow: TextOverflow.ellipsis, style: _onPhoto),
                        ),
                        Text(timeAgo(latest.sentAt), style: _onPhotoMuted),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Countdown widget (small), as CountdownWidget.kt draws it.
class CountdownWidgetPreview extends ConsumerWidget {
  const CountdownWidgetPreview({required this.themeId, super.key});

  final String themeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = paletteFor(themeId);
    final list = ref.watch(countdownsProvider).value ?? const <Countdown>[];
    final c = list.isEmpty ? null : list.first;
    final days = c?.daysLeft(DateTime.now());
    return SmallWidgetBox(
      child: WidgetFrame(
        palette: p,
        child: c == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  WidgetEmojiBubble('📅', palette: p, size: 34),
                  const SizedBox(height: 6),
                  Text(
                    'Add a date',
                    style: TextStyle(color: p.text, fontWeight: FontWeight.w800, fontSize: 11),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      WidgetEmojiBubble(c.emoji.isEmpty ? '💕' : c.emoji, palette: p, size: 26),
                      const Spacer(),
                      const Text('💕', style: TextStyle(fontSize: 9)),
                    ],
                  ),
                  const Spacer(),
                  FittedBox(
                    child: Text(
                      days == 0 ? 'Today!' : '$days',
                      style: TextStyle(color: p.text, fontWeight: FontWeight.w900, fontSize: 30, height: 1),
                    ),
                  ),
                  Text(
                    days == 0 ? c.title : '${days == 1 ? 'day' : 'days'} to ${c.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontWeight: FontWeight.w800, fontSize: 9.5),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Plant widget (small), as PlantWidget.kt draws it.
class PlantWidgetPreview extends ConsumerWidget {
  const PlantWidgetPreview({required this.themeId, super.key});

  final String themeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = paletteFor(themeId);
    final pair = ref.watch(pairProvider).value;
    final streak = pair?.streak.count ?? 0;
    return SmallWidgetBox(
      child: WidgetFrame(
        palette: p,
        padding: 8,
        child: Column(
          children: [
            Expanded(
              child: FittedBox(
                child: PlantArt(stage: pair?.plant.stage ?? 0, health: pair?.plant.health ?? PlantHealth.healthy),
              ),
            ),
            const SizedBox(height: 3),
            WidgetChip(streak > 0 ? '🔥 $streak' : '🌱 Day 1', palette: p),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ home mock-up

/// A pretend phone home screen showing the widgets in a theme (plan F11).
class FakeHomeScreen extends StatelessWidget {
  const FakeHomeScreen({required this.themeId, super.key});

  final String themeId;

  @override
  Widget build(BuildContext context) {
    Widget app(IconData i) => Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
      ),
      child: Icon(i, color: Colors.white, size: 21),
    );
    final now = DateTime.now();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 3),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFB9C6FF), Color(0xFFE7C6F5), Color(0xFFFFC2D4)],
        ),
        boxShadow: const [BoxShadow(color: Color(0x261737E2), blurRadius: 30, offset: Offset(0, 14))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Status bar.
          Row(
            children: [
              Text(
                DateFormat('H:mm').format(now),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
              ),
              const Spacer(),
              const Icon(Icons.signal_cellular_alt_rounded, color: Colors.white, size: 13),
              const SizedBox(width: 3),
              const Icon(Icons.wifi_rounded, color: Colors.white, size: 13),
              const SizedBox(width: 3),
              const Icon(Icons.battery_full_rounded, color: Colors.white, size: 13),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('EEEE, d MMMM').format(now),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                app(Icons.phone_rounded),
                app(Icons.chat_bubble_rounded),
                app(Icons.camera_alt_rounded),
                app(Icons.music_note_rounded),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
