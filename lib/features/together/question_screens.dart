import 'dart:math' as math;

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/data/content.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/features/send/send_screen.dart' show captureToFile;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
    await SharePlus.instance.share(ShareParams(files: [XFile(path)], text: 'Our question of the day on Closer 💌'));
  }

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(todayQuestionProvider).value;
    final me = ref.watch(meProvider).value;
    final partner = ref.watch(partnerProvider).value;
    final name = ref.watch(partnerNameProvider);
    if (q == null || me == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final answered = q.myAnswer != null;
    final partnerUid = q.answeredBy.firstWhere((u) => u != me.uid, orElse: () => '');
    final partnerAnswered = partnerUid.isNotEmpty;
    final pack = packById(q.packId);

    return Scaffold(
      appBar: AppBar(
        title: Text('${pack.emoji} ${pack.title}'),
        actions: [
          IconButton(tooltip: 'Question packs', icon: const Icon(Icons.style_rounded), onPressed: () => context.push('/packs')),
          IconButton(tooltip: 'History', icon: const Icon(Icons.history_rounded), onPressed: () => context.push('/question/history')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          RepaintBoundary(
            key: _shareKey,
            child: Container(
              padding: const EdgeInsets.all(Space.l),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: context.cc.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(Radii.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('QUESTION OF THE DAY', style: context.tt.labelSmall?.copyWith(color: Colors.white70, letterSpacing: 1.2)),
                  const SizedBox(height: Space.s),
                  Text(q.text, style: context.tt.headlineSmall?.copyWith(color: Colors.white)),
                  if (q.revealed) ...[
                    const SizedBox(height: Space.l),
                    _AnswerBubble(name: me.displayName, text: q.answers[me.uid] ?? q.myAnswer ?? '', onGradient: true),
                    const SizedBox(height: Space.s),
                    _AnswerBubble(name: name, text: q.answers[partnerUid] ?? '', onGradient: true)
                        .animate()
                        .flipV(begin: -0.5, duration: 600.ms, curve: Curves.easeOutBack),
                    const SizedBox(height: Space.m),
                    Text('closer.app', style: context.tt.labelSmall?.copyWith(color: Colors.white60)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: Space.l),
          if (!answered) ...[
            if (partnerAnswered)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.m),
                child: LockedCard(
                  label: '$name answered — answer to unlock',
                  child: _AnswerBubble(name: name, text: 'This is a secret answer you can’t read yet, nice try'),
                ),
              ),
            TextField(
              controller: _ctrl,
              maxLines: 4,
              minLines: 2,
              maxLength: 280,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Your answer… only revealed when you both answer'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Space.s),
            CloserButton(label: 'Lock in my answer', icon: Icons.lock_rounded, loading: _busy, onPressed: _ctrl.text.trim().isEmpty ? null : _submit),
          ] else if (!q.revealed) ...[
            _AnswerBubble(name: 'You', text: q.myAnswer!),
            const SizedBox(height: Space.m),
            LockedCard(
              label: 'Waiting for $name',
              icon: Icons.hourglass_top_rounded,
              child: _AnswerBubble(name: name, text: 'Their answer will appear here as soon as they answer'),
            ),
            const SizedBox(height: Space.m),
            CloserButton(
              label: 'Nudge $name',
              kind: CloserButtonKind.secondary,
              icon: Icons.notifications_active_rounded,
              onPressed: () async {
                final ok = await runAction(context, () => ref.read(backendProvider).sendTap());
                if (ok && context.mounted) showToast(context, 'Nudged $name 💗');
              },
            ),
          ] else ...[
            Wrap(
              alignment: WrapAlignment.center,
              spacing: Space.s,
              children: [
                for (final e in ['😍', '😂', '🥹', '🔥', '🤯'])
                  ActionChip(
                    label: Text(e, style: const TextStyle(fontSize: 20)),
                    onPressed: () async {
                      hapticSoft();
                      final ok = await runAction(context, () => ref.read(backendProvider).sendTap(kind: e));
                      if (ok && context.mounted) showToast(context, 'Reacted $e');
                    },
                  ),
              ],
            ),
            const SizedBox(height: Space.m),
            CloserButton(label: 'Share this card', icon: Icons.ios_share_rounded, kind: CloserButtonKind.secondary, onPressed: _share),
          ],
          const SizedBox(height: Space.l),
          Text(
            partner == null ? '' : 'A new question arrives every morning.',
            textAlign: TextAlign.center,
            style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
          ),
        ],
      ),
    );
  }
}

class _AnswerBubble extends StatelessWidget {
  const _AnswerBubble({required this.name, required this.text, this.onGradient = false});

  final String name;
  final String text;
  final bool onGradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(
        color: onGradient ? Colors.white.withValues(alpha: 0.92) : context.cc.card,
        borderRadius: BorderRadius.circular(Radii.tile),
        border: onGradient ? null : Border.all(color: context.cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: context.tt.labelMedium?.copyWith(color: onGradient ? Brand.grey700 : context.cc.muted)),
          const SizedBox(height: 4),
          Text(text, style: context.tt.bodyLarge?.copyWith(color: onGradient ? Brand.ink : null)),
        ],
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
          ? const EmptyState(emoji: '🗂️', title: 'No past questions yet', body: 'Answer together each day to build your collection.')
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plus = ref.watch(isPlusProvider);
    final mode = ref.watch(pairModeProvider);
    final current = ref.watch(todayQuestionProvider).value?.packId;
    final me = ref.watch(meProvider).value;
    final packs = questionPacks.where((p) => p.modes.contains(mode)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Question packs')),
      body: ListView.separated(
        padding: const EdgeInsets.all(Space.m),
        itemCount: packs.length,
        separatorBuilder: (_, _) => const SizedBox(height: Space.m),
        itemBuilder: (context, i) {
          final p = packs[i];
          final locked = p.plus && !plus;
          return CloserCard(
            onTap: () async {
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
            },
            child: Row(
              children: [
                Text(p.emoji, style: const TextStyle(fontSize: 36)),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(p.title, style: context.tt.titleMedium),
                          if (p.adultsOnly) ...[const SizedBox(width: 6), const CounterChip(label: '18+')],
                        ],
                      ),
                      Text('${p.description} · ${p.questions.length} questions', style: context.tt.bodyMedium?.copyWith(color: context.cc.muted)),
                    ],
                  ),
                ),
                if (current == p.id)
                  Icon(Icons.check_circle_rounded, color: context.cc.accent)
                else if (locked)
                  Transform.rotate(angle: math.pi / 12, child: const Icon(Icons.workspace_premium_rounded, color: Brand.amber)),
              ],
            ),
          );
        },
      ),
    );
  }
}
