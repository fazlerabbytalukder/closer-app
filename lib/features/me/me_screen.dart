import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/config.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/soft_ui.dart';
import 'package:closer_app/features/onboarding/onboarding_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Icon tile colours from the Figma "me" screen: tinted square with a
/// matching outline icon.
enum _Tone {
  violet(Color(0xFFEFE9FF), Color(0xFF6A3DF0)),
  blue(Color(0xFFE3E6FF), Color(0xFF2F3BD6)),
  pink(Color(0xFFFFE3F0), Color(0xFFC2185B)),
  mint(Color(0xFFDDFBF4), Color(0xFF0F8F80)),
  yellow(Color(0xFFFFF1CC), Color(0xFF8A5A00));

  _Tone(this.background, this.icon);

  final Color background;
  final Color icon;
}

class MeScreen extends ConsumerWidget {
  const MeScreen({super.key});

  void _editProfile(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProfileScreen(editing: true)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider).value;
    final pair = ref.watch(pairProvider).value;
    final name = ref.watch(partnerNameProvider);
    final plus = ref.watch(isPlusProvider);
    final label = ref.watch(myLabelForPartnerProvider);
    final backend = ref.watch(backendProvider);
    if (me == null) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final top = MediaQuery.paddingOf(context).top;
    final subtitle = pair == null
        ? 'Not connected'
        : [
            if (label != null)
              '${label.emoji} $name is your ${label.title.toLowerCase()}'
            else
              '${modeLabel(pair.mode)} with $name',
            if (pair.daysTogether(DateTime.now()) case final d?)
              '$d days'
            else
              'since ${pair.pairedAt.day}/${pair.pairedAt.month}/${pair.pairedAt.year}',
          ].join(' · ');

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          // Violet header with the title and an edit button; the pink
          // profile card overlaps its rounded bottom edge.
          Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(left: 0, right: 0, top: 0, height: top + 140, child: const HeroBackdrop(radius: 32)),
              Padding(
                padding: EdgeInsets.fromLTRB(20, top + 22, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Me',
                            style: context.tt.headlineLarge?.copyWith(color: Colors.white, fontSize: 40, height: 1.1),
                          ),
                        ),
                        _HeaderButton(
                          icon: Icons.edit_outlined,
                          tooltip: 'Edit profile',
                          onTap: () => _editProfile(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    _ProfileCard(
                      name: me.displayName,
                      photo: me.photoUrl,
                      subtitle: subtitle,
                      onTap: () => _editProfile(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MoodCard(
                  emoji: me.mood?.emoji,
                  title: me.mood?.label ?? 'Set your mood',
                  subtitle: me.status?.text.isNotEmpty ?? false ? me.status!.text : 'Add a status for $name',
                  onTap: () => context.push('/mood'),
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
                              Text(
                                plus ? 'Duosy Plus is active' : 'Try Duosy Plus',
                                style: context.tt.titleMedium?.copyWith(color: plus ? null : Colors.white),
                              ),
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
                const _SectionTitle('Widgets'),
                _Group(
                  children: [
                    _Row(
                      icon: Icons.dashboard_customize_outlined,
                      tone: _Tone.violet,
                      title: 'My widgets & themes',
                      onTap: () => context.push('/widgets'),
                    ),
                    _Row(
                      icon: Icons.build_outlined,
                      tone: _Tone.yellow,
                      title: 'Widget not updating?',
                      onTap: () => context.push('/widget-help'),
                    ),
                  ],
                ),
                const _SectionTitle('Settings'),
                _Group(
                  children: [
                    _Row(
                      icon: Icons.favorite_border_rounded,
                      tone: _Tone.pink,
                      title: 'Relationship',
                      onTap: () => context.push('/relationship'),
                    ),
                    _Row(
                      icon: Icons.show_chart_rounded,
                      tone: _Tone.mint,
                      title: 'Our insights',
                      onTap: () => context.push('/insights'),
                    ),
                    _Row(
                      icon: Icons.tune_rounded,
                      tone: _Tone.blue,
                      title: 'Notifications & appearance',
                      onTap: () => context.push('/settings'),
                    ),
                    _Row(
                      icon: Icons.shield_outlined,
                      tone: _Tone.violet,
                      title: 'Privacy & data',
                      onTap: () => context.push('/privacy'),
                    ),
                    _Row(
                      icon: Icons.help_outline_rounded,
                      tone: _Tone.yellow,
                      title: 'Help & feedback',
                      onTap: () => context.push('/help'),
                    ),
                  ],
                ),
                const SizedBox(height: Space.l),
                Center(
                  child: Text(
                    'Duosy 1.0.0 · ${backend.isSimulated ? 'demo mode (on-device)' : backend.name}',
                    style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Frosted round button on the violet header (Figma: the pencil).
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.22),
        shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.45))),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 44, height: 44, child: Icon(icon, color: Colors.white, size: 20)),
        ),
      ),
    );
  }
}

/// Pink profile card with a ringed avatar and the mascot peeking in.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.name, required this.photo, required this.subtitle, required this.onTap});

  final String name;
  final String? photo;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const ink = Brand.ink;
    return Semantics(
      button: true,
      label: 'Edit profile',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFFF8CC6), Color(0xFFFFA9D3)]),
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(color: Color(0x66FF5C9E), blurRadius: 30, offset: Offset(0, 18), spreadRadius: -12),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -4,
                bottom: -22,
                child: Image.asset('assets/home/progress_mascot.png', width: 100, height: 110)
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .moveY(begin: 0, end: -4, duration: 1700.ms, curve: Curves.easeInOut),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 96, 16),
                child: Row(
                  children: [
                    Avatar(name: name, photo: photo, size: 62, ring: Colors.white),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.tt.titleLarge?.copyWith(color: ink, fontSize: 22),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.tt.bodyMedium?.copyWith(color: ink.withValues(alpha: 0.8)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mint "Set your mood" card: white icon tile, title, status line, chevron.
class _MoodCard extends StatelessWidget {
  const _MoodCard({required this.emoji, required this.title, required this.subtitle, required this.onTap});

  final String? emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const tone = _Tone.mint;
    return Container(
      decoration: BoxDecoration(
        color: dark ? tone.icon.withValues(alpha: 0.18) : tone.background,
        borderRadius: BorderRadius.circular(Radii.card),
        boxShadow: dark ? null : softCardShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.card),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: context.cc.card, borderRadius: BorderRadius.circular(14)),
                  alignment: Alignment.center,
                  child: emoji == null
                      ? Icon(Icons.sentiment_satisfied_alt_outlined, color: tone.icon, size: 22)
                      : Text(emoji!, style: const TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      Text(subtitle, style: context.tt.bodySmall?.copyWith(color: context.cc.muted)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Text(title, style: context.tt.titleLarge?.copyWith(fontSize: 20)),
    );
  }
}

/// White rounded card holding settings rows, separated by hairlines.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.cc.card,
        borderRadius: BorderRadius.circular(Radii.card),
        boxShadow: dark ? null : softCardShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (i < children.length - 1)
                Divider(height: 1, indent: 16, endIndent: 16, color: context.cs.outlineVariant.withValues(alpha: 0.5)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.tone, required this.title, required this.onTap});

  final IconData icon;
  final _Tone tone;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: dark ? tone.icon.withValues(alpha: 0.2) : tone.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: dark ? tone.background : tone.icon),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(title, style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
