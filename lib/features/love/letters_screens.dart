import 'dart:math' as math;

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/soft_ui.dart';
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
    final letters = (ref.watch(capsulesProvider).value ?? const <Capsule>[])
        .where((c) => c.kind == CapsuleKind.letter)
        .toList();
    final forMe = letters.where((c) => c.forUid == me).toList()..sort((a, b) => a.unlockAt.compareTo(b.unlockAt));
    final byMe = letters.where((c) => c.authorId == me).toList()..sort((a, b) => a.unlockAt.compareTo(b.unlockAt));
    // Ready ones first, then sealed by date, then already-read ones.
    final ready = forMe.where((c) => c.isUnlocked(now) && c.openedAt == null).toList();
    final sealed = forMe.where((c) => !c.isUnlocked(now)).toList();
    final read = forMe.where((c) => c.openedAt != null).toList().reversed.toList();

    Widget section(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
      child: Text(text, style: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
    );

    return Scaffold(
      floatingActionButton: _WriteButton(onTap: () => context.push('/letters/write')),
      body: Column(
        children: [
          const PlainPageHeader(title: 'Letters from the future', boxed: true),
          Expanded(
            child: letters.isEmpty
                ? EmptyState(
                    emoji: '💌',
                    title: 'Write to the future',
                    body:
                        'Seal a letter, a photo or a promise for $name. It opens on the day you choose: an anniversary, a trip, or just a random Tuesday.',
                    action: 'Write a letter',
                    onAction: () => context.push('/letters/write'),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 110),
                    children: [
                      if (forMe.isNotEmpty) section('For you from $name'),
                      for (final c in [...ready, ...sealed, ...read])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: c.openedAt == null
                              // Not read yet: the big pink card with a mascot.
                              ? _PinkLetterCard(
                                  title: c.title.isEmpty ? 'A letter from $name' : c.title,
                                  pill: opensIn(c.unlockAt, now),
                                  ready: c.isUnlocked(now),
                                  onTap: () => context.push('/letters/${c.id}'),
                                )
                              : _LetterRow(
                                  title: c.title.isEmpty ? 'A letter from $name' : c.title,
                                  subtitle: 'Opened ${DateFormat('d MMM yyyy').format(c.openedAt!)}',
                                  tone: SoftTone.mint,
                                  icon: Icons.mail_outline_rounded,
                                  onTap: () => context.push('/letters/${c.id}'),
                                ),
                        ),
                      if (byMe.isNotEmpty) ...[
                        if (forMe.isNotEmpty) const SizedBox(height: 8),
                        section('Written by you'),
                      ],
                      for (final c in byMe)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _LetterRow(
                            title: c.title.isEmpty ? 'A letter for $name' : c.title,
                            subtitle: c.openedAt != null
                                ? '$name read it ${DateFormat('d MMM').format(c.openedAt!)} 💗'
                                : c.isUnlocked(now)
                                ? 'Delivered — waiting for $name to open it'
                                : opensIn(c.unlockAt, now).replaceFirst('Opens', 'Opens for $name'),
                            tone: c.openedAt != null
                                ? SoftTone.mint
                                : (c.isUnlocked(now) ? SoftTone.pink : SoftTone.violet),
                            icon: c.isUnlocked(now) ? Icons.mail_outline_rounded : Icons.lock_outline_rounded,
                            onTap: () => context.push('/letters/${c.id}'),
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

/// Rounded pill choice: pastel or white fill; selected turns solid violet
/// with white text.
class _SoftChip extends StatelessWidget {
  const _SoftChip({
    required this.label,
    required this.fill,
    required this.selected,
    required this.onTap,
    this.icon,
    this.outlined = false,
  });

  final String label;
  final Color fill;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  /// Thin lavender border (for white pills on the lavender page).
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = selected ? Colors.white : (dark ? Colors.white : Brand.ink);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? Brand.royal : fill,
        shape: StadiumBorder(
          side: outlined && !selected
              ? BorderSide(color: context.cs.outlineVariant.withValues(alpha: 0.6))
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                  const SizedBox(width: 5),
                ] else if (icon != null) ...[
                  Icon(icon, size: 16, color: dark ? Colors.white : Brand.royal),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: context.tt.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pink of the big letter card (Figma "letters countdown screen").
const _cardPink = Color(0xFFFF9CCB);

/// Violet "Write a letter" pill floating bottom-right.
class _WriteButton extends StatelessWidget {
  const _WriteButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: Brand.royal.withValues(alpha: 0.35),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                  spreadRadius: -6,
                ),
              ],
      ),
      child: Material(
        color: Brand.royal,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.edit_outlined, size: 18, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  'Write a letter',
                  style: context.tt.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A letter for you that isn't read yet: pink card, white lock (or mail)
/// circle, big title, white "Opens in …" pill and a mascot peeking in.
class _PinkLetterCard extends StatelessWidget {
  const _PinkLetterCard({required this.title, required this.pill, required this.ready, required this.onTap});

  final String title;
  final String pill;
  final bool ready;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget card = Material(
      color: _cardPink,
      borderRadius: BorderRadius.circular(26),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned(
              right: 6,
              bottom: -8,
              child: Image.asset('assets/together/streak_mascot.png', width: 76, height: 84),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 96, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: Icon(
                      ready ? Icons.mail_outline_rounded : Icons.lock_outline_rounded,
                      size: 18,
                      color: _letterPink,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.tt.titleLarge?.copyWith(color: Brand.ink, fontSize: 19, height: 1.2),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                    child: Text(
                      pill,
                      style: context.tt.labelMedium?.copyWith(color: _letterPink, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (ready) {
      card = card
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .shimmer(duration: 1800.ms, color: Colors.white.withValues(alpha: 0.5))
          .scaleXY(begin: 1, end: 1.015, duration: 900.ms, curve: Curves.easeInOut);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: dark
            ? null
            : const [BoxShadow(color: Color(0x40FF6FAE), blurRadius: 24, offset: Offset(0, 12), spreadRadius: -8)],
      ),
      child: card,
    );
  }
}

/// Compact tinted row: white icon tile, title, coloured subtitle, chevron.
class _LetterRow extends StatelessWidget {
  const _LetterRow({
    required this.title,
    required this.subtitle,
    required this.tone,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final SoftTone tone;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: tone.fill(context),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: dark ? Colors.white.withValues(alpha: 0.12) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: tone.icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: dark ? Colors.white : Brand.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.tt.labelMedium?.copyWith(color: tone.icon, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: dark ? Colors.white : Brand.ink),
            ],
          ),
        ),
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

    final dark = Theme.of(context).brightness == Brightness.dark;
    const tones = [SoftTone.pink, SoftTone.violet, SoftTone.blue, SoftTone.mint, SoftTone.yellow, SoftTone.pink];

    Widget section(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
      child: Text(text, style: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
    );

    return Scaffold(
      body: Column(
        children: [
          PlainPageHeader(title: 'A letter for $name'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
              children: [
                // Envelope title: white field with a live counter, then
                // pastel suggestion pills.
                section('On the envelope'),
                ListenableBuilder(
                  listenable: _title,
                  builder: (context, _) => DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: dark ? null : softCardShadow,
                    ),
                    child: TextField(
                      controller: _title,
                      maxLength: Capsule.maxTitle,
                      textCapitalization: TextCapitalization.sentences,
                      style: context.tt.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                      decoration: softFieldDecoration(
                        context,
                        hint: 'Open when you miss me',
                        max: Capsule.maxTitle,
                        length: _title.text.length,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ListenableBuilder(
                  listenable: _title,
                  builder: (context, _) => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (i, t) in _titles.indexed)
                        _SoftChip(
                          label: t,
                          fill: tones[i % tones.length].fill(context),
                          selected: _title.text == t,
                          onTap: () => setState(() => _title.text = t),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                // The letter: pink sheet inside a white card, heart badge on
                // the corner (same look as the opened letter).
                section('Your letter'),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: context.cc.card,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: dark ? null : softCardShadow,
                      ),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                        decoration: BoxDecoration(
                          color: dark ? SoftTone.pink.fill(context) : const Color(0xFFFFF0F4),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: TextField(
                          controller: _text,
                          minLines: 8,
                          maxLines: 20,
                          maxLength: CapsuleContent.maxText,
                          textCapitalization: TextCapitalization.sentences,
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            height: 1.55,
                            color: dark ? Colors.white : Brand.ink,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            hintText: 'Dear $name,\n\n',
                            hintStyle: TextStyle(color: context.cc.muted, fontWeight: FontWeight.w600),
                            counterStyle: context.tt.labelSmall?.copyWith(color: context.cc.muted),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: -6,
                      top: -14,
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF5C9E),
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Color(0x55FF5C9E), blurRadius: 14, offset: Offset(0, 6))],
                        ),
                        child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 22),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                PhotoField(path: _photo, onChanged: (p) => setState(() => _photo = p), label: 'Tuck a photo inside'),
                const SizedBox(height: 24),
                section('When does it open?'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final o in options)
                      _SoftChip(
                        label: o.label,
                        fill: context.cc.card,
                        outlined: true,
                        selected: _whenLabel == o.label,
                        onTap: () => setState(() {
                          _unlockAt = o.at;
                          _whenLabel = o.label;
                        }),
                      ),
                    _SoftChip(
                      label: 'Pick a date',
                      icon: Icons.calendar_today_outlined,
                      fill: context.cc.card,
                      outlined: true,
                      selected: _whenLabel == 'custom',
                      onTap: _pickCustom,
                    ),
                  ],
                ),
                if (_unlockAt != null) ...[
                  const SizedBox(height: 12),
                  // Chosen moment in a lavender strip.
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: SoftTone.violet.fill(context),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock_clock_outlined, size: 20, color: SoftTone.violet.icon),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Opens ${DateFormat('EEEE d MMMM yyyy, HH:mm').format(_unlockAt!)}',
                            style: context.tt.labelLarge?.copyWith(
                              color: dark ? Colors.white : SoftTone.violet.icon,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 26),
                PillButton(
                  label: 'Seal the letter',
                  icon: Icons.lock_outline_rounded,
                  color: _letterPink,
                  loading: _busy,
                  onPressed: _seal,
                ),
                const SizedBox(height: 12),
                Text(
                  '$name will see the envelope, but not what’s inside, until it opens.',
                  textAlign: TextAlign.center,
                  style: context.tt.bodySmall?.copyWith(color: context.cc.muted, fontWeight: FontWeight.w600),
                ),
              ],
            ),
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
    final c = (ref.watch(capsulesProvider).value ?? const <Capsule>[])
        .where((x) => x.id == widget.capsuleId)
        .firstOrNull;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(emoji: '📭', title: 'This letter is gone'),
      );
    }
    final mine = c.authorId == me;
    final canRead = mine || c.isUnlocked(now);
    final alreadyOpen = mine || c.openedAt != null || _opening;

    return Scaffold(
      body: Column(
        children: [
          PlainPageHeader(
            title: mine ? 'Your letter for $name' : 'From $name',
            boxed: !canRead,
            actions: [
              if (mine && !c.isUnlocked(now))
                CircleIconButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Delete letter',
                  onTap: () async {
                    final ok = await confirm(
                      context,
                      title: 'Delete this letter?',
                      body: '$name won’t get it.',
                      ok: 'Delete',
                      destructive: true,
                    );
                    if (!ok || !context.mounted) return;
                    final done = await runAction(context, () => ref.read(backendProvider).deleteCapsule(c.id));
                    if (done && context.mounted) context.pop();
                  },
                ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
              children: [
                if (!canRead)
                  _Sealed(capsule: c, now: now, name: name)
                else if (!alreadyOpen)
                  _Unopened(capsule: c, name: name, onOpen: () => _open(c))
                else
                  _Paper(capsule: c, name: name, mine: mine, animate: _opening),
              ],
            ),
          ),
          if (canRead) const PeekingMascots() else const _NoPeeking(),
        ],
      ),
    );
  }
}

/// "No peeking! 🙈" above one mascot peeking up from the bottom (Figma
/// "letters countdown lock screen").
class _NoPeeking extends StatelessWidget {
  const _NoPeeking();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('No peeking! 🙈', style: context.tt.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        SizedBox(
          height: 96,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              maxHeight: 115,
              child: Image.asset('assets/together/streak_mascot.png', width: 104, height: 115),
            ),
          ),
        ),
      ],
    );
  }
}

/// Deep pink used for the letter's button and heart (Figma "from sam").
const _letterPink = Color(0xFFD6246E);

/// White card with a soft shadow, tilted a touch (Figma letter cards).
class _TiltedCard extends StatelessWidget {
  const _TiltedCard({required this.child, this.angle = -0.03});

  final Widget child;
  final double angle;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Transform.rotate(
      angle: angle,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.cc.card,
          borderRadius: BorderRadius.circular(28),
          boxShadow: dark ? null : softCardShadow,
        ),
        child: child,
      ),
    );
  }
}

