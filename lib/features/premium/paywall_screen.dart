import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// Closer Plus paywall (plan section 11).
///
/// Production: offerings from RevenueCat (`purchases_flutter`), products
/// `closer_plus_monthly` / `closer_plus_yearly` with a 7-day trial; the
/// RevenueCat webhook writes `pairs/{pairId}.premium` so both partners get
/// Plus. In demo mode the purchase toggles Plus locally.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({required this.trigger, super.key});

  final String trigger;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  bool _yearly = true;
  bool _busy = false;

  static const _features = [
    ('💌', 'Unlimited photos, notes & doodles'),
    ('🌙', 'All question packs — deep talk, long distance, spicy'),
    ('📅', 'Unlimited countdowns'),
    ('📸', 'Every memory, forever'),
    ('🎨', 'All widget themes & sticker packs'),
    ('🧊', '3 streak freezes a month'),
    ('🚫', 'No ads'),
  ];

  String get _headline => switch (widget.trigger) {
        'sends' => 'Keep the love flowing',
        'countdowns' => 'Count down to everything',
        'memories' => 'Keep every memory',
        'packs' => 'Unlock every question pack',
        'themes' || 'stickers' => 'Make your widget yours',
        _ => 'Closer Plus',
      };

  Future<void> _buy() async {
    setState(() => _busy = true);
    final backend = ref.read(backendProvider);
    final ok = await runAction(context, () async {
      if (!backend.isSimulated) {
        throw UnsupportedError('RevenueCat is not configured yet');
      }
      await backend.debugSetPremium(active: true);
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      hapticMedium();
      showToast(context, 'Welcome to Closer Plus ✨ — ${ref.read(partnerNameProvider)} has it too');
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final plus = ref.watch(isPlusProvider);
    final name = ref.watch(partnerNameProvider);
    final backend = ref.watch(backendProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(tooltip: 'Close', icon: const Icon(Icons.close_rounded), onPressed: () => context.pop()),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: Space.l),
                children: [
                  const Text('✨', textAlign: TextAlign.center, style: TextStyle(fontSize: 56))
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scaleXY(begin: 0.95, end: 1.08, duration: 1200.ms),
                  Text(_headline, textAlign: TextAlign.center, style: context.tt.headlineMedium),
                  const SizedBox(height: Space.s),
                  Text(
                    'One subscription for both you and $name.',
                    textAlign: TextAlign.center,
                    style: context.tt.bodyLarge?.copyWith(color: context.cc.muted),
                  ),
                  const SizedBox(height: Space.l),
                  for (final (e, t) in _features)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Text(e, style: const TextStyle(fontSize: 22)),
                          const SizedBox(width: Space.m),
                          Expanded(child: Text(t, style: context.tt.bodyLarge)),
                        ],
                      ),
                    ),
                  const SizedBox(height: Space.l),
                  if (!plus) ...[
                    _Plan(
                      title: 'Yearly',
                      price: r'$29.99 / year',
                      note: r'$2.50 / month · save 50%',
                      selected: _yearly,
                      badge: 'Best value',
                      onTap: () => setState(() => _yearly = true),
                    ),
                    const SizedBox(height: Space.s),
                    _Plan(
                      title: 'Monthly',
                      price: r'$4.99 / month',
                      note: 'Cancel anytime',
                      selected: !_yearly,
                      onTap: () => setState(() => _yearly = false),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Space.l),
              child: Column(
                children: [
                  if (plus) ...[
                    Text('You and $name have Closer Plus 💖', style: context.tt.titleMedium),
                    const SizedBox(height: Space.m),
                    CloserButton(
                      label: 'Manage subscription',
                      kind: CloserButtonKind.secondary,
                      onPressed: () => launchUrl(
                        Uri.parse('https://play.google.com/store/account/subscriptions?package=app.closer.widget'),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    if (backend.isSimulated)
                      CloserButton(
                        label: 'Demo: turn Plus off',
                        kind: CloserButtonKind.ghost,
                        onPressed: () => runAction(context, () => backend.debugSetPremium(active: false)),
                      ),
                  ] else ...[
                    CloserButton(label: 'Start 7-day free trial', kind: CloserButtonKind.accent, loading: _busy, onPressed: _buy),
                    const SizedBox(height: Space.s),
                    Text(
                      'Then ${_yearly ? r'$29.99/year' : r'$4.99/month'}. Cancel anytime in Google Play.${backend.isSimulated ? ' Demo mode: no real charge.' : ''}',
                      textAlign: TextAlign.center,
                      style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
                    ),
                    TextButton(
                      onPressed: () => showToast(context, backend.isSimulated ? 'Nothing to restore in demo mode' : 'Restoring purchases…'),
                      child: const Text('Restore purchases'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Plan extends StatelessWidget {
  const _Plan({
    required this.title,
    required this.price,
    required this.note,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String price;
  final String note;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final cc = context.cc;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.tile),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(Space.m),
          decoration: BoxDecoration(
            color: selected ? cc.accentTint : cc.card,
            borderRadius: BorderRadius.circular(Radii.tile),
            border: Border.all(color: selected ? cc.accent : context.cs.outlineVariant, width: 2),
          ),
          child: Row(
            children: [
              Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: selected ? cc.accent : cc.muted),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(title, style: context.tt.titleMedium),
                        if (badge != null) ...[const SizedBox(width: Space.s), CounterChip(label: badge!)],
                      ],
                    ),
                    Text(note, style: context.tt.bodySmall?.copyWith(color: cc.muted)),
                  ],
                ),
              ),
              Text(price, style: context.tt.titleSmall),
            ],
          ),
        ),
      ),
    );
  }
}
