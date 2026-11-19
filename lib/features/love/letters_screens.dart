import 'dart:math' as math;

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/features/love/love_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// Letters from the future: write now, they open on a date you choose.
class LettersScreen extends ConsumerWidget {
  const LettersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authUidProvider).value;
    final name = ref.watch(partnerNameProvider);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final letters = (ref.watch(capsulesProvider).value ?? const <Capsule>[]).where((c) => c.kind == CapsuleKind.letter).toList();
    final forMe = letters.where((c) => c.forUid == me).toList()..sort((a, b) => a.unlockAt.compareTo(b.unlockAt));
    final byMe = letters.where((c) => c.authorId == me).toList()..sort((a, b) => a.unlockAt.compareTo(b.unlockAt));
    // Ready ones first, then sealed by date, then already-read ones.
    final ready = forMe.where((c) => c.isUnlocked(now) && c.openedAt == null).toList();
    final sealed = forMe.where((c) => !c.isUnlocked(now)).toList();
    final read = forMe.where((c) => c.openedAt != null).toList().reversed.toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Letters from the future')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/letters/write'),
        icon: const Icon(Icons.edit_rounded),
        label: const Text('Write a letter'),
      ),
      body: letters.isEmpty
          ? EmptyState(
              emoji: '💌',
              title: 'Write to the future',
              body: 'Seal a letter, a photo or a promise for $name. It opens on the day you choose: an anniversary, a trip, or just a random Tuesday.',
              action: 'Write a letter',
              onAction: () => context.push('/letters/write'),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, 100),
              children: [
                if (forMe.isNotEmpty) SectionHeader('For you from $name'),
                for (final c in [...ready, ...sealed, ...read])
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.s),
                    child: EnvelopeCard(
                      title: c.title.isEmpty ? 'A letter from $name' : c.title,
                      subtitle: c.openedAt != null
                          ? 'Opened ${DateFormat('d MMM yyyy').format(c.openedAt!)}'
                          : opensIn(c.unlockAt, now),
                      ready: c.isUnlocked(now),
                      opened: c.openedAt != null,
                      onTap: () => context.push('/letters/${c.id}'),
                    ),
                  ),
                if (byMe.isNotEmpty) const SectionHeader('Written by you'),
                for (final c in byMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.s),
                    child: EnvelopeCard(
                      title: c.title.isEmpty ? 'A letter for $name' : c.title,
                      subtitle: c.openedAt != null
                          ? '$name read it ${DateFormat('d MMM').format(c.openedAt!)} 💗'
                          : c.isUnlocked(now)
                              ? 'Delivered — waiting for $name to open it'
                              : opensIn(c.unlockAt, now).replaceFirst('Opens', 'Opens for $name'),
                      opened: c.openedAt != null,
                      onTap: () => context.push('/letters/${c.id}'),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Write and seal a letter.
class WriteLetterScreen extends ConsumerStatefulWidget {
  const WriteLetterScreen({super.key});

  @override
  ConsumerState<WriteLetterScreen> createState() => _WriteLetterScreenState();
}

typedef _When = ({String label, DateTime at});

class _WriteLetterScreenState extends ConsumerState<WriteLetterScreen> {
  final _title = TextEditingController();
  final _text = TextEditingController();
  String? _photo;
  DateTime? _unlockAt;
  String? _whenLabel;
  bool _busy = false;

  static const _titles = [
    'Open when you miss me',
    'Open when you’re sad',
    'Open when you can’t sleep',
    'Open on our anniversary',
    'Open when you need a laugh',
    'Open on your birthday',
  ];

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  DateTime _at9(DateTime d) => DateTime(d.year, d.month, d.day, 9);

  List<_When> _options(Pair? pair, List<Countdown> countdowns) {
    final now = DateTime.now();
    final out = <_When>[
      (label: 'Tomorrow', at: _at9(now.add(const Duration(days: 1)))),
      (label: 'In a week', at: _at9(now.add(const Duration(days: 7)))),
      (label: 'In a month', at: _at9(DateTime(now.year, now.month + 1, now.day))),
      (label: 'In a year', at: _at9(DateTime(now.year + 1, now.month, now.day))),
    ];
    final a = pair?.anniversary;
    if (a != null) {
      var next = DateTime(now.year, a.month, a.day, 9);
      if (!next.isAfter(now)) next = DateTime(now.year + 1, a.month, a.day, 9);
      out.add((label: 'Our anniversary 💞', at: next));
    }
    for (final c in countdowns.take(3)) {
      final d = c.nextOccurrence(now);
      if (d.isAfter(now)) out.add((label: '${c.emoji} ${c.title}', at: c.hasTime ? d : _at9(d)));
    }
    return out;
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: DateTime(now.year + 20),
      helpText: 'When should it open?',
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
    if (!mounted) return;
    final at = DateTime(day.year, day.month, day.day, time?.hour ?? 9, time?.minute ?? 0);
    if (!at.isAfter(now)) {
      showToast(context, 'Pick a moment in the future');
      return;
    }
    setState(() {
      _unlockAt = at;
      _whenLabel = 'custom';
    });
  }

  Future<void> _seal() async {
    final at = _unlockAt;
    if (at == null) {
      showToast(context, 'Choose when it opens');
      return;
    }
    setState(() => _busy = true);
    final backend = ref.read(backendProvider);
    final ok = await runAction(context, () async {
      final photo = _photo == null ? null : await backend.uploadPhoto(_photo!);
      await backend.sendCapsule(
        Capsule(
          id: '',
          kind: CapsuleKind.letter,
          authorId: '',
          forUid: '',
          title: _title.text.trim(),
          createdAt: DateTime.now(),
          unlockAt: at,
        ),
        CapsuleContent(text: _text.text.trim(), photoPath: photo),
      );
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      hapticMedium();
      showToast(context, 'Sealed 💌 ${opensIn(at, DateTime.now()).toLowerCase()}');
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(partnerNameProvider);
    final pair = ref.watch(pairProvider).value;
    final countdowns = ref.watch(countdownsProvider).value ?? const <Countdown>[];
    final options = _options(pair, countdowns);

    return Scaffold(
      appBar: AppBar(title: Text('A letter for $name')),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          TextField(
            controller: _title,
            maxLength: Capsule.maxTitle,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'On the envelope', hintText: 'Open when you miss me'),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in _titles) ActionChip(label: Text(t), onPressed: () => setState(() => _title.text = t)),
            ],
          ),
          const SizedBox(height: Space.m),
          Container(
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBF5),
              borderRadius: BorderRadius.circular(Radii.card),
              border: Border.all(color: const Color(0xFFF0DCC8)),
            ),
            child: TextField(
              controller: _text,
              minLines: 8,
              maxLines: 20,
              maxLength: CapsuleContent.maxText,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontFamily: 'Nunito', fontSize: 17, height: 1.5, color: Brand.ink),
              decoration: InputDecoration(
                border: InputBorder.none,
                filled: false,
                hintText: 'Dear $name,\n\n',
                hintStyle: const TextStyle(color: Brand.grey500),
              ),
            ),
          ),
          const SizedBox(height: Space.s),
          PhotoField(path: _photo, onChanged: (p) => setState(() => _photo = p), label: 'Tuck a photo inside'),
          const SectionHeader('When does it open?'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final o in options)
                ChoiceChip(
                  label: Text(o.label),
                  selected: _whenLabel == o.label,
                  onSelected: (_) => setState(() {
                    _unlockAt = o.at;
                    _whenLabel = o.label;
                  }),
                ),
              ChoiceChip(
                avatar: const Icon(Icons.event_rounded, size: 18),
                label: const Text('Pick a date'),
                selected: _whenLabel == 'custom',
                onSelected: (_) => _pickCustom(),
              ),
            ],
          ),
          if (_unlockAt != null) ...[
            const SizedBox(height: Space.s),
            Text(
              'Opens ${DateFormat('EEEE d MMMM yyyy, HH:mm').format(_unlockAt!)}',
              style: context.tt.titleSmall?.copyWith(color: context.cc.accent),
            ),
          ],
          const SizedBox(height: Space.l),
          CloserButton(
            label: 'Seal the letter',
            icon: Icons.lock_rounded,
            kind: CloserButtonKind.accent,
            loading: _busy,
            onPressed: _seal,
          ),
          const SizedBox(height: Space.s),
          Text(
            '$name will see the envelope, but not what’s inside, until it opens.',
            textAlign: TextAlign.center,
            style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
          ),
        ],
      ),
    );
  }
}

