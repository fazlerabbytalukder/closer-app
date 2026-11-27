import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/soft_ui.dart';
import 'package:closer_app/features/send/send_screen.dart' show captureToFile;
import 'package:confetti/confetti.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

/// Pink of the game cards (Figma "know me screen").
const _gamePink = Color(0xFFFF9CCB);

/// Deep pink for icons and the "Your turn" text.
const _deepPink = Color(0xFFD6246E);

/// Pink card with rounded corners and a soft pink glow.
class _PinkCard extends StatelessWidget {
  const _PinkCard({required this.child, this.padding = const EdgeInsets.fromLTRB(18, 18, 18, 18)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _gamePink,
        borderRadius: BorderRadius.circular(28),
        boxShadow: dark
            ? null
            : const [BoxShadow(color: Color(0x40FF6FAE), blurRadius: 24, offset: Offset(0, 12), spreadRadius: -8)],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// White rounded card with the soft violet shadow.
class _WhiteCard extends StatelessWidget {
  const _WhiteCard({required this.child, this.onTap, this.padding = const EdgeInsets.all(14)});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: dark ? null : softCardShadow),
      child: Material(
        color: context.cc.card,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// One result line: mint ✓ / red ✕ circle, the question, then the answer
/// (and the wrong guess, struck through).
class _AnswerRow extends StatelessWidget {
  const _AnswerRow({required this.question, required this.answer, required this.guess});

  final String question;
  final String answer;

  /// The wrong guess, or null when it was right.
  final String? guess;

  @override
  Widget build(BuildContext context) {
    final right = guess == null;
    final tone = right ? SoftTone.mint : SoftTone.red;
    final small = context.tt.bodySmall?.copyWith(fontWeight: FontWeight.w700);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: tone.fill(context), shape: BoxShape.circle),
            child: Icon(right ? Icons.check_rounded : Icons.close_rounded, size: 18, color: tone.icon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(question, style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.3)),
                const SizedBox(height: 3),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: answer,
                        style: small?.copyWith(color: tone.icon),
                      ),
                      if (!right) ...[
                        TextSpan(
                          text: '  ·  ',
                          style: small?.copyWith(color: context.cc.muted),
                        ),
                        TextSpan(
                          text: 'Guessed $guess',
                          style: small?.copyWith(color: context.cc.muted, decoration: TextDecoration.lineThrough),
                        ),
                      ],
                    ],
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

/// Game lobby for "How well do you know me?" (F10).
class GamesScreen extends ConsumerWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final games = ref.watch(gamesProvider).value ?? const <Game>[];
    final me = ref.watch(authUidProvider).value;
    final name = ref.watch(partnerNameProvider);
    return Scaffold(
      body: Column(
        children: [
          const PlainPageHeader(title: 'How well do you know me?', titleSize: 21),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
              children: [
                // Pink hero: target icon, title, text, violet button, mascot.
                _PinkCard(
                  padding: EdgeInsets.zero,
                  child: Stack(
                    children: [
                      Positioned(
                        right: -6,
                        bottom: -24,
                        child: Image.asset('assets/together/streak_mascot.png', width: 118, height: 131),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                              child: const Icon(Icons.track_changes_rounded, color: _deepPink, size: 26),
                            ),
                            const SizedBox(height: 14),
                            Padding(
                              padding: const EdgeInsets.only(right: 100),
                              child: Text(
                                'Answer 5 questions about yourself',
                                style: context.tt.headlineSmall?.copyWith(color: Brand.ink, fontSize: 24, height: 1.2),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.only(right: 90),
                              child: Text(
                                '$name tries to guess your answers. Then swap!',
                                style: context.tt.bodySmall?.copyWith(color: Brand.ink, fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: 180,
                              child: PillButton(
                                label: 'Start a new game',
                                height: 50,
                                onPressed: () async {
                                  Game? g;
                                  final ok = await runAction(
                                    context,
                                    () async => g = await ref.read(backendProvider).startGame(),
                                  );
                                  if (ok && g != null && context.mounted) await context.push('/games/${g!.id}');
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (games.isEmpty)
                  Text(
                    'No games yet.',
                    textAlign: TextAlign.center,
                    style: context.tt.bodyMedium?.copyWith(color: context.cc.muted, fontWeight: FontWeight.w600),
                  )
                else
                  for (final g in games)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _WhiteCard(
                        onTap: () => context.push('/games/${g.id}'),
                        child: Row(
                          children: [
                            IconTile(
                              icon: g.status == GameStatus.done
                                  ? Icons.emoji_events_outlined
                                  : Icons.hourglass_empty_rounded,
                              tone: g.status == GameStatus.done ? SoftTone.mint : SoftTone.yellow,
                              size: 44,
                              filled: true,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    g.subjectUid == me ? 'About you' : 'About $name',
                                    style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  Text(
                                    _statusText(g, me, name),
                                    style: context.tt.bodySmall?.copyWith(
                                      color: context.cc.muted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_isMyTurn(g, me))
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: SoftTone.pink.fill(context),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Your turn',
                                  style: context.tt.labelSmall?.copyWith(color: _deepPink, fontWeight: FontWeight.w800),
                                ),
                              ),
                          ],
                        ),
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
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final myTurn = _isMyTurn(g, me);
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget body;
    if (g.status == GameStatus.done) {
      if (!_celebrated && g.score >= 3) {
        _celebrated = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _confetti.play());
      }
      body = _results(g, me, name);
    } else if (!myTurn || _busy || _answers.length >= g.questions.length) {
      body = EmptyState(emoji: '⏳', title: _busy ? 'Sending…' : 'Waiting for $name', body: _statusText(g, me, name));
    } else {
      final i = _answers.length;
      final q = g.questions[i];
      final guessing = g.guesserUid == me;
      body = ListView(
        key: ValueKey(i),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          // Violet progress bar on lavender (Figma "quiz pink screen").
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: (i + 1) / g.questions.length,
              minHeight: 7,
              color: Brand.royal,
              backgroundColor: dark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFEDE7FF),
            ),
          ),
          const SizedBox(height: 14),
          // Pink question card with a mascot peeking in.
          _PinkCard(
            padding: EdgeInsets.zero,
            child: Stack(
              children: [
                Positioned(
                  right: 2,
                  bottom: -8,
                  child: Image.asset('assets/together/streak_mascot.png', width: 72, height: 80),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 84, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        guessing ? 'What would $name say?' : 'About you',
                        style: context.tt.labelMedium?.copyWith(color: Brand.ink, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        q.text,
                        style: context.tt.headlineSmall?.copyWith(color: Brand.ink, fontSize: 22, height: 1.25),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (var o = 0; o < q.options.length; o++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _WhiteCard(
                onTap: () => _choose(g, o),
                padding: const EdgeInsets.fromLTRB(16, 15, 14, 15),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(q.options[o], style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFC9BDF5), width: 2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ).animate().fadeIn(duration: 250.ms).slideX(begin: 0.08);
    }
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              PlainPageHeader(title: g.subjectUid == me ? 'About you' : 'About $name'),
              Expanded(child: body),
            ],
          ),
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
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        // Shared image: pink card, score in deep pink, two soft circles.
        RepaintBoundary(
          key: _shareKey,
          child: _PinkCard(
            padding: EdgeInsets.zero,
            child: Stack(
              children: [
                Positioned(
                  left: -34,
                  top: -34,
                  child: Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), shape: BoxShape.circle),
                  ),
                ),
                Positioned(
                  right: -26,
                  bottom: -30,
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
                  child: Center(
                    child: Column(
                      children: [
                        Text(
                          '$guesserName scored',
                          style: context.tt.titleSmall?.copyWith(color: Brand.ink, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${g.score}/${g.questions.length}',
                          style: context.tt.displaySmall?.copyWith(
                            color: _deepPink,
                            fontSize: 56,
                            fontWeight: FontWeight.w700,
                          ),
                        ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
                        Text(verdict, style: context.tt.headlineSmall?.copyWith(color: Brand.ink, fontSize: 22)),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                          child: Text(
                            'How well do you know me? · Duosy',
                            style: context.tt.labelSmall?.copyWith(color: _deepPink, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: Text('The answers', style: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        ),
        // All answers in one white card, split by hairlines.
        _WhiteCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < g.questions.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: context.cs.outlineVariant.withValues(alpha: 0.5),
                  ),
                _AnswerRow(
                  question: g.questions[i].text,
                  answer: g.questions[i].options[g.subjectAnswers[i]],
                  guess: g.guesses[i] == g.subjectAnswers[i] ? null : g.questions[i].options[g.guesses[i]],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        PillButton(
          label: 'Share result',
          icon: Icons.ios_share_rounded,
          glow: false,
          color: SoftTone.violet.fill(context),
          foreground: Theme.of(context).brightness == Brightness.dark ? Colors.white : Brand.royal,
          onPressed: () async {
            final path = await captureToFile(_shareKey, pixelRatio: 2.5);
            await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
          },
        ),
        const SizedBox(height: 10),
        PillButton(
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
