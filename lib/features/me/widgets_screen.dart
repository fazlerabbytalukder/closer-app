import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/services/ads.dart';
import 'package:closer_app/core/services/widget_bridge.dart';
import 'package:closer_app/core/services/widget_contract.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/features/me/widget_previews.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final _canPinProvider = FutureProvider.autoDispose<bool>((ref) => WidgetBridge.canPin());

/// "My widgets": a home-screen mock-up, the widgets to add and the theme
/// picker (F2, F11).
class WidgetsScreen extends ConsumerStatefulWidget {
  const WidgetsScreen({super.key});

  @override
  ConsumerState<WidgetsScreen> createState() => _WidgetsScreenState();
}

class _WidgetsScreenState extends ConsumerState<WidgetsScreen> {
  String? _preview;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authUidProvider).value;
    final pair = ref.watch(pairProvider).value;
    final plus = ref.watch(isPlusProvider);
    final canPin = ref.watch(_canPinProvider).value ?? false;
    final name = ref.watch(partnerNameProvider);
    final current = (me == null ? null : pair?.widgetTheme[me]) ?? WidgetThemes.classic;
    final shown = _preview ?? current;

    Future<void> pin(String receiver) async {
      HapticFeedback.selectionClick().ignore();
      if (canPin) {
        await WidgetBridge.requestPin(receiver);
      } else {
        showToast(context, 'Long-press your home screen → Widgets → Closer');
      }
    }

    final widgets = [
      _WidgetInfo(
        title: 'Love photo',
        subtitle: '$name’s latest photo, note or doodle',
        sizes: 'S · M · L',
        preview: PhotoWidgetPreview(themeId: shown),
        onAdd: () => pin(WidgetReceivers.partnerPhoto),
      ),
      _WidgetInfo(
        title: 'Countdown',
        subtitle: 'Days until you’re together',
        sizes: 'S · M',
        preview: CountdownWidgetPreview(themeId: shown),
        onAdd: () => pin(WidgetReceivers.countdown),
      ),
      _WidgetInfo(
        title: 'Love plant',
        subtitle: 'Your shared plant and streak',
        sizes: 'S · M',
        preview: PlantWidgetPreview(themeId: shown),
        onAdd: () => pin(WidgetReceivers.plant),
      ),
      _WidgetInfo(
        title: 'Always with me',
        subtitle: 'A memory, a sweet line, time apart',
        sizes: 'S · M · L',
        preview: _AlwaysMini(themeId: shown),
        onAdd: () => context.push('/always'),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('My widgets')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
        children: [
          Text('Keep $name on your home screen 💞', style: context.tt.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Everything you two send shows up here instantly, no app to open.',
            style: context.tt.bodyMedium?.copyWith(color: context.cc.muted),
          ),
          const SizedBox(height: Space.m),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: FakeHomeScreen(key: ValueKey(shown), themeId: shown),
          ),
          const SizedBox(height: Space.l),
          _Heading(icon: Icons.palette_rounded, title: 'Theme', trailing: paletteFor(shown).name),
          const SizedBox(height: Space.s),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: WidgetThemes.all.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.s),
              itemBuilder: (context, i) {
                final id = WidgetThemes.all[i];
                return _ThemeSwatch(
                  palette: paletteFor(id),
                  selected: current == id,
                  previewing: _preview == id && _preview != current,
                  locked: WidgetThemes.plus.contains(id) && !plus,
                  onTap: () {
                    HapticFeedback.selectionClick().ignore();
                    setState(() => _preview = id == current ? null : id);
                  },
                );
              },
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: _preview != null && _preview != current
                ? Padding(
                    padding: const EdgeInsets.only(top: Space.s),
                    child: _applyButton(_preview!, plus),
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: Space.l),
          const _Heading(icon: Icons.add_to_home_screen_rounded, title: 'Add a widget'),
          const SizedBox(height: Space.s),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: Space.s + 4,
            crossAxisSpacing: Space.s + 4,
            childAspectRatio: 0.66,
            children: [
              for (final (i, w) in widgets.indexed)
                _WidgetCard(info: w).animate().fadeIn(delay: (60 * i).ms, duration: 300.ms).slideY(begin: 0.08),
            ],
          ),
          const SizedBox(height: Space.m),
          const AdBanner(),
        ],
      ),
    );
  }

  Widget _applyButton(String id, bool plus) {
    final locked = WidgetThemes.plus.contains(id) && !plus;
    if (locked) {
      return Column(
        children: [
          CloserButton(
            label: 'Unlock ${paletteFor(id).name} with Plus',
            kind: CloserButtonKind.accent,
            onPressed: () => context.push('/paywall?from=themes'),
          ),
          const SizedBox(height: Space.s),
          CloserButton(
            label: 'Watch an ad to try it for 24 h',
            kind: CloserButtonKind.secondary,
            onPressed: () async {
              final ok = await Ads.showRewarded(context);
              if (ok && mounted) await _apply(id);
            },
          ),
        ],
      );
    }
    return CloserButton(
      label: 'Use ${paletteFor(id).name} on my widgets',
      icon: Icons.check_rounded,
      onPressed: () => _apply(id),
    );
  }

  Future<void> _apply(String id) async {
    final ok = await runAction(context, () => ref.read(backendProvider).setWidgetTheme(id));
    if (ok && mounted) {
      HapticFeedback.mediumImpact().ignore();
      setState(() => _preview = null);
      showToast(context, 'Your widgets are ${paletteFor(id).name} now 💞');
    }
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.icon, required this.title, this.trailing});

  final IconData icon;
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: context.cc.accentTint, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 17, color: context.cc.accent),
        ),
        const SizedBox(width: Space.s),
        Text(title, style: context.tt.titleMedium),
        const Spacer(),
        if (trailing != null) Text(trailing!, style: context.tt.labelLarge?.copyWith(color: context.cc.muted)),
      ],
    );
  }
}

