import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/features/love/love_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// "100 reasons I love you": both write reasons for each other; one of
/// your person's reasons opens for you every day.
class ReasonsScreen extends ConsumerWidget {
  const ReasonsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(partnerNameProvider);
    final mode = ref.watch(pairModeProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(mode == PairMode.couple ? '100 reasons I love you' : '100 reasons you’re special'),
          bottom: TabBar(tabs: [Tab(text: 'From $name'), const Tab(text: 'Written by you')]),
        ),
        body: const TabBarView(children: [_ForMe(), _ByMe()]),
      ),
    );
  }
}

class _ForMe extends ConsumerWidget {
  const _ForMe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authUidProvider).value;
    final name = ref.watch(partnerNameProvider);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final all = (ref.watch(capsulesProvider).value ?? const <Capsule>[])
        .where((c) => c.kind == CapsuleKind.reason && c.forUid == me)
        .toList()
      ..sort((a, b) => a.unlockAt.compareTo(b.unlockAt));
    final unlocked = all.where((c) => c.isUnlocked(now)).toList();
    final waiting = all.where((c) => !c.isUnlocked(now)).toList();
    final fresh = unlocked.where((c) => c.openedAt == null).toList();

    if (all.isEmpty) {
      return EmptyState(
        emoji: '💗',
        title: 'No reasons yet',
        body: 'When $name writes reasons for you, one opens here every day.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(Space.m),
      children: [
        _ProgressHeader(
          revealed: unlocked.length,
          total: all.length,
          next: waiting.isEmpty ? null : waiting.first.unlockAt,
          now: now,
          name: name,
        ),
        const SizedBox(height: Space.m),
        for (final c in fresh) ...[
          _SealedReason(capsule: c, number: unlocked.indexOf(c) + 1),
          const SizedBox(height: Space.s),
        ],
        if (unlocked.length > fresh.length) const SectionHeader('Your reasons so far'),
        for (final c in unlocked.reversed.where((c) => c.openedAt != null))
          _ReasonCard(capsule: c, number: unlocked.indexOf(c) + 1),
      ],
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.revealed, required this.total, required this.next, required this.now, required this.name});

  final int revealed;
  final int total;
  final DateTime? next;
  final DateTime now;
  final String name;

  @override
  Widget build(BuildContext context) {
    final n = next;
    return CloserCard(
      gradient: const LinearGradient(colors: [Color(0xFFFFE6EF), Color(0xFFF1EDFF)]),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            height: 76,
            child: Stack(
              alignment: Alignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: revealed / Capsule.maxReasons),
                  duration: 900.ms,
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => CircularProgressIndicator(
                    value: v,
                    strokeWidth: 8,
                    backgroundColor: Colors.white,
                    color: Brand.pink,
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Text('$revealed', style: context.tt.titleLarge?.copyWith(color: Brand.ink, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$revealed of ${Capsule.maxReasons} reasons', style: context.tt.titleMedium?.copyWith(color: Brand.ink)),
                const SizedBox(height: 2),
                Text(
                  n == null
                      ? '$name has more to write 💌'
                      : '${total - revealed} waiting · next ${opensIn(n, now).replaceFirst('Opens ', '')}',
                  style: context.tt.bodyMedium?.copyWith(color: Brand.grey700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Today's unopened reason: tap to flip it open.
class _SealedReason extends ConsumerStatefulWidget {
  const _SealedReason({required this.capsule, required this.number});

  final Capsule capsule;
  final int number;

  @override
  ConsumerState<_SealedReason> createState() => _SealedReasonState();
}

class _SealedReasonState extends ConsumerState<_SealedReason> {
  bool _open = false;

  Future<void> _reveal() async {
    hapticMedium();
    setState(() => _open = true);
    await ref.read(backendProvider).markCapsuleOpened(widget.capsule.id);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: 500.ms,
      transitionBuilder: (child, a) => ScaleTransition(scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack), child: child),
      child: _open
          ? _ReasonCard(key: const ValueKey('open'), capsule: widget.capsule, number: widget.number, highlight: true)
          : CloserCard(
              key: const ValueKey('sealed'),
              onTap: _reveal,
              gradient: const LinearGradient(colors: [Brand.pink, Color(0xFFFF9EB5)]),
              child: Row(
                children: [
                  const Text('💌', style: TextStyle(fontSize: 40))
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scaleXY(begin: 1, end: 1.12, duration: 700.ms),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Reason #${widget.number} is here!', style: context.tt.titleMedium?.copyWith(color: Colors.white)),
                        Text('Tap to open it', style: context.tt.bodyMedium?.copyWith(color: Colors.white70)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ReasonCard extends StatelessWidget {
  const _ReasonCard({required this.capsule, required this.number, super.key, this.highlight = false});

  final Capsule capsule;
  final int number;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: CloserCard(
        color: highlight ? context.cc.accentTint : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Brand.pink),
              child: Text('#$number', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CapsuleBody(capsule: capsule, textStyle: context.tt.titleMedium?.copyWith(height: 1.35)),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('d MMMM yyyy').format(capsule.unlockAt),
                    style: context.tt.bodySmall?.copyWith(color: highlight ? Brand.grey700 : context.cc.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ByMe extends ConsumerWidget {
  const _ByMe();

  static const _ideas = [
    'The way you…',
    'You always…',
    'I love it when you…',
    'You make me feel…',
    'Nobody else can…',
  ];

  Future<void> _add(BuildContext context, WidgetRef ref, List<Capsule> mine) async {
    final ctrl = TextEditingController();
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(Space.m, 0, Space.m, MediaQuery.viewInsetsOf(ctx).bottom + Space.m),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Reason #${mine.length + 1}', style: ctx.tt.titleLarge),
            const SizedBox(height: Space.s),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLength: CapsuleContent.maxReason,
              maxLines: 4,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Why are they special?'),
            ),
            Wrap(
              spacing: 6,
              children: [
                for (final i in _ideas)
                  ActionChip(
                    label: Text(i),
                    onPressed: () {
                      ctrl
                        ..text = i.replaceAll('…', ' ')
                        ..selection = TextSelection.collapsed(offset: ctrl.text.length);
                    },
                  ),
              ],
            ),
            const SizedBox(height: Space.m),
            CloserButton(label: 'Add reason', kind: CloserButtonKind.accent, onPressed: () => Navigator.pop(ctx, ctrl.text.trim())),
          ],
        ),
      ),
    );
    disposeAfterRoute(ctrl);
    if (text == null || text.isEmpty || !context.mounted) return;
    final now = DateTime.now();
    final unlockAt = Capsule.nextReasonUnlock(mine, now);
    final ok = await runAction(
      context,
      () => ref.read(backendProvider).sendCapsule(
            Capsule(id: '', kind: CapsuleKind.reason, authorId: '', forUid: '', createdAt: now, unlockAt: unlockAt),
            CapsuleContent(text: text),
          ),
    );
    if (ok && context.mounted) {
      hapticMedium();
      showToast(context, '${opensIn(unlockAt, now)} for ${ref.read(partnerNameProvider)} 💗');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authUidProvider).value;
    final name = ref.watch(partnerNameProvider);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final mine = (ref.watch(capsulesProvider).value ?? const <Capsule>[])
        .where((c) => c.kind == CapsuleKind.reason && c.authorId == me)
        .toList()
      ..sort((a, b) => a.unlockAt.compareTo(b.unlockAt));
    final full = mine.length >= Capsule.maxReasons;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: full
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _add(context, ref, mine),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add a reason'),
            ),
      body: mine.isEmpty
          ? EmptyState(
              emoji: '✍️',
              title: 'Write your first reason',
              body: 'Add as many as you like, up to 100. $name gets one every morning.',
              action: 'Add a reason',
              onAction: () => _add(context, ref, mine),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, 100),
              children: [
                Text(
                  '${mine.length} of ${Capsule.maxReasons} written · ${mine.where((c) => c.openedAt != null).length} read by $name',
                  style: context.tt.titleSmall,
                ),
                const SizedBox(height: Space.s),
                for (final (i, c) in mine.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.s),
                    child: CloserCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('#${i + 1}', style: context.tt.titleSmall?.copyWith(color: Brand.pink)),
                          const SizedBox(width: Space.m),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CapsuleBody(capsule: c, textStyle: context.tt.bodyLarge),
                                const SizedBox(height: 4),
                                Text(
                                  c.openedAt != null
                                      ? 'Read by $name ✓'
                                      : c.isUnlocked(now)
                                          ? 'Delivered, not read yet'
                                          : opensIn(c.unlockAt, now),
                                  style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
                                ),
                              ],
                            ),
                          ),
                          if (!c.isUnlocked(now))
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () async {
                                final ok = await confirm(context, title: 'Delete this reason?', body: '$name won’t get it.', ok: 'Delete', destructive: true);
                                if (ok && context.mounted) {
                                  await runAction(context, () => ref.read(backendProvider).deleteCapsule(c.id));
                                }
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
