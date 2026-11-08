import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/widget_bridge.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/features/onboarding/pairing_screens.dart' show RelationLabelChips;
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
      () => ref.read(backendProvider).updateRelationship(
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
      body: 'This changes it for both of you: colours, question packs and how the app talks about you two. '
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
      () => ref.read(backendProvider).saveCountdown(
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
      return Scaffold(appBar: AppBar(title: const Text('Relationship')), body: const Center(child: CircularProgressIndicator()));
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
    final hasAnnivCountdown = countdowns.any((c) => c.repeatsYearly && pair.anniversary != null &&
        c.date.month == pair.anniversary!.month && c.date.day == pair.anniversary!.day);

    return Scaffold(
      appBar: AppBar(title: const Text('Relationship')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.xl),
        children: [
          // ------------------------------------------------------ header
          CloserCard(
            gradient: LinearGradient(colors: context.cc.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
            padding: const EdgeInsets.all(Space.l),
            child: Column(
              children: [
                AvatarPair(
                  me: me.displayName,
                  partner: realName,
                  mePhoto: me.photoUrl,
                  partnerPhoto: partner?.photoUrl,
                  size: 64,
                ),
                const SizedBox(height: Space.m),
                Text(
                  'You & ${nick.isNotEmpty ? nick : realName}',
                  style: context.tt.titleLarge?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (myLabel != null) '${myLabel.emoji} ${myLabel.title}' else (couple ? '💑 Couple' : '👯 Best friends'),
                    if (days != null) '${couple ? 'together' : 'friends'} for $days day${days == 1 ? '' : 's'}'
                    else 'connected ${DateFormat('d MMM yyyy').format(pair.pairedAt)}',
                  ].join(' · '),
                  textAlign: TextAlign.center,
                  style: context.tt.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                ),
              ],
            ),
          ),

          // ------------------------------------------------- type
          const SectionHeader('Relationship type'),
          Row(
            children: [
              Expanded(
                child: _TypeTile(
                  emoji: '💑',
                  title: 'Couple',
                  selected: couple,
                  color: Brand.pink,
                  onTap: () => _changeMode(pair, PairMode.couple, realName),
                ),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: _TypeTile(
                  emoji: '👯',
                  title: 'Best friends',
                  selected: !couple,
                  color: Brand.purple,
                  onTap: () => _changeMode(pair, PairMode.friends, realName),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.s),
          Text(
            'Shared with $realName. It sets the colours, the question packs and how Closer talks about you two.',
            style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
          ),

          // ------------------------------------------------- labels
          SectionHeader('$realName is my…'),
          RelationLabelChips(
            mode: pair.mode,
            selected: myLabel?.id,
            onSelected: (id) {
              if (id != myLabel?.id) _update(label: id, done: 'Saved');
            },
          ),
          const SizedBox(height: Space.s),
          Text(
            theirLabel == null
                ? '$realName hasn’t picked what you are to them yet.'
                : '$realName calls you their ${theirLabel.title.toLowerCase()} ${theirLabel.emoji}',
            style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
          ),

          // ----------------------------------------------- nickname
          const SectionHeader('Nickname'),
          TextField(
            controller: _nick,
            maxLength: 24,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'What do you call $realName?',
              hintText: couple ? 'Babe, Sunshine, Honey…' : 'Bestie, Partner in crime…',
              suffixIcon: nick.isEmpty
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
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  _update(nickname: _nick.text, done: 'Nickname saved');
                },
                child: const Text('Save nickname'),
              ),
            ),
          Text(
            'Only you see it. It replaces their name in your app and on your widget.',
            style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
          ),

          // ------------------------------------------- anniversary
          SectionHeader(couple ? 'Together since' : 'Friends since'),
          CloserCard(
            onTap: () => _pickDate(pair),
            child: Row(
              children: [
                const Icon(Icons.favorite_border_rounded),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Text(
                    pair.anniversary == null ? 'Add the date you got together' : DateFormat('EEEE d MMMM yyyy').format(pair.anniversary!),
                    style: context.tt.titleMedium,
                  ),
                ),
                if (pair.anniversary != null)
                  IconButton(
                    tooltip: 'Remove date',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => _update(clearAnniversary: true, done: 'Date removed'),
                  )
                else
                  const Icon(Icons.edit_calendar_rounded),
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
          Text(
            'Connected in Closer on ${DateFormat('d MMMM yyyy').format(pair.pairedAt)}.',
            style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
          ),

          // ---------------------------------------------- unpair
          const SectionHeader('Connection'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.link_off_rounded, color: context.cs.error),
            title: Text('Unpair from $realName', style: TextStyle(color: context.cs.error)),
            subtitle: const Text('Deletes your shared memories, questions, countdowns and plant'),
            onTap: () async {
              final yes = await confirm(
                context,
                title: 'Unpair from $realName?',
                body: 'Your shared memories, questions, countdowns and plant will be deleted. '
                    'You can export memories first in Privacy & data. $realName will be notified.',
                ok: 'Unpair',
                destructive: true,
              );
              if (!yes || !context.mounted) return;
              final ok = await runAction(context, ref.read(backendProvider).unpair);
              if (ok) await WidgetBridge.clear();
            },
          ),
        ],
      ),
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({
    required this.emoji,
    required this.title,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.tile),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: Space.m),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.12) : context.cc.card,
            borderRadius: BorderRadius.circular(Radii.tile),
            border: Border.all(color: selected ? color : context.cs.outlineVariant, width: 2),
          ),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 32)),
              const SizedBox(height: 4),
              Text(title, style: context.tt.titleSmall),
            ],
          ),
        ),
      ),
    );
  }
}
