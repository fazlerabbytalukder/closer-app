import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/services/ads.dart';
import 'package:closer_app/core/services/widget_bridge.dart';
import 'package:closer_app/core/services/widget_contract.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/features/me/widget_previews.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final _canPinProvider = FutureProvider.autoDispose<bool>((ref) => WidgetBridge.canPin());

/// "My widgets": previews, add-to-home-screen and the theme picker (F2, F11).
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
    final current = (me == null ? null : pair?.widgetTheme[me]) ?? WidgetThemes.classic;
    final shown = _preview ?? current;

    Future<void> pin(String receiver) async {
      if (canPin) {
        await WidgetBridge.requestPin(receiver);
      } else {
        showToast(context, 'Long-press your home screen → Widgets → Closer');
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My widgets')),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          FakeHomeScreen(themeId: shown),
          const SectionHeader('Add to home screen'),
          _AddRow(emoji: '💌', title: 'Photo widget', subtitle: 'Their latest photo, note or doodle · S/M/L', onTap: () => pin(WidgetReceivers.partnerPhoto)),
          _AddRow(emoji: '📅', title: 'Countdown widget', subtitle: 'Days until your next date · S/M', onTap: () => pin(WidgetReceivers.countdown)),
          _AddRow(emoji: '🌱', title: 'Plant widget', subtitle: 'Your shared plant and streak · S/M', onTap: () => pin(WidgetReceivers.plant)),
          const SectionHeader('Theme'),
          SizedBox(
            height: 112,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final id in WidgetThemes.all)
                  _ThemeSwatch(
                    palette: paletteFor(id),
                    selected: current == id,
                    previewing: _preview == id,
                    locked: WidgetThemes.plus.contains(id) && !plus,
                    onTap: () => setState(() => _preview = id),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.m),
          if (_preview != null && _preview != current) _applyButton(_preview!, plus),
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
          CloserButton(label: 'Unlock ${paletteFor(id).name} with Plus', kind: CloserButtonKind.accent, onPressed: () => context.push('/paywall?from=themes')),
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
    return CloserButton(label: 'Use ${paletteFor(id).name}', onPressed: () => _apply(id));
  }

  Future<void> _apply(String id) async {
    final ok = await runAction(context, () => ref.read(backendProvider).setWidgetTheme(id));
    if (ok && mounted) {
      setState(() => _preview = null);
      showToast(context, 'Widget theme updated');
    }
  }
}

class _AddRow extends StatelessWidget {
  const _AddRow({required this.emoji, required this.title, required this.subtitle, required this.onTap});

  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: CloserCard(
        onTap: onTap,
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.tt.titleMedium),
                  Text(subtitle, style: context.tt.bodySmall?.copyWith(color: context.cc.muted)),
                ],
              ),
            ),
            Icon(Icons.add_circle_rounded, color: context.cc.accent),
          ],
        ),
      ),
    );
  }
}

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
    return Padding(
      padding: const EdgeInsets.only(right: Space.s),
      child: Semantics(
        button: true,
        selected: selected,
        label: '${palette.name} theme${locked ? ', Plus' : ''}',
        child: GestureDetector(
          onTap: onTap,
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: palette.bg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selected || previewing ? context.cc.accent : context.cs.outlineVariant,
                    width: selected || previewing ? 3 : 1.5,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(width: 34, height: 34, decoration: BoxDecoration(color: palette.primary, shape: BoxShape.circle)),
                    if (locked)
                      const Positioned(top: 4, right: 4, child: Icon(Icons.workspace_premium_rounded, size: 16, color: Brand.amber)),
                    if (selected)
                      const Icon(Icons.check_rounded, color: Colors.white),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(palette.name, style: context.tt.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}