/// One letter: a sealed envelope with a countdown, or the opening animation
/// and the letter itself.
class LetterScreen extends ConsumerStatefulWidget {
  const LetterScreen({required this.capsuleId, super.key});

  final String capsuleId;

  @override
  ConsumerState<LetterScreen> createState() => _LetterScreenState();
}

class _LetterScreenState extends ConsumerState<LetterScreen> {
  bool _opening = false;

  void _open(Capsule c) {
    hapticMedium();
    setState(() => _opening = true);
    ref.read(backendProvider).markCapsuleOpened(c.id).ignore();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authUidProvider).value;
    final name = ref.watch(partnerNameProvider);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final c = (ref.watch(capsulesProvider).value ?? const <Capsule>[]).where((x) => x.id == widget.capsuleId).firstOrNull;
    if (c == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(emoji: '📭', title: 'This letter is gone'));
    }
    final mine = c.authorId == me;
    final canRead = mine || c.isUnlocked(now);
    final alreadyOpen = mine || c.openedAt != null || _opening;

    return Scaffold(
      appBar: AppBar(
        title: Text(mine ? 'Your letter for $name' : 'From $name'),
        actions: [
          if (mine && !c.isUnlocked(now))
            IconButton(
              tooltip: 'Delete letter',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final ok = await confirm(context, title: 'Delete this letter?', body: '$name won’t get it.', ok: 'Delete', destructive: true);
                if (!ok || !context.mounted) return;
                final done = await runAction(context, () => ref.read(backendProvider).deleteCapsule(c.id));
                if (done && context.mounted) context.pop();
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          if (!canRead)
            _Sealed(capsule: c, now: now, name: name)
          else if (!alreadyOpen)
            _Unopened(capsule: c, name: name, onOpen: () => _open(c))
          else
            _Paper(capsule: c, name: name, mine: mine, animate: _opening),
        ],
      ),
    );
  }
}

