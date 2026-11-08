import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/config.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/features/onboarding/onboarding_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class MeScreen extends ConsumerWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider).value;
    final pair = ref.watch(pairProvider).value;
    final name = ref.watch(partnerNameProvider);
    final plus = ref.watch(isPlusProvider);
    final label = ref.watch(myLabelForPartnerProvider);
    final backend = ref.watch(backendProvider);
    if (me == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text('Me')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.xl),
        children: [
          CloserCard(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ProfileScreen(editing: true)),
            ),
            child: Row(
              children: [
                Avatar(name: me.displayName, photo: me.photoUrl, size: 64),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(me.displayName, style: context.tt.titleLarge),
                      Text(
                        pair == null
                            ? 'Not connected'
                            : [
                                if (label != null) '${label.emoji} $name is your ${label.title.toLowerCase()}' else '${modeLabel(pair.mode)} with $name',
                                if (pair.daysTogether(DateTime.now()) case final d?) '$d days' else 'since ${pair.pairedAt.day}/${pair.pairedAt.month}/${pair.pairedAt.year}',
                              ].join(' · '),
                        style: context.tt.bodyMedium?.copyWith(color: context.cc.muted),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.edit_rounded, size: 20),
              ],
            ),
          ),
          const SizedBox(height: Space.m),
          CloserCard(
            onTap: () => context.push('/mood'),
            child: Row(
              children: [
                Text(me.mood?.emoji ?? '🙂', style: const TextStyle(fontSize: 32)),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(me.mood?.label ?? 'Set your mood', style: context.tt.titleMedium),
                      Text(
                        me.status?.text.isNotEmpty ?? false ? me.status!.text : 'Add a status for $name',
                        style: context.tt.bodyMedium?.copyWith(color: context.cc.muted),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
          if (AppConfig.monetizationEnabled) ...[
          const SizedBox(height: Space.m),
          CloserCard(
            gradient: plus ? null : LinearGradient(colors: context.cc.gradient),
            color: plus ? context.cc.accentTint : null,
            onTap: () => context.push('/paywall?from=me'),
            child: Row(
              children: [
                Icon(Icons.workspace_premium_rounded, color: plus ? Brand.amber : Colors.white, size: 32),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(plus ? 'Closer Plus is active' : 'Try Closer Plus', style: context.tt.titleMedium?.copyWith(color: plus ? null : Colors.white)),
                      Text(
                        plus ? 'Shared with $name' : 'Unlimited sends, all packs, no ads — for both of you',
                        style: context.tt.bodyMedium?.copyWith(color: plus ? context.cc.muted : Colors.white70),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: plus ? null : Colors.white),
              ],
            ),
          ),
          ],
          const SectionHeader('Widgets'),
          _Group(
            children: [
              _Row(icon: Icons.widgets_rounded, title: 'My widgets & themes', onTap: () => context.push('/widgets')),
              _Row(icon: Icons.build_circle_outlined, title: 'Widget not updating?', onTap: () => context.push('/widget-help')),
            ],
          ),
          const SectionHeader('Settings'),
          _Group(
            children: [
              _Row(icon: Icons.favorite_border_rounded, title: 'Relationship', onTap: () => context.push('/relationship')),
              _Row(icon: Icons.tune_rounded, title: 'Notifications & appearance', onTap: () => context.push('/settings')),
              _Row(icon: Icons.shield_outlined, title: 'Privacy & data', onTap: () => context.push('/privacy')),
              _Row(icon: Icons.help_outline_rounded, title: 'Help & feedback', onTap: () => context.push('/help')),
            ],
          ),
          const SizedBox(height: Space.l),
          Center(
            child: Text(
              'Closer 1.0.0 · ${backend.isSimulated ? 'demo mode (on-device)' : backend.name}',
              style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return CloserCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1) const Divider(height: 1, indent: 56),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title, style: context.tt.titleSmall),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