/// Outline envelope with a heart on the flap (Figma "from sam").
class _EnvelopeArt extends StatelessWidget {
  const _EnvelopeArt({this.color = const Color(0xFFF06FA0), this.locked = false});

  final Color color;

  /// A lock badge where the flap meets, instead of the heart.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              // Locked (Figma "letters countdown lock"): soft fill, plain V
              // flap, no bottom folds.
              painter: _EnvelopePainter(color, fill: locked ? const Color(0xFFF6D9F4) : null, folds: !locked),
            ),
          ),
          if (locked)
            // Lock badge centred on the tip of the flap.
            Positioned(
              top: 4 + 88 * 0.6 - 18,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: const Icon(Icons.lock_outline_rounded, size: 19, color: Color(0xFFF6D9F4)),
              ),
            )
          else
            Positioned(top: 20, child: Icon(Icons.favorite_rounded, size: 38, color: color)),
        ],
      ),
    );
  }
}

class _EnvelopePainter extends CustomPainter {
  const _EnvelopePainter(this.color, {this.fill, this.folds = true});

  final Color color;

  /// Inside colour; null leaves it see-through.
  final Color? fill;

  /// Draw the two bottom fold lines.
  final bool folds;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = folds ? 5.5 : 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    const inset = 4.0;
    final r = Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2);
    final box = RRect.fromRectAndRadius(r, Radius.circular(folds ? 12 : 8));
    if (fill != null) canvas.drawRRect(box, Paint()..color = fill!);
    final tip = Offset(r.center.dx, r.top + r.height * (folds ? 0.56 : 0.6));
    canvas
      ..drawRRect(box, p)
      // Flap: top corners down to the middle.
      ..drawLine(r.topLeft + const Offset(6, 6), tip, p)
      ..drawLine(r.topRight + const Offset(-6, 6), tip, p);
    if (folds) {
      canvas
        ..drawLine(r.bottomLeft + const Offset(8, -6), Offset(r.left + r.width * 0.36, r.top + r.height * 0.55), p)
        ..drawLine(r.bottomRight + const Offset(-8, -6), Offset(r.right - r.width * 0.36, r.top + r.height * 0.55), p);
    }
  }

  @override
  bool shouldRepaint(_EnvelopePainter old) => old.color != color || old.fill != fill || old.folds != folds;
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Pink card: violet envelope with a lock, title, date, white countdown
    // pill (Figma "letters countdown lock screen").
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _cardPink,
        borderRadius: BorderRadius.circular(28),
        boxShadow: dark
            ? null
            : const [BoxShadow(color: Color(0x40FF6FAE), blurRadius: 26, offset: Offset(0, 14), spreadRadius: -8)],
      ),
      child: Stack(
        children: [
          Positioned(
            left: -40,
            top: -40,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), shape: BoxShape.circle),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(34, 28, 34, 26),
            child: Column(
              children: [
                const _EnvelopeArt(color: Color(0xFF7B3FE4), locked: true)
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .moveY(begin: 0, end: -5, duration: 1600.ms, curve: Curves.easeInOut),
                const SizedBox(height: 18),
                Text(
                  capsule.title.isEmpty ? 'A letter from $name' : capsule.title,
                  textAlign: TextAlign.center,
                  style: context.tt.headlineSmall?.copyWith(fontSize: 25, color: Brand.ink, height: 1.15),
                ),
                const SizedBox(height: 6),
                Text(
                  'Sealed until ${DateFormat('EEEE d MMMM yyyy, HH:mm').format(capsule.unlockAt)}',
                  textAlign: TextAlign.center,
                  style: context.tt.bodySmall?.copyWith(color: Brand.ink, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline_rounded, size: 15, color: _letterPink),
                      const SizedBox(width: 5),
                      Text(
                        '${parts.join(' ')} to go',
                        style: context.tt.labelLarge?.copyWith(color: _letterPink, fontWeight: FontWeight.w800),
                      ),
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

class _Unopened extends StatelessWidget {
  const _Unopened({required this.capsule, required this.name, required this.onOpen});

  final Capsule capsule;
  final String name;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // White tilted card: pink square with the envelope, title, date.
        GestureDetector(
          onTap: onOpen,
          child: _TiltedCard(
            child: Column(
              children: [
                AspectRatio(
                  aspectRatio: 1.35,
                  child: Container(
                    decoration: BoxDecoration(
                      color: SoftTone.pink.fill(context),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    alignment: Alignment.center,
                    child: const _EnvelopeArt()
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .scaleXY(begin: 1, end: 1.06, duration: 900.ms, curve: Curves.easeInOut),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  capsule.title.isEmpty ? 'A letter from $name' : capsule.title,
                  textAlign: TextAlign.center,
                  style: context.tt.headlineSmall?.copyWith(fontSize: 22),
                ),
                const SizedBox(height: 4),
                Text(
                  'Written ${DateFormat('d MMMM yyyy').format(capsule.createdAt)}',
                  style: context.tt.bodyMedium?.copyWith(color: context.cc.muted, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
        const SizedBox(height: 26),
        PillButton(label: 'Open the letter', icon: Icons.mail_outline_rounded, color: _letterPink, onPressed: onOpen),
      ],
    );
  }
}

/// The opened letter: pink sheet inside a tilted white card, a heart badge
/// on the corner and the signature at the bottom (Figma "open letter").
class _Paper extends StatelessWidget {
  const _Paper({required this.capsule, required this.name, required this.mine, required this.animate});

  final Capsule capsule;
  final String name;
  final bool mine;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    Widget paper = Stack(
      clipBehavior: Clip.none,
      children: [
        _TiltedCard(
          angle: -0.025,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            decoration: BoxDecoration(color: const Color(0xFFFFF0F4), borderRadius: BorderRadius.circular(20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (capsule.title.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 24),
                    child: Text(
                      capsule.title,
                      style: const TextStyle(
                        fontFamily: 'Fredoka',
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: Brand.ink,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                CapsuleBody(
                  capsule: capsule,
                  textStyle: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.55,
                    color: Brand.ink,
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '— ${mine ? 'you' : name}, ${DateFormat('d MMMM yyyy').format(capsule.createdAt)}',
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Color(0xFF5B5675),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          right: -6,
          top: -14,
          child: Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: Color(0xFFFF5C9E),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0x55FF5C9E), blurRadius: 14, offset: Offset(0, 6))],
            ),
            child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 24),
          ),
        ),
      ],
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
    return Padding(padding: const EdgeInsets.only(top: 10), child: paper);
  }
}
