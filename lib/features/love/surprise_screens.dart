import 'dart:math' as math;

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/features/love/love_widgets.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

typedef _TypeInfo = ({SurpriseType type, String emoji, String title, String subtitle});

const _types = <_TypeInfo>[
  (type: SurpriseType.note, emoji: '🤫', title: 'Secret note', subtitle: 'A few words, wrapped up'),
  (type: SurpriseType.photo, emoji: '📸', title: 'Surprise photo', subtitle: 'A picture they’ll unwrap'),
  (type: SurpriseType.compliment, emoji: '🌟', title: 'Compliment', subtitle: 'Make their day'),
  (type: SurpriseType.gift, emoji: '🎁', title: 'Virtual gift', subtitle: 'Flowers, cake, a teddy…'),
];

_TypeInfo _info(SurpriseType? t) => _types.firstWhere((i) => i.type == t, orElse: () => _types.first);

/// "Surprise me": send unexpected notes, photos, compliments and gifts;
/// unwrap the ones you get.
class SurprisesScreen extends ConsumerWidget {
  const SurprisesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authUidProvider).value;
    final name = ref.watch(partnerNameProvider);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final all = (ref.watch(capsulesProvider).value ?? const <Capsule>[]).where((c) => c.kind == CapsuleKind.surprise).toList();
    final forMe = all.where((c) => c.forUid == me).toList();
    final toUnwrap = forMe.where((c) => c.isUnlocked(now) && c.openedAt == null).toList();
    final coming = forMe.where((c) => !c.isUnlocked(now)).length;
    final opened = forMe.where((c) => c.openedAt != null).toList();
    final sent = all.where((c) => c.authorId == me).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Surprise me')),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          Text('Surprise $name', style: context.tt.titleLarge),
          const SizedBox(height: Space.s),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: Space.s,
            crossAxisSpacing: Space.s,
            childAspectRatio: 1.35,
            children: [
              for (final t in _types)
                CloserCard(
                  onTap: () => context.push('/surprises/new?type=${t.type.name}'),
                  padding: const EdgeInsets.all(Space.s + 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.emoji, style: const TextStyle(fontSize: 30)),
                      const Spacer(),
                      Text(t.title, style: context.tt.titleSmall),
                      Text(t.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall?.copyWith(color: context.cc.muted)),
                    ],
                  ),
                ),
            ],
          ),
          if (toUnwrap.isNotEmpty || coming > 0) const SectionHeader('For you'),
          for (final c in toUnwrap)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: CloserCard(
                onTap: () => unwrapSurprise(context, ref, c),
                gradient: const LinearGradient(colors: [Color(0xFFFFE6EF), Color(0xFFFFF3D6)]),
                child: Row(
                  children: [
                    const GiftBox(size: 44),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$name sent you a surprise!', style: context.tt.titleMedium?.copyWith(color: Brand.ink)),
                          Text('Tap to unwrap', style: context.tt.bodyMedium?.copyWith(color: Brand.grey700)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (coming > 0)
            CloserCard(
              color: context.cc.secondaryTint,
              child: Row(
                children: [
                  const Text('👀', style: TextStyle(fontSize: 28)),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Text(
                      coming == 1 ? 'Something is on its way to you…' : '$coming surprises are on their way…',
                      style: context.tt.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
          if (opened.isNotEmpty) const SectionHeader('Unwrapped'),
          for (final c in opened) _OpenedTile(capsule: c, label: 'From $name'),
          if (sent.isNotEmpty) const SectionHeader('Sent by you'),
          for (final c in sent)
            _OpenedTile(
              capsule: c,
              label: c.openedAt != null
                  ? '$name unwrapped it 💗'
                  : c.isUnlocked(now)
                      ? 'Delivered ${DateFormat('d MMM, HH:mm').format(c.unlockAt)}'
                      : 'Arrives as a surprise ${opensIn(c.unlockAt, now).replaceFirst('Opens ', '')}',
            ),
          const SizedBox(height: Space.l),
        ],
      ),
    );
  }
}

class _OpenedTile extends StatelessWidget {
  const _OpenedTile({required this.capsule, required this.label});

  final Capsule capsule;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = _info(capsule.surpriseType);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: CloserCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: context.tt.bodySmall?.copyWith(color: context.cc.muted)),
                  const SizedBox(height: 4),
                  CapsuleBody(capsule: capsule, textStyle: context.tt.bodyLarge),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen unwrap: the box shakes, bursts open with confetti, and the
/// surprise appears.
Future<void> unwrapSurprise(BuildContext context, WidgetRef ref, Capsule c) async {
  await Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black54,
      pageBuilder: (_, _, _) => _UnwrapView(capsule: c),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ),
  );
}

class _UnwrapView extends ConsumerStatefulWidget {
  const _UnwrapView({required this.capsule});

  final Capsule capsule;

  @override
  ConsumerState<_UnwrapView> createState() => _UnwrapViewState();
}

class _UnwrapViewState extends ConsumerState<_UnwrapView> {
  final _confetti = ConfettiController(duration: const Duration(seconds: 2));
  bool _open = false;

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  Future<void> _unwrap() async {
    if (_open) return;
    hapticMedium();
    setState(() => _open = true);
    _confetti.play();
    await ref.read(backendProvider).markCapsuleOpened(widget.capsule.id);
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(partnerNameProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(child: GestureDetector(onTap: () => Navigator.pop(context))),
            Padding(
              padding: const EdgeInsets.all(Space.l),
              child: AnimatedSwitcher(
                duration: 450.ms,
                transitionBuilder: (child, a) => ScaleTransition(scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack), child: child),
                child: _open
                    ? Container(
                        key: const ValueKey('open'),
                        padding: const EdgeInsets.all(Space.l),
                        decoration: BoxDecoration(color: context.cc.card, borderRadius: BorderRadius.circular(Radii.card)),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('From $name 💗', style: context.tt.titleMedium?.copyWith(color: context.cc.muted)),
                            const SizedBox(height: Space.m),
                            CapsuleBody(capsule: widget.capsule, center: true, textStyle: context.tt.titleLarge?.copyWith(height: 1.35)),
                            const SizedBox(height: Space.l),
                            CloserButton(
                              label: 'Send a heart back',
                              icon: Icons.favorite_rounded,
                              kind: CloserButtonKind.accent,
                              onPressed: () async {
                                final ok = await runAction(context, () => ref.read(backendProvider).sendTap(kind: 'love'));
                                if (ok && context.mounted) Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
                      )
                    : GestureDetector(
                        key: const ValueKey('box'),
                        onTap: _unwrap,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const GiftBox(size: 140),
                            const SizedBox(height: Space.m),
                            Text('Tap to unwrap', style: context.tt.titleLarge?.copyWith(color: Colors.white)),
                          ],
                        ),
                      ),
              ),
            ),
            Align(
              child: ConfettiWidget(
                confettiController: _confetti,
                blastDirectionality: BlastDirectionality.explosive,
                numberOfParticles: 30,
                colors: const [Brand.pink, Brand.purple, Brand.amber, Colors.white],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Create a surprise of one type, now or at a random moment later.
class NewSurpriseScreen extends ConsumerStatefulWidget {
  const NewSurpriseScreen({required this.type, super.key});

  final SurpriseType type;

  @override
  ConsumerState<NewSurpriseScreen> createState() => _NewSurpriseScreenState();
}

class _NewSurpriseScreenState extends ConsumerState<NewSurpriseScreen> {
  final _text = TextEditingController();
  String? _photo;
  String? _gift;
  bool _later = false;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    final now = DateTime.now();
    // "Surprise them": a random moment in the next 24 h, never in the middle
    // of the night (09:00–22:00 their side, assuming the same timezone).
    var at = now;
    if (_later) {
      final r = math.Random();
      for (var i = 0; i < 20; i++) {
        final t = now.add(Duration(minutes: 30 + r.nextInt(24 * 60 - 30)));
        if (t.hour >= 9 && t.hour < 22) {
          at = t;
          break;
        }
      }
      if (at == now) at = now.add(const Duration(hours: 3));
    }
    final backend = ref.read(backendProvider);
    final ok = await runAction(context, () async {
      final photo = _photo == null ? null : await backend.uploadPhoto(_photo!);
      await backend.sendCapsule(
        Capsule(
          id: '',
          kind: CapsuleKind.surprise,
          authorId: '',
          forUid: '',
          surpriseType: widget.type,
          createdAt: now,
          unlockAt: at,
        ),
        CapsuleContent(text: _text.text.trim(), photoPath: photo, giftId: _gift),
      );
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      hapticMedium();
      showToast(context, _later ? 'Scheduled 🤫 They won’t see it coming' : 'Surprise sent 🎁');
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(partnerNameProvider);
    final t = _info(widget.type);
    return Scaffold(
      appBar: AppBar(title: Text('${t.emoji} ${t.title}')),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          ...switch (widget.type) {
            SurpriseType.note => [
                TextField(
                  controller: _text,
                  minLines: 4,
                  maxLines: 10,
                  maxLength: 500,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(hintText: 'A secret note for $name…'),
                ),
              ],
            SurpriseType.photo => [
                PhotoField(path: _photo, onChanged: (p) => setState(() => _photo = p), label: 'Pick a photo'),
                const SizedBox(height: Space.s),
                TextField(
                  controller: _text,
                  maxLength: 200,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Add a message (optional)'),
                ),
              ],
            SurpriseType.compliment => [
                Text('Pick one, or write your own', style: context.tt.titleSmall),
                const SizedBox(height: Space.s),
                for (final c in compliments)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ChoiceChip(
                      label: Text(c, softWrap: true),
                      selected: _text.text == c,
                      onSelected: (_) => setState(() => _text.text = c),
                    ),
                  ),
                const SizedBox(height: Space.s),
                TextField(
                  controller: _text,
                  maxLength: 300,
                  maxLines: 3,
                  minLines: 1,
                  onChanged: (_) => setState(() {}),
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Your own compliment'),
                ),
              ],
            SurpriseType.gift => [
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    for (final g in VirtualGift.all)
                      Semantics(
                        button: true,
                        selected: _gift == g.id,
                        label: g.name,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(Radii.small + 4),
                          onTap: () => setState(() => _gift = g.id),
                          child: AnimatedContainer(
                            duration: 200.ms,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _gift == g.id ? context.cc.accentTint : context.cc.card,
                              borderRadius: BorderRadius.circular(Radii.small + 4),
                              border: Border.all(color: _gift == g.id ? context.cc.accent : Colors.transparent, width: 2),
                            ),
                            child: AnimatedScale(
                              scale: _gift == g.id ? 1.2 : 1,
                              duration: 200.ms,
                              child: Text(g.emoji, style: const TextStyle(fontSize: 34)),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (VirtualGift.byId(_gift) case final g?) ...[
                  const SizedBox(height: Space.s),
                  Text(g.name, textAlign: TextAlign.center, style: context.tt.titleMedium),
                ],
                const SizedBox(height: Space.s),
                TextField(
                  controller: _text,
                  maxLength: 200,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Add a message (optional)'),
                ),
              ],
          },
          const SectionHeader('When?'),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Right now'), icon: Icon(Icons.bolt_rounded)),
              ButtonSegment(value: true, label: Text('Surprise them'), icon: Icon(Icons.casino_rounded)),
            ],
            selected: {_later},
            onSelectionChanged: (v) => setState(() => _later = v.first),
          ),
          const SizedBox(height: Space.xs),
          Text(
            _later ? 'It arrives at a random moment in the next 24 hours. $name won’t know when.' : '$name gets it straight away.',
            style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
          ),
          const SizedBox(height: Space.l),
          CloserButton(
            label: _later ? 'Schedule the surprise' : 'Send the surprise',
            icon: Icons.card_giftcard_rounded,
            kind: CloserButtonKind.accent,
            loading: _busy,
            onPressed: _send,
          ),
        ],
      ),
    );
  }
}
