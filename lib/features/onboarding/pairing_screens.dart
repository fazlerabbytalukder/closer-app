import 'dart:async';

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/app/router.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

/// Couple or best friends.
class ModeScreen extends ConsumerStatefulWidget {
  const ModeScreen({super.key});

  @override
  ConsumerState<ModeScreen> createState() => _ModeScreenState();
}

class _ModeScreenState extends ConsumerState<ModeScreen> {
  PairMode _mode = PairMode.couple;
  String? _label;

  @override
  void initState() {
    super.initState();
    final me = ref.read(meProvider).value;
    _mode = me?.pendingMode ?? PairMode.couple;
    _label = RelationLabel.validFor(me?.pendingLabel, _mode);
  }

  void _setMode(PairMode m) => setState(() {
        _mode = m;
        _label = RelationLabel.validFor(_label, m);
      });

  Future<void> _next(String route) async {
    await ref.read(backendProvider).setPendingMode(_mode, label: _label);
    if (mounted) unawaited(context.push(route));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
          padding: const EdgeInsets.all(Space.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: Space.l),
              Text('Who are you connecting with?', style: context.tt.headlineSmall),
              const SizedBox(height: Space.s),
              Text(
                'Closer is just for two. You can change this later.',
                style: context.tt.bodyLarge?.copyWith(color: context.cc.muted),
              ),
              const SizedBox(height: Space.xl),
              _ModeTile(
                emoji: '💑',
                title: 'My partner',
                subtitle: 'Couple mode — love notes, spicy questions, anniversaries',
                selected: _mode == PairMode.couple,
                color: Brand.pink,
                onTap: () => _setMode(PairMode.couple),
              ),
              const SizedBox(height: Space.m),
              _ModeTile(
                emoji: '👯',
                title: 'My best friend',
                subtitle: 'Best-friend mode — inside jokes, BFF questions, trips',
                selected: _mode == PairMode.friends,
                color: Brand.purple,
                onTap: () => _setMode(PairMode.friends),
              ),
              const SizedBox(height: Space.l),
              Text('They are my… (optional)', style: context.tt.titleSmall),
              const SizedBox(height: Space.s),
              RelationLabelChips(
                mode: _mode,
                selected: _label,
                onSelected: (id) => setState(() => _label = id == _label ? null : id),
              ),
              const Spacer(),
              Text(
                'One of you sends an invite code, the other enters it. That’s it, you’re connected.',
                textAlign: TextAlign.center,
                style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
              ),
              const SizedBox(height: Space.m),
              CloserButton(label: 'Invite your person', icon: Icons.send_rounded, onPressed: () => _next('/invite')),
              const SizedBox(height: Space.s),
              CloserButton(label: 'I have a code', kind: CloserButtonKind.secondary, onPressed: () => _next('/code')),
              const SizedBox(height: Space.s),
              CloserButton(
                label: 'Sign out',
                kind: CloserButtonKind.ghost,
                onPressed: () => ref.read(backendProvider).signOut(),
              ),
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

/// Choice chips for [RelationLabel]s of one mode (used in onboarding and
/// relationship settings).
class RelationLabelChips extends StatelessWidget {
  const RelationLabelChips({
    required this.mode,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final PairMode mode;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Space.s,
      runSpacing: Space.s,
      children: [
        for (final l in RelationLabel.forMode(mode))
          ChoiceChip(
            label: Text('${l.emoji} ${l.title}'),
            selected: selected == l.id,
            onSelected: (_) => onSelected(l.id),
          ),
      ],
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration: 200.ms,
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : context.cc.card,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: selected ? color : context.cs.outlineVariant, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.card),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Space.m),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 40)),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.tt.titleMedium),
                      const SizedBox(height: 2),
                      Text(subtitle, style: context.tt.bodyMedium?.copyWith(color: context.cc.muted)),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: selected ? color : context.cs.outlineVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the invite code + link and waits for the partner to join. The
