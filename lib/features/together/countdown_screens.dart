import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/data/closer_backend.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/ads.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// Countdowns list with the next date big (F7).
class CountdownsScreen extends ConsumerWidget {
  const CountdownsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(countdownsProvider).value ?? const <Countdown>[];
    final plus = ref.watch(isPlusProvider);
    final now = DateTime.now();
    void add() {
      if (!plus && list.length >= FreeLimits.countdowns) {
        context.push('/paywall?from=countdowns');
      } else {
        context.push('/countdowns/edit');
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Countdowns'),
        actions: [IconButton(tooltip: 'Add countdown', icon: const Icon(Icons.add_rounded), onPressed: add)],
      ),
      body: list.isEmpty
          ? EmptyState(
              emoji: '📅',
              title: 'Something to look forward to',
              body: 'Add your next date, trip, or anniversary. It shows on your widgets too.',
              action: 'Add a date',
              onAction: add,
            )
          : ListView(
              padding: const EdgeInsets.all(Space.m),
              children: [
                _Hero(c: list.first, now: now),
                const SizedBox(height: Space.m),
                for (final c in list.skip(1))
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.s),
                    child: CloserCard(
                      onTap: () => context.push('/countdowns/edit?id=${c.id}'),
                      child: Row(
                        children: [
                          Text(c.emoji, style: const TextStyle(fontSize: 28)),
                          const SizedBox(width: Space.m),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.title, style: context.tt.titleMedium),
                                Text(DateFormat('EEE d MMM yyyy').format(c.nextOccurrence(now)), style: context.tt.bodySmall?.copyWith(color: context.cc.muted)),
                              ],
                            ),
                          ),
                          Text('${c.daysLeft(now)}d', style: context.tt.titleLarge?.copyWith(color: context.cc.secondary)),
                        ],
                      ),
                    ),
                  ),
                if (!plus)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.s),
                    child: Text(
                      '${list.length} of ${FreeLimits.countdowns} free countdowns used',
                      textAlign: TextAlign.center,
                      style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
                    ),
                  ),
                const AdBanner(),
              ],
            ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.c, required this.now});

  final Countdown c;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final days = c.daysLeft(now);
    return CloserCard(
      onTap: () => context.push('/countdowns/edit?id=${c.id}'),
      gradient: LinearGradient(colors: context.cc.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
      padding: const EdgeInsets.all(Space.l),
      child: Column(
        children: [
          Text(c.emoji, style: const TextStyle(fontSize: 48)),
          Text(days == 0 ? 'Today!' : '$days', style: context.tt.displaySmall?.copyWith(color: Colors.white, fontSize: 64)),
          Text(
            days == 0 ? c.title : '${days == 1 ? 'day' : 'days'} to ${c.title}',
            textAlign: TextAlign.center,
            style: context.tt.titleLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: Space.xs),
          Text(DateFormat('EEEE d MMMM yyyy').format(c.nextOccurrence(now)), style: context.tt.bodyMedium?.copyWith(color: Colors.white70)),
        ],
      ),
    );
  }
}

class CountdownEditScreen extends ConsumerStatefulWidget {
  const CountdownEditScreen({super.key, this.countdownId});

  final String? countdownId;

  @override
  ConsumerState<CountdownEditScreen> createState() => _CountdownEditScreenState();
}

class _CountdownEditScreenState extends ConsumerState<CountdownEditScreen> {
  final _title = TextEditingController();
  DateTime _date = DateTime.now().add(const Duration(days: 7));
  String _emoji = '✈️';
  bool _yearly = false;
  int _remind = 1;
  Countdown? _existing;
  bool _busy = false;

  static const _emojis = ['✈️', '💑', '🎂', '💍', '🎄', '🏖️', '🎉', '🎓', '🏠', '❤️', '🎁', '📅'];

  @override
  void initState() {
    super.initState();
    final list = ref.read(countdownsProvider).value ?? const <Countdown>[];
    _existing = list.where((c) => c.id == widget.countdownId).firstOrNull;
    final e = _existing;
    if (e != null) {
      _title.text = e.title;
      _date = e.date;
      _emoji = e.emoji;
      _yearly = e.repeatsYearly;
      _remind = e.remindDaysBefore;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => ref.read(backendProvider).saveCountdown(
            Countdown(
              id: _existing?.id ?? '',
              title: _title.text.trim(),
              date: DateTime(_date.year, _date.month, _date.day),
              emoji: _emoji,
              repeatsYearly: _yearly,
              remindDaysBefore: _remind,
              createdBy: _existing?.createdBy ?? '',
            ),
          ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null ? 'New countdown' : 'Edit countdown'),
        actions: [
          if (_existing != null)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final yes = await confirm(context, title: 'Delete countdown?', body: '“${_existing!.title}” will be removed for both of you.', ok: 'Delete', destructive: true);
                if (!yes || !context.mounted) return;
                final ok = await runAction(context, () => ref.read(backendProvider).deleteCountdown(_existing!.id));
                if (ok && context.mounted) context.pop();
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          TextField(
            controller: _title,
            maxLength: 30,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'What are you counting down to?', hintText: 'Paris trip'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.s),
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              for (final e in _emojis)
                ChoiceChip(
                  label: Text(e, style: const TextStyle(fontSize: 20)),
                  selected: _emoji == e,
                  onSelected: (_) => setState(() => _emoji = e),
                ),
            ],
          ),
          const SizedBox(height: Space.m),
          CloserCard(
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _date.isBefore(DateTime.now()) && !_yearly ? DateTime.now() : _date,
                firstDate: _yearly ? DateTime(1950) : DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
              );
              if (d != null) setState(() => _date = d);
            },
            child: Row(
              children: [
                const Icon(Icons.event_rounded),
                const SizedBox(width: Space.m),
                Expanded(child: Text(DateFormat('EEEE d MMMM yyyy').format(_date), style: context.tt.titleMedium)),
                const Icon(Icons.edit_rounded, size: 18),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('Repeats every year'),
            subtitle: const Text('Birthdays, anniversaries'),
            value: _yearly,
            onChanged: (v) => setState(() => _yearly = v),
          ),
          ListTile(
            title: const Text('Remind us'),
            trailing: DropdownButton<int>(
              value: _remind,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 0, child: Text('On the day')),
                DropdownMenuItem(value: 1, child: Text('1 day before')),
                DropdownMenuItem(value: 3, child: Text('3 days before')),
                DropdownMenuItem(value: 7, child: Text('1 week before')),
              ],
              onChanged: (v) => setState(() => _remind = v ?? 1),
            ),
          ),
          const SizedBox(height: Space.l),
          CloserButton(label: 'Save', loading: _busy, onPressed: _title.text.trim().isEmpty ? null : _save),
        ],
      ),
    );
  }
}
