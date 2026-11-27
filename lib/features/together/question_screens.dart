import 'dart:math' as math;

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/data/content.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/soft_ui.dart';
import 'package:closer_app/features/send/send_screen.dart' show captureToFile;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

/// Daily question: answer privately, partner's answer stays locked until
/// both answered, then a flip reveal (F4).
class QuestionScreen extends ConsumerStatefulWidget {
  const QuestionScreen({super.key});

  @override
  ConsumerState<QuestionScreen> createState() => _QuestionScreenState();
}

class _QuestionScreenState extends ConsumerState<QuestionScreen> {
  final _ctrl = TextEditingController();
  final _shareKey = GlobalKey();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final ok = await runAction(context, () => ref.read(backendProvider).submitAnswer(_ctrl.text));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      hapticMedium();
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _share() async {
    final path = await captureToFile(_shareKey, pixelRatio: 2.5);
    await SharePlus.instance.share(ShareParams(files: [XFile(path)], text: 'Our question of the day on Duosy 💌'));
  }

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(todayQuestionProvider).value;
    final me = ref.watch(meProvider).value;
    final partner = ref.watch(partnerProvider).value;
    final name = ref.watch(partnerNameProvider);
    if (q == null || me == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final answered = q.myAnswer != null;
    final partnerUid = q.answeredBy.firstWhere((u) => u != me.uid, orElse: () => '');
    final partnerAnswered = partnerUid.isNotEmpty;
    final pack = packById(q.packId);

    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          VioletPageHeader(
            title: '${pack.emoji} ${pack.title}',
            actions: [
              HeaderIconButton(
                icon: Icons.style_outlined,
                tooltip: 'Question packs',
                onTap: () => context.push('/packs'),
              ),
              HeaderIconButton(
                icon: Icons.history_rounded,
                tooltip: 'History',
                onTap: () => context.push('/question/history'),
              ),
            ],
            // Pink question card on the header edge (Figma "everyday
            // question"). It is also the card that gets shared.
            child: RepaintBoundary(
              key: _shareKey,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9CCB),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(color: Color(0x40FF5C9E), blurRadius: 30, offset: Offset(0, 16), spreadRadius: -12),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: 6,
                      top: q.revealed ? 8 : null,
                      bottom: q.revealed ? null : 6,
                      child: Image.asset('assets/together/streak_mascot.png', width: 76, height: 84),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                            child: Text(
                              'QUESTION OF THE DAY',
                              style: context.tt.labelSmall?.copyWith(
                                color: const Color(0xFFC2185B),
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.only(right: 80),
                            child: Text(
                              q.text,
                              style: context.tt.headlineSmall?.copyWith(color: Brand.ink, fontSize: 22, height: 1.25),
                            ),
                          ),
                          if (q.revealed) ...[
                            const SizedBox(height: 14),
                            _AnswerBubble(
                              name: me.displayName,
                              text: q.answers[me.uid] ?? q.myAnswer ?? '',
                              mine: true,
                            ),
                            const SizedBox(height: 10),
                            _AnswerBubble(
                              name: name,
                              text: q.answers[partnerUid] ?? '',
                            ).animate().flipV(begin: -0.5, duration: 600.ms, curve: Curves.easeOutBack),
                            const SizedBox(height: 12),
                            Text(
                              'Duosy',
                              style: context.tt.labelMedium?.copyWith(
                                color: const Color(0xFF7A1640),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ] else
                            const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!answered) ...[
                  if (partnerAnswered) ...[
                    _LockedAnswer(label: '$name answered — answer to unlock'),
                    const SizedBox(height: 12),
                  ],
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                    decoration: BoxDecoration(
                      color: context.cc.card,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: dark ? null : softCardShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        TextField(
                          controller: _ctrl,
                          maxLines: 4,
                          minLines: 2,
                          maxLength: 280,
                          textCapitalization: TextCapitalization.sentences,
                          style: context.tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            hintText: 'Your answer… only revealed when you both answer',
                            hintStyle: context.tt.bodyLarge?.copyWith(
                              color: context.cc.muted,
                              fontWeight: FontWeight.w600,
                            ),
                            counterText: '',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        Text(
                          '${_ctrl.text.length}/280',
                          style: context.tt.labelSmall?.copyWith(color: context.cc.muted, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  PillButton(
                    label: 'Lock in my answer',
                    icon: Icons.lock_outline_rounded,
                    loading: _busy,
                    onPressed: _ctrl.text.trim().isEmpty ? null : _submit,
                  ),
                ] else if (!q.revealed) ...[
                  _AnswerBubble(name: 'You', text: q.myAnswer!, mine: true, onPage: true),
                  const SizedBox(height: 12),
                  _LockedAnswer(label: 'Waiting for $name', icon: Icons.hourglass_top_rounded),
                  const SizedBox(height: 14),
                  PillButton(
                    label: 'Nudge $name',
                    icon: Icons.notifications_active_outlined,
                    onPressed: () async {
                      final ok = await runAction(context, () => ref.read(backendProvider).sendTap());
                      if (ok && context.mounted) showToast(context, 'Nudged $name 💗');
                    },
                  ),
                ] else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final (i, e) in ['😍', '😂', '🥹', '🔥', '🤯'].indexed) ...[
                        if (i > 0) const SizedBox(width: 10),
                        _ReactionTile(
                          emoji: e,
                          onTap: () async {
                            hapticSoft();
                            final ok = await runAction(context, () => ref.read(backendProvider).sendTap(kind: e));
                            if (ok && context.mounted) showToast(context, 'Reacted $e');
                          },
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  PillButton(label: 'Share this card', icon: Icons.ios_share_rounded, onPressed: _share),
                ],
                const SizedBox(height: 16),
                Text(
                  partner == null ? '' : 'A new question arrives every morning.',
                  textAlign: TextAlign.center,
                  style: context.tt.bodySmall?.copyWith(color: context.cc.muted, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// An answer: white card with a round initial avatar (pink for you, violet
/// for your partner), the name in small muted text and the answer in bold.
class _AnswerBubble extends StatelessWidget {
  const _AnswerBubble({required this.name, required this.text, this.mine = false, this.onPage = false});

  final String name;
  final String text;
  final bool mine;

  /// On the page background (white with a soft shadow) rather than on the
  /// pink card.
  final bool onPage;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // On the pink card the colours stay light in dark mode too (it is shared
    // as an image).
    final bg = onPage ? context.cc.card : Colors.white;
    final ink = onPage ? context.cs.onSurface : Brand.ink;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: onPage && !dark ? softCardShadow : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: mine ? const Color(0xFFFF8CC6) : Brand.royal),
            child: Text(
              initial,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: context.tt.labelSmall?.copyWith(
                    color: onPage ? context.cc.muted : const Color(0xFF5B5675),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: context.tt.bodyLarge?.copyWith(color: ink, fontWeight: FontWeight.w700, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Mint card standing in for the partner's hidden answer: faint text bars
/// and a white pill with a lock (Figma "Sam answered — answer to unlock").
class _LockedAnswer extends StatelessWidget {
  const _LockedAnswer({required this.label, this.icon = Icons.lock_outline_rounded});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final bar = SoftTone.mint.icon.withValues(alpha: 0.18);
    Widget line(double widthFactor) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: 10,
        decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(999)),
      ),
    );
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(color: SoftTone.mint.fill(context), borderRadius: BorderRadius.circular(22)),
        child: Stack(
          alignment: Alignment.center,
          children: [
            ExcludeSemantics(
              child: Column(
                children: [line(0.55), const SizedBox(height: 14), line(0.85), const SizedBox(height: 14), line(0.65)],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: context.cc.card,
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [BoxShadow(color: Color(0x1A0F8F80), blurRadius: 10, offset: Offset(0, 4))],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: context.cs.onSurface),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.tt.labelMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
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

/// White rounded-square reaction button with a big emoji.
class _ReactionTile extends StatelessWidget {
  const _ReactionTile({required this.emoji, required this.onTap});

  final String emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: 'React $emoji',
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: dark ? null : softCardShadow),
        child: Material(
          color: context.cc.card,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: SizedBox(
              width: 52,
              height: 48,
              child: Center(child: Text(emoji, style: const TextStyle(fontSize: 24))),
            ),
          ),
        ),
      ),
    );
  }
}

class QuestionHistoryScreen extends ConsumerWidget {
  const QuestionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final past = ref.watch(pastQuestionsProvider).value ?? const <DailyQuestion>[];
    final me = ref.watch(meProvider).value;
    final name = ref.watch(partnerNameProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Past questions')),
      body: past.isEmpty
          ? const EmptyState(
              emoji: '🗂️',
              title: 'No past questions yet',
              body: 'Answer together each day to build your collection.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(Space.m),
              itemCount: past.length,
              separatorBuilder: (_, _) => const SizedBox(height: Space.m),
              itemBuilder: (context, i) {
                final q = past[i];
                final partnerUid = q.answers.keys.firstWhere((k) => k != me?.uid, orElse: () => '');
                return CloserCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(q.date, style: context.tt.labelSmall?.copyWith(color: context.cc.muted)),
                      const SizedBox(height: 4),
                      Text(q.text, style: context.tt.titleMedium),
                      const SizedBox(height: Space.s),
                      _AnswerBubble(name: 'You', text: q.answers[me?.uid] ?? '—'),
                      const SizedBox(height: Space.s),
                      _AnswerBubble(name: name, text: q.answers[partnerUid] ?? '—'),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// Pack picker (Plus). Spicy requires the 18+ confirmation.
class QuestionPacksScreen extends ConsumerWidget {
  const QuestionPacksScreen({super.key});

  /// Outline icon and colour per pack (Figma "question packs screen").
  static (IconData, SoftTone) _look(String id) => switch (id) {
    'everyday' => (Icons.wb_sunny_outlined, SoftTone.yellow),
    'deep' => (Icons.dark_mode_outlined, SoftTone.blue),
    'long-distance' => (Icons.flight_outlined, SoftTone.mint),
    'bff' => (Icons.people_outline_rounded, SoftTone.violet),
    'spicy' => (Icons.local_fire_department_outlined, SoftTone.pink),
    _ => (Icons.style_outlined, SoftTone.violet),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plus = ref.watch(isPlusProvider);
    final mode = ref.watch(pairModeProvider);
    final current = ref.watch(todayQuestionProvider).value?.packId;
    final me = ref.watch(meProvider).value;
    final packs = questionPacks.where((p) => p.modes.contains(mode)).toList();
    final dark = Theme.of(context).brightness == Brightness.dark;

    Future<void> choose(QuestionPack p, {required bool locked}) async {
      if (locked) {
        await context.push('/paywall?from=packs');
        return;
      }
      if (p.adultsOnly && !(me?.ageConfirmed18 ?? false)) {
        final ok = await confirm(
          context,
          title: 'Are you 18 or older?',
          body: 'The Spicy pack contains mature questions for adults.',
          ok: 'I’m 18+',
        );
        if (!ok || !context.mounted) return;
        await ref.read(backendProvider).setAgeConfirmed(confirmed: true);
      }
      if (!context.mounted) return;
      final done = await runAction(context, () => ref.read(backendProvider).setQuestionPack(p.id));
      if (done && context.mounted) {
        showToast(context, '${p.title} pack selected — new questions from tomorrow (or today, if nobody answered yet)');
        context.pop();
      }
    }

    return Scaffold(
      body: Column(
        children: [
          const PlainPageHeader(title: 'Question packs'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              children: [
                // All packs in one white card, split by hairlines.
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: context.cc.card,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: dark ? null : softCardShadow,
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Column(
                      children: [
                        for (final (i, p) in packs.indexed) ...[
                          if (i > 0) Divider(height: 1, color: context.cs.outlineVariant.withValues(alpha: 0.5)),
                          _PackRow(
                            pack: p,
                            look: _look(p.id),
                            selected: current == p.id,
                            locked: p.plus && !plus,
                            onTap: () => choose(p, locked: p.plus && !plus),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const PeekingMascots(),
        ],
      ),
    );
  }
}

/// One pack: tinted icon tile, bold title (+ 18+ tag), description, a
/// lavender "N questions" pill, and a violet check / empty ring / Plus badge.
class _PackRow extends StatelessWidget {
  const _PackRow({
    required this.pack,
    required this.look,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final QuestionPack pack;
  final (IconData, SoftTone) look;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, tone) = look;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(icon: icon, tone: tone, size: 48, filled: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(pack.title, style: context.tt.titleMedium?.copyWith(fontSize: 18))),
                        if (pack.adultsOnly) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: SoftTone.pink.fill(context),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '18+',
                              style: context.tt.labelSmall?.copyWith(
                                color: SoftTone.pink.icon,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pack.description,
                      style: context.tt.bodyMedium?.copyWith(color: context.cc.muted, height: 1.35),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: SoftTone.violet.fill(context),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${pack.questions.length} questions',
                        style: context.tt.labelSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: selected
                    ? Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(color: Brand.royal, shape: BoxShape.circle),
                        child: const Icon(Icons.check_rounded, size: 17, color: Colors.white),
                      )
                    : locked
                    ? Transform.rotate(
                        angle: math.pi / 12,
                        child: const Icon(Icons.workspace_premium_rounded, color: Brand.amber),
                      )
                    : Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFC9BDF5), width: 2),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