/// router moves on automatically when `pairId` appears.
class InviteScreen extends ConsumerStatefulWidget {
  const InviteScreen({super.key});

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  Invite? _invite;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final mode = ref.read(meProvider).value?.pendingMode ?? PairMode.couple;
    try {
      final inv = await ref.read(backendProvider).createInvite(mode);
      if (mounted) setState(() => _invite = inv);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = _invite;
    final simulated = ref.watch(backendProvider).isSimulated;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                switch (RelationLabel.byId(ref.watch(meProvider).value?.pendingLabel)) {
                  final l? => 'Invite your ${l.title.toLowerCase()}',
                  null => 'Invite your person',
                },
                style: context.tt.headlineSmall,
              ),
              const SizedBox(height: Space.s),
              Text(
                'Send them this code (or the link). When they enter it in Closer, you’re connected.',
                style: context.tt.bodyLarge?.copyWith(color: context.cc.muted),
              ),
              const SizedBox(height: Space.xl),
              if (_error != null)
                Text('$_error', style: TextStyle(color: context.cs.error))
              else if (inv == null)
                const Center(child: CircularProgressIndicator())
              else ...[
                CloserCard(
                  color: context.cc.accentTint,
                  child: Column(
                    children: [
                      Text('Your code', style: context.tt.labelMedium?.copyWith(color: context.cc.muted)),
                      const SizedBox(height: Space.s),
                      Semantics(
                        label: 'Invite code ${inv.code.split('').join(' ')}',
                        child: Text(
                          inv.code,
                          style: context.tt.displaySmall?.copyWith(letterSpacing: 8, color: context.cc.accent),
                        ),
                      ),
                      const SizedBox(height: Space.s),
                      TextButton.icon(
                        onPressed: () {
                          unawaited(Clipboard.setData(ClipboardData(text: inv.code)));
                          showToast(context, 'Code copied');
                        },
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('Copy code'),
                      ),
                      Text(
                        'Expires in 48 hours',
                        style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
                      ),
                    ],
                  ),
                ).animate().fadeIn().scale(begin: const Offset(0.95, 0.95)),
                const SizedBox(height: Space.l),
                CloserButton(
                  label: 'Share invite link',
                  icon: Icons.ios_share_rounded,
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(
                      text: 'Let’s get Closer 💌 Join me so we can send things to each other’s home screen: ${inv.link} (code ${inv.code})',
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: Space.s),
                  Text('Waiting for them to join…', style: context.tt.bodyMedium?.copyWith(color: context.cc.muted)),
                ],
              ),
              if (simulated) ...[
                const SizedBox(height: Space.s),
                Text(
                  'Demo mode: a simulated partner will join in a few seconds.',
                  textAlign: TextAlign.center,
                  style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
                ),
              ],
              const SizedBox(height: Space.m),
            ],
          ),
        ),
      ),
    );
  }
}

/// Enter a 6-character code (also reached from invite links).
class CodeScreen extends ConsumerStatefulWidget {
  const CodeScreen({super.key});

  @override
  ConsumerState<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends ConsumerState<CodeScreen> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final pending = ref.read(pendingInviteProvider);
    if (pending != null) {
      _ctrl.text = pending.toUpperCase();
      WidgetsBinding.instance.addPostFrameCallback((_) => _submit());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_ctrl.text.trim().length != 6 || _busy) return;
    setState(() => _busy = true);
    await runAction(context, () => ref.read(backendProvider).acceptInvite(_ctrl.text));
    ref.read(pendingInviteProvider.notifier).set(null);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final simulated = ref.watch(backendProvider).isSimulated;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Enter their code', style: context.tt.headlineSmall),
              const SizedBox(height: Space.s),
              Text(
                simulated
                    ? 'Demo mode: any 6 characters connect you with a simulated partner.'
                    : 'Find it in their Closer app under “Invite your person”.',
                style: context.tt.bodyLarge?.copyWith(color: context.cc.muted),
              ),
              const SizedBox(height: Space.xl),
              TextField(
                controller: _ctrl,
                autofocus: true,
                maxLength: 6,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                style: context.tt.headlineMedium?.copyWith(letterSpacing: 10),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
                  TextInputFormatter.withFunction(
                    (o, n) => n.copyWith(text: n.text.toUpperCase()),
                  ),
                ],
                decoration: const InputDecoration(hintText: 'ABC123', counterText: ''),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: Space.l),
              CloserButton(
                label: 'Connect',
                loading: _busy,
                onPressed: _ctrl.text.trim().length == 6 ? _submit : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
