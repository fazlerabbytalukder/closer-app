import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/widget_bridge.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/soft_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Settings → Relationship: type (couple / best friends), what you call
/// each other, a nickname, and the "together since" date.
class RelationshipScreen extends ConsumerStatefulWidget {
  const RelationshipScreen({super.key});

  @override
  ConsumerState<RelationshipScreen> createState() => _RelationshipScreenState();
}

class _RelationshipScreenState extends ConsumerState<RelationshipScreen> {
  final _nick = TextEditingController();
  bool _nickLoaded = false;

  @override
  void dispose() {
    _nick.dispose();
    super.dispose();
  }

  Future<void> _update({
    PairMode? mode,
    DateTime? anniversary,
    bool clearAnniversary = false,
    String? label,
    String? nickname,
    String? done,
  }) async {
    final ok = await runAction(
      context,
      () => ref
          .read(backendProvider)
          .updateRelationship(
            mode: mode,
            anniversary: anniversary,
            clearAnniversary: clearAnniversary,
            label: label,
            nickname: nickname,
          ),
    );
    if (ok && done != null && mounted) {
      hapticSoft();
      showToast(context, done);
    }
  }

  Future<void> _changeMode(Pair pair, PairMode mode, String partnerName) async {
    if (mode == pair.mode) return;
    final toCouple = mode == PairMode.couple;
    final yes = await confirm(
      context,
      title: toCouple ? 'Switch to couple?' : 'Switch to best friends?',
      body:
          'This changes it for both of you: colours, question packs and how the app talks about you two. '
          '$partnerName will see the change too.',
      ok: 'Switch',
    );
    if (!yes) return;
    await _update(mode: mode, done: toCouple ? 'You’re a couple now 💑' : 'You’re best friends now 👯');
  }

