import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/features/send/send_screen.dart' show captureToFile;
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

/// Game lobby for "How well do you know me?" (F10).
class GamesScreen extends ConsumerWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final games = ref.watch(gamesProvider).value ?? const <Game>[];
    final me = ref.watch(authUidProvider).value;
    final name = ref.watch(partnerNameProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('How well do you know me?')),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          CloserCard(
            gradient: LinearGradient(colors: context.cc.gradient),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🎯', style: TextStyle(fontSize: 40)),
                const SizedBox(height: Space.s),
                Text('Answer 5 questions about yourself', style: context.tt.titleLarge?.copyWith(color: Colors.white)),
                const SizedBox(height: Space.xs),
                Text('$name tries to guess your answers. Then swap!', style: context.tt.bodyMedium?.copyWith(color: Colors.white70)),
                const SizedBox(height: Space.m),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: context.cc.accent),
                  onPressed: () async {
                    Game? g;
                    final ok = await runAction(context, () async => g = await ref.read(backendProvider).startGame());
                    if (ok && g != null && context.mounted) await context.push('/games/${g!.id}');
                  },
                  child: const Text('Start a new game'),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.l),
          if (games.isEmpty)
            Text('No games yet.', style: context.tt.bodyMedium?.copyWith(color: context.cc.muted))
          else
            for (final g in games)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.s),
                child: CloserCard(
                  onTap: () => context.push('/games/${g.id}'),
                  child: Row(
                    children: [
                      Text(g.status == GameStatus.done ? '🏆' : '⏳', style: const TextStyle(fontSize: 28)),
                      const SizedBox(width: Space.m),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              g.subjectUid == me ? 'About you' : 'About $name',
                              style: context.tt.titleMedium,
                            ),
                            Text(_statusText(g, me, name), style: context.tt.bodyMedium?.copyWith(color: context.cc.muted)),
                          ],
                        ),
                      ),
                      if (_isMyTurn(g, me)) CounterChip(label: 'Your turn', color: context.cc.accent),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

bool _isMyTurn(Game g, String? me) =>
    (g.status == GameStatus.subjectTurn && g.subjectUid == me) ||
    (g.status == GameStatus.guesserTurn && g.guesserUid == me);

String _statusText(Game g, String? me, String name) => switch (g.status) {
      GameStatus.subjectTurn => g.subjectUid == me ? 'Answer about yourself' : 'Waiting for $name to answer',
      GameStatus.guesserTurn => g.guesserUid == me ? 'Guess $name’s answers' : 'Waiting for $name to guess',
      GameStatus.done => 'Score ${g.score}/${g.questions.length}',
    };

class GamePlayScreen extends ConsumerStatefulWidget {
  const GamePlayScreen({required this.gameId, super.key});

  final String gameId;

  @override
  ConsumerState<GamePlayScreen> createState() => _GamePlayScreenState();
}