class _WidgetInfo {
  const _WidgetInfo({
    required this.title,
    required this.subtitle,
    required this.sizes,
    required this.preview,
    required this.onAdd,
  });

  final String title;
  final String subtitle;
  final String sizes;
  final Widget preview;
  final VoidCallback onAdd;
}

/// A widget in the gallery: live preview, name, sizes and an Add button.
class _WidgetCard extends StatelessWidget {
  const _WidgetCard({required this.info});

  final _WidgetInfo info;

  @override
  Widget build(BuildContext context) {
    return CloserCard(
      onTap: info.onAdd,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: info.preview),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(info.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.titleSmall),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: context.cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(info.sizes, style: context.tt.labelSmall?.copyWith(color: context.cc.muted, fontSize: 9)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Expanded(
            child: Text(
              info.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
            ),
          ),
          SizedBox(
            width: double.infinity,
            height: 32,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                shape: const StadiumBorder(),
              ),
              onPressed: info.onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The medium "Always with me" widget shrunk into a gallery tile.
class _AlwaysMini extends StatelessWidget {
  const _AlwaysMini({required this.themeId});

  final String themeId;

  @override
  Widget build(BuildContext context) {
    final p = paletteFor(themeId);
    return SmallWidgetBox(
      child: WidgetFrame(
        palette: p,
        padding: 5,
        child: WidgetPhoto(
          palette: p,
          overlay: const Text(
            'Saw each other 3 h ago',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10),
          ),
        ),
      ),
    );
  }
}

/// A theme: its gradient with a heart, a check when in use.
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.palette,
    required this.selected,
    required this.previewing,
    required this.locked,
    required this.onTap,
  });

  final WidgetPalette palette;
  final bool selected;
  final bool previewing;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = palette.gradient;
    final ring = selected || previewing;
    return Semantics(
      button: true,
      selected: selected,
      label: '${palette.name} theme${locked ? ', Plus' : ''}',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 70,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: ring ? context.cc.accent : Colors.transparent, width: 2.5),
                ),
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: palette.bg,
                    gradient: g == null
                        ? null
                        : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: g),
                    border: g == null ? Border.all(color: context.cs.outlineVariant) : null,
                    boxShadow: [
                      BoxShadow(color: palette.bg.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        selected ? Icons.check_rounded : Icons.favorite_rounded,
                        color: palette.text.withValues(alpha: selected ? 1 : 0.85),
                        size: 24,
                      ),
                      if (locked)
                        const Positioned(
                          top: 4,
                          right: 4,
                          child: Icon(Icons.workspace_premium_rounded, size: 15, color: Brand.amber),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                palette.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.tt.labelSmall?.copyWith(fontWeight: ring ? FontWeight.w800 : FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