  Future<void> _pickDate(Pair pair) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: pair.anniversary ?? pair.pairedAt,
      firstDate: DateTime(1950),
      lastDate: now,
      helpText: pair.mode == PairMode.couple ? 'Together since' : 'Friends since',
    );
    if (d != null) await _update(anniversary: d, done: 'Date saved');
  }

  Future<void> _addAnniversaryCountdown(Pair pair) async {
    final a = pair.anniversary;
    if (a == null) return;
    final couple = pair.mode == PairMode.couple;
    final ok = await runAction(
      context,
      () => ref
          .read(backendProvider)
          .saveCountdown(
            Countdown(
              id: '',
              title: couple ? 'Our anniversary' : 'Our friendiversary',
              date: a,
              emoji: couple ? '💑' : '👯',
              repeatsYearly: true,
              createdBy: '',
            ),
          ),
    );
    if (ok && mounted) showToast(context, 'Added to your countdowns 📅');
  }

  @override
  Widget build(BuildContext context) {
    final pair = ref.watch(pairProvider).value;
    final me = ref.watch(meProvider).value;
    final partner = ref.watch(partnerProvider).value;
    final myLabel = ref.watch(myLabelForPartnerProvider);
    final theirLabel = ref.watch(partnerLabelForMeProvider);
    if (pair == null || me == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Relationship')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final realName = (partner?.displayName.isNotEmpty ?? false) ? partner!.displayName : 'your person';
    final nick = pair.nicknames[me.uid] ?? '';
    if (!_nickLoaded) {
      _nick.text = nick;
      _nickLoaded = true;
    }
    final couple = pair.mode == PairMode.couple;
    final days = pair.daysTogether(DateTime.now());
    final countdowns = ref.watch(countdownsProvider).value ?? const <Countdown>[];
    final hasAnnivCountdown = countdowns.any(
      (c) =>
          c.repeatsYearly &&
          pair.anniversary != null &&
          c.date.month == pair.anniversary!.month &&
          c.date.day == pair.anniversary!.day,
    );

    final shownName = nick.isNotEmpty ? nick : realName;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          // ------------------------------------------------------ header
          VioletPageHeader(
            title: 'Relationship',
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
              decoration: BoxDecoration(
                color: context.cc.card,
                borderRadius: BorderRadius.circular(28),
                boxShadow: dark ? null : softCardShadow,
              ),
              child: Column(
                children: [
                  AvatarPair(
                    me: me.displayName,
                    partner: realName,
                    mePhoto: me.photoUrl,
                    partnerPhoto: partner?.photoUrl,
                    size: 56,
                    ring: context.cc.card,
                  ),
                  const SizedBox(height: 12),
                  Text('You & $shownName', style: context.tt.titleLarge?.copyWith(fontSize: 24)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.favorite_border_rounded, size: 14, color: context.cc.muted),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          [
                            if (myLabel != null) myLabel.title else (couple ? 'Couple' : 'Best friends'),
                            if (days != null)
                              '${couple ? 'together' : 'friends'} for $days day${days == 1 ? '' : 's'}'
                            else
                              'connected ${DateFormat('d MMM yyyy').format(pair.pairedAt)}',
                          ].join(' · '),
                          textAlign: TextAlign.center,
                          style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ------------------------------------------------- type
                const PageSectionTitle('Relationship type'),
                Row(
                  children: [
                    Expanded(
                      child: _TypeTile(
                        icon: Icons.favorite_border_rounded,
                        tone: SoftTone.violet,
                        title: 'Couple',
                        selected: couple,
                        onTap: () => _changeMode(pair, PairMode.couple, realName),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TypeTile(
                        icon: Icons.people_outline_rounded,
                        tone: SoftTone.mint,
                        title: 'Best friends',
                        selected: !couple,
                        onTap: () => _changeMode(pair, PairMode.friends, realName),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.s),
                _Hint(
                  'Shared with $realName. It sets the colours, the question packs and how Duosy talks about you two.',
                ),

                // ------------------------------------------------- labels
                PageSectionTitle('$realName is my…'),
                _LabelChips(
                  mode: pair.mode,
                  selected: myLabel?.id,
                  onSelected: (id) {
                    if (id != myLabel?.id) _update(label: id, done: 'Saved');
                  },
                ),
                const SizedBox(height: Space.s),
                _Hint(
                  theirLabel == null
                      ? '$realName hasn’t picked what you are to them yet.'
                      : '$realName calls you their ${theirLabel.title.toLowerCase()} ${theirLabel.emoji}',
                ),

                // ----------------------------------------------- nickname
                const PageSectionTitle('Nickname'),
                TextField(
                  controller: _nick,
                  maxLength: 24,
                  textCapitalization: TextCapitalization.words,
                  decoration: softFieldDecoration(
                    context,
                    hint: 'What do you call $realName?',
                    max: 24,
                    length: _nick.text.length,
                    clear: nick.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Remove nickname',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _nick.clear();
                              _update(nickname: '', done: 'Nickname removed');
                            },
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (v) => _update(nickname: v, done: 'Nickname saved'),
                ),
                if (_nick.text.trim() != nick)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.s),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: () {
                          FocusScope.of(context).unfocus();
                          _update(nickname: _nick.text, done: 'Nickname saved');
                        },
                        child: const Text('Save nickname'),
                      ),
                    ),
                  ),
                const SizedBox(height: Space.s),
                const _Hint('Only you see it. It replaces their name in your app and on your widget.'),

                // ------------------------------------------- anniversary
                PageSectionTitle(couple ? 'Together since' : 'Friends since'),
                _ToneCard(
                  tone: SoftTone.mint,
                  onTap: () => _pickDate(pair),
                  child: Row(
                    children: [
                      const IconTile(icon: Icons.favorite_border_rounded, tone: SoftTone.mint),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          pair.anniversary == null
                              ? 'Add the date you got together'
                              : DateFormat('EEEE d MMMM yyyy').format(pair.anniversary!),
                          style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (pair.anniversary != null)
                        IconButton(
                          tooltip: 'Remove date',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => _update(clearAnniversary: true, done: 'Date removed'),
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(Icons.calendar_today_outlined, size: 20),
                        ),
                    ],
                  ),
                ),
                if (pair.anniversary != null && !hasAnnivCountdown) ...[
                  const SizedBox(height: Space.s),
                  CloserButton(
                    label: couple ? 'Count down to our anniversary' : 'Count down to our friendiversary',
                    icon: Icons.event_repeat_rounded,
                    kind: CloserButtonKind.secondary,
                    onPressed: () => _addAnniversaryCountdown(pair),
                  ),
                ],
                const SizedBox(height: Space.s),
                _Hint('Connected in Duosy on ${DateFormat('d MMMM yyyy').format(pair.pairedAt)}.'),

                // ---------------------------------------------- unpair
                const PageSectionTitle('Connection'),
                _ToneCard(
                  tone: SoftTone.red,
                  onTap: () async {
                    final yes = await confirm(
                      context,
                      title: 'Unpair from $realName?',
                      body:
                          'Your shared memories, questions, countdowns and plant will be deleted. '
                          'You can export memories first in Privacy & data. $realName will be notified.',
                      ok: 'Unpair',
                      destructive: true,
                    );
                    if (!yes || !context.mounted) return;
                    final ok = await runAction(context, ref.read(backendProvider).unpair);
                    if (ok) await WidgetBridge.clear();
                  },
                  child: Row(
                    children: [
                      const IconTile(icon: Icons.link_off_rounded, tone: SoftTone.red),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Unpair from $realName',
                              style: context.tt.titleSmall?.copyWith(
                                color: SoftTone.red.icon,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Deletes your shared memories, questions, countdowns and plant',
                              style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
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
        ],
      ),
    );
  }
}

/// Muted helper line under a section.
class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: context.tt.bodySmall?.copyWith(color: context.cc.muted));
  }
}

/// Tinted rounded card (Figma: mint "Together since", pink "Unpair").
class _ToneCard extends StatelessWidget {
  const _ToneCard({required this.tone, required this.child, this.onTap});

  final SoftTone tone;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tone.fill(context),
      borderRadius: BorderRadius.circular(Radii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.card),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(14), child: child),
      ),
    );
  }
}