class _GamePlayScreenState extends ConsumerState<GamePlayScreen> {
  final _answers = <int>[];
  final _confetti = ConfettiController(duration: const Duration(seconds: 2));
  final _shareKey = GlobalKey();
  bool _busy = false;
  bool _celebrated = false;

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  Future<void> _choose(Game g, int option) async {
    hapticSoft();
    setState(() => _answers.add(option));
    if (_answers.length == g.questions.length) {
      setState(() => _busy = true);
      await runAction(context, () => ref.read(backendProvider).submitGameAnswers(g.id, List.of(_answers)));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final games = ref.watch(gamesProvider).value ?? const <Game>[];
    final g = games.where((x) => x.id == widget.gameId).firstOrNull;
    final me = ref.watch(authUidProvider).value;
    final name = ref.watch(partnerNameProvider);
    if (g == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final myTurn = _isMyTurn(g, me);
    Widget body;
    if (g.status == GameStatus.done) {
      if (!_celebrated && g.score >= 3) {
        _celebrated = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _confetti.play());
      }
      body = _results(g, me, name);
    } else if (!myTurn || _busy || _answers.length >= g.questions.length) {
      body = EmptyState(
        emoji: '⏳',
        title: _busy ? 'Sending…' : 'Waiting for $name',
        body: _statusText(g, me, name),
      );
    } else {
      final i = _answers.length;
      final q = g.questions[i];
      final guessing = g.guesserUid == me;
      body = ListView(
        key: ValueKey(i),
        padding: const EdgeInsets.all(Space.m),
        children: [
          LinearProgressIndicator(value: i / g.questions.length, borderRadius: BorderRadius.circular(8)),
          const SizedBox(height: Space.l),
          Text(guessing ? 'What would $name say?' : 'About you', style: context.tt.labelLarge?.copyWith(color: context.cc.muted)),
          const SizedBox(height: Space.s),
          Text(q.text, style: context.tt.headlineSmall),
          const SizedBox(height: Space.l),
          for (var o = 0; o < q.options.length; o++)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: CloserButton(label: q.options[o], kind: CloserButtonKind.secondary, onPressed: () => _choose(g, o)),
            ),
        ],
      ).animate().fadeIn(duration: 250.ms).slideX(begin: 0.08);
    }
    return Scaffold(
      appBar: AppBar(title: Text(g.subjectUid == me ? 'About you' : 'About $name')),
      body: Stack(
        children: [
          body,
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(confettiController: _confetti, blastDirectionality: BlastDirectionality.explosive),
          ),
        ],
      ),
    );
  }

  Widget _results(Game g, String? me, String name) {
    final guesserName = g.guesserUid == me ? 'You' : name;
    final verdict = switch (g.score) {
      5 => 'Soulmates! 💞',
      4 => 'Nearly perfect ✨',
      3 => 'Pretty close 😊',
      2 => 'Room to learn 😅',
      _ => 'Time for a deep talk 🙈',
    };
    return ListView(
      padding: const EdgeInsets.all(Space.m),
      children: [
        RepaintBoundary(
          key: _shareKey,
          child: Container(
            padding: const EdgeInsets.all(Space.l),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: context.cc.gradient),
              borderRadius: BorderRadius.circular(Radii.card),
            ),
            child: Column(
              children: [
                Text('$guesserName scored', style: context.tt.titleMedium?.copyWith(color: Colors.white70)),
                Text('${g.score}/${g.questions.length}', style: context.tt.displaySmall?.copyWith(color: Colors.white, fontSize: 56))
                    .animate()
                    .scale(duration: 600.ms, curve: Curves.elasticOut),
                Text(verdict, style: context.tt.titleLarge?.copyWith(color: Colors.white)),
                const SizedBox(height: Space.s),
                Text('How well do you know me? · closer.app', style: context.tt.labelSmall?.copyWith(color: Colors.white60)),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.l),
        for (var i = 0; i < g.questions.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: CloserCard(
              child: Row(
                children: [
                  Icon(
                    g.guesses[i] == g.subjectAnswers[i] ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    color: g.guesses[i] == g.subjectAnswers[i] ? Brand.green : context.cs.error,
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.questions[i].text, style: context.tt.titleSmall),
                        Text(
                          'Answer: ${g.questions[i].options[g.subjectAnswers[i]]}'
                          '${g.guesses[i] == g.subjectAnswers[i] ? '' : ' · Guess: ${g.questions[i].options[g.guesses[i]]}'}',
                          style: context.tt.bodyMedium?.copyWith(color: context.cc.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: Space.m),
        CloserButton(
          label: 'Share result',
          icon: Icons.ios_share_rounded,
          kind: CloserButtonKind.secondary,
          onPressed: () async {
            final path = await captureToFile(_shareKey, pixelRatio: 2.5);
            await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
          },
        ),
        const SizedBox(height: Space.s),
        CloserButton(
          label: 'Play again — your turn to answer',
          onPressed: () async {
            Game? next;
            final ok = await runAction(context, () async => next = await ref.read(backendProvider).startGame());
            if (ok && next != null && mounted) context.pushReplacement('/games/${next!.id}');
          },
        ),
      ],
    );
  }
}