class _Sealed extends StatelessWidget {
  const _Sealed({required this.capsule, required this.now, required this.name});

  final Capsule capsule;
  final DateTime now;
  final String name;

  @override
  Widget build(BuildContext context) {
    final left = capsule.unlockAt.difference(now);
    final parts = [
      if (left.inDays > 0) '${left.inDays} d',
      if (left.inDays < 30) '${left.inHours % 24} h',
      if (left.inDays == 0) '${left.inMinutes % 60} min',
    ];
    return Column(
      children: [
        const SizedBox(height: Space.l),
        const Text('✉️', style: TextStyle(fontSize: 120))
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .moveY(begin: 0, end: -8, duration: 1600.ms, curve: Curves.easeInOut),
        const SizedBox(height: Space.m),
        Text(capsule.title.isEmpty ? 'A letter from $name' : capsule.title, textAlign: TextAlign.center, style: context.tt.headlineSmall),
        const SizedBox(height: Space.s),
        Text('Sealed until ${DateFormat('EEEE d MMMM yyyy, HH:mm').format(capsule.unlockAt)}', textAlign: TextAlign.center),
        const SizedBox(height: Space.l),
        CounterChip(label: '${parts.join(' ')} to go', icon: Icons.lock_clock_rounded, color: context.cc.accent),
        const SizedBox(height: Space.m),
        Text('No peeking! 🙈', style: context.tt.bodyMedium?.copyWith(color: context.cc.muted)),
      ],
    );
  }
}

class _Unopened extends StatelessWidget {
  const _Unopened({required this.capsule, required this.name, required this.onOpen});

  final Capsule capsule;
  final String name;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: Space.l),
        GestureDetector(
          onTap: onOpen,
          child: const Text('💌', style: TextStyle(fontSize: 130))
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(begin: 1, end: 1.08, duration: 800.ms, curve: Curves.easeInOut),
        ),
        const SizedBox(height: Space.m),
        Text(capsule.title.isEmpty ? 'A letter from $name' : capsule.title, textAlign: TextAlign.center, style: context.tt.headlineSmall),
        const SizedBox(height: Space.xs),
        Text('Written ${DateFormat('d MMMM yyyy').format(capsule.createdAt)}', style: context.tt.bodyMedium?.copyWith(color: context.cc.muted)),
        const SizedBox(height: Space.l),
        CloserButton(label: 'Open the letter', icon: Icons.drafts_rounded, kind: CloserButtonKind.accent, onPressed: onOpen),
      ],
    );
  }
}

class _Paper extends StatelessWidget {
  const _Paper({required this.capsule, required this.name, required this.mine, required this.animate});

  final Capsule capsule;
  final String name;
  final bool mine;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    Widget paper = Container(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.l),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF5),
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: const Color(0xFFF0DCC8)),
        boxShadow: const [BoxShadow(color: Color(0x1A8A4B2E), blurRadius: 24, offset: Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (capsule.title.isNotEmpty) ...[
            Text(capsule.title, style: const TextStyle(fontFamily: 'Nunito', fontSize: 22, fontWeight: FontWeight.w700, color: Brand.ink)),
            const SizedBox(height: Space.m),
          ],
          CapsuleBody(
            capsule: capsule,
            textStyle: const TextStyle(fontFamily: 'Nunito', fontSize: 18, height: 1.6, color: Brand.ink),
          ),
          const SizedBox(height: Space.l),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '— ${mine ? 'you' : name}, ${DateFormat('d MMMM yyyy').format(capsule.createdAt)}',
              style: const TextStyle(fontFamily: 'Nunito', fontStyle: FontStyle.italic, color: Brand.grey700),
            ),
          ),
        ],
      ),
    );
    if (animate) {
      paper = paper
          .animate()
          .fadeIn(duration: 500.ms)
          .moveY(begin: 60, end: 0, duration: 700.ms, curve: Curves.easeOutCubic)
          .custom(
            duration: 700.ms,
            builder: (_, v, child) => Transform(
              alignment: Alignment.topCenter,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateX((1 - v) * math.pi / 3),
              child: child,
            ),
          );
    }
    return paper;
  }
}