/// "Sam is my…" labels as tinted pills, one colour per label.
class _LabelChips extends StatelessWidget {
  const _LabelChips({required this.mode, required this.selected, required this.onSelected});

  final PairMode mode;
  final String? selected;
  final ValueChanged<String> onSelected;

  static const _tones = [SoftTone.pink, SoftTone.blue, SoftTone.pink, SoftTone.yellow, SoftTone.mint, SoftTone.violet];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (i, l) in RelationLabel.forMode(mode).indexed)
          _LabelPill(
            label: '${l.emoji} ${l.title}',
            tone: _tones[i % _tones.length],
            selected: selected == l.id,
            onTap: () => onSelected(l.id),
          ),
      ],
    );
  }
}

class _LabelPill extends StatelessWidget {
  const _LabelPill({required this.label, required this.tone, required this.selected, required this.onTap});

  final String label;
  final SoftTone tone;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: tone.fill(context),
        shape: StadiumBorder(side: BorderSide(color: selected ? tone.icon : Colors.transparent, width: 1.6)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[Icon(Icons.check_rounded, size: 16, color: tone.icon), const SizedBox(width: 4)],
                Text(label, style: context.tt.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Couple / Best friends choice: white card with an icon badge; the chosen
/// one is violet-tinted with a check in the corner.
class _TypeTile extends StatelessWidget {
  const _TypeTile({
    required this.icon,
    required this.tone,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final SoftTone tone;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = context.cs.primary;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: selected ? SoftTone.violet.fill(context) : context.cc.card,
            borderRadius: BorderRadius.circular(Radii.card),
            border: Border.all(color: selected ? accent : Colors.transparent, width: 2),
            boxShadow: dark || selected ? null : softCardShadow,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: selected ? context.cc.card : tone.fill(context),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 22, color: selected ? accent : tone.icon),
                    ),
                    const SizedBox(height: 8),
                    Text(title, style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              if (selected)
                Positioned(
                  top: -8,
                  right: 10,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, size: 15, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
