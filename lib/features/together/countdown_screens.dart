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
                                Text(_when(context, c, now, 'EEE d MMM yyyy'), style: context.tt.bodySmall?.copyWith(color: context.cc.muted)),
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

/// Date of the next occurrence, plus " · 6:30 PM" when a time is set.
String _when(BuildContext context, Countdown c, DateTime now, String pattern) {
  final date = DateFormat(pattern).format(c.nextOccurrence(now));
  if (!c.hasTime) return date;
  return '$date · ${TimeOfDay.fromDateTime(c.date).format(context)}';
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
          Text(_when(context, c, now, 'EEEE d MMMM yyyy'), textAlign: TextAlign.center, style: context.tt.bodyMedium?.copyWith(color: Colors.white70)),
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
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  String _emoji = '✈️';
  bool _yearly = false;
  int _remind = Countdown.minutesPerDay; // minutes before
  Countdown? _existing;
  bool _busy = false;

  static const _emojis = ['✈️', '💑', '🎂', '💍', '🎄', '🏖️', '🎉', '🎓', '🏠', '❤️', '🎁', '📅'];

  /// Reminder presets, in minutes before the moment.
  static const _remindPresets = [0, 5, 15, 30, 60, 120, 1440, 2880, 4320, 10080];
  static const _customRemind = -1;

  DateTime get _moment => DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  /// A one-off countdown has to be in the future.
  bool get _inPast => !_yearly && !_moment.isAfter(DateTime.now());

  @override
  void initState() {
    super.initState();
    final list = ref.read(countdownsProvider).value ?? const <Countdown>[];
    _existing = list.where((c) => c.id == widget.countdownId).firstOrNull;
    final e = _existing;
    if (e != null) {
      _title.text = e.title;
      _date = e.date;
      if (e.hasTime) _time = TimeOfDay.fromDateTime(e.date);
      _emoji = e.emoji;
      _yearly = e.repeatsYearly;
      _remind = e.remindMinutesBefore;
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
              date: _moment,
              hasTime: true,
              emoji: _emoji,
              repeatsYearly: _yearly,
              remindMinutesBefore: _remind,
              createdBy: _existing?.createdBy ?? '',
            ),
          ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) context.pop();
  }

  Future<void> _pickCustomRemind() async {
    final picked = await showDialog<int>(context: context, builder: (_) => _CustomRemindDialog(initialMinutes: _remind));
    if (picked != null) setState(() => _remind = picked);
  }

  @override
  Widget build(BuildContext context) {
    final remindValues = [..._remindPresets, if (!_remindPresets.contains(_remind)) _remind];
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
          const SizedBox(height: Space.s),
          CloserCard(
            onTap: () async {
              final t = await showTimePicker(context: context, initialTime: _time);
              if (t != null) setState(() => _time = t);
            },
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded),
                const SizedBox(width: Space.m),
                Expanded(child: Text(_time.format(context), style: context.tt.titleMedium)),
                const Icon(Icons.edit_rounded, size: 18),
              ],
            ),
          ),
          if (_inPast)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs, left: Space.s),
              child: Text('That time has already passed', style: context.tt.bodySmall?.copyWith(color: context.cs.error)),
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
              items: [
                for (final m in remindValues) DropdownMenuItem(value: m, child: Text(Countdown.describeRemind(m))),
                const DropdownMenuItem(value: _customRemind, child: Text('Custom…')),
              ],
              onChanged: (v) async {
                if (v == _customRemind) {
                  await _pickCustomRemind();
                } else if (v != null) {
                  setState(() => _remind = v);
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m),
            child: Text(
              _remind == 0
                  ? 'You both get a notification at the time.'
                  : 'You both get a notification ${Countdown.describeRemind(_remind)}, and again at the time.',
              style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
            ),
          ),
          const SizedBox(height: Space.l),
          CloserButton(label: 'Save', loading: _busy, onPressed: _title.text.trim().isEmpty || _inPast ? null : _save),
        ],
      ),
    );
  }
}

/// "Remind us 45 minutes / 6 hours / 10 days before".
class _CustomRemindDialog extends StatefulWidget {
  const _CustomRemindDialog({required this.initialMinutes});

  final int initialMinutes;

  @override
  State<_CustomRemindDialog> createState() => _CustomRemindDialogState();
}

class _CustomRemindDialogState extends State<_CustomRemindDialog> {
  static const _units = {'minutes': 1, 'hours': 60, 'days': Countdown.minutesPerDay};

  late final TextEditingController _amount;
  late String _unit;

  @override
  void initState() {
    super.initState();
    final m = widget.initialMinutes;
    _unit = m > 0 && m % Countdown.minutesPerDay == 0
        ? 'days'
        : m > 0 && m % 60 == 0
            ? 'hours'
            : 'minutes';
    final n = m <= 0 ? 30 : m ~/ _units[_unit]!;
    _amount = TextEditingController(text: '$n');
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int? get _minutes {
    final n = int.tryParse(_amount.text.trim());
    if (n == null || n <= 0) return null;
    final m = n * _units[_unit]!;
    return m > Countdown.maxRemindMinutes ? null : m;
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _minutes;
    return AlertDialog(
      title: const Text('Remind us before'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'How long before'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.m),
          SegmentedButton<String>(
            segments: [for (final u in _units.keys) ButtonSegment(value: u, label: Text(u))],
            selected: {_unit},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _unit = v.first),
          ),
          if (minutes == null && _amount.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: Text('Pick something up to 60 days', style: context.tt.bodySmall?.copyWith(color: context.cs.error)),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          // Compact pill for dialogs; the theme default (56 tall) is for full-width actions.
          style: FilledButton.styleFrom(
            minimumSize: const Size(80, 40),
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
          ),
          onPressed: minutes == null ? null : () => Navigator.pop(context, minutes),
          child: const Text('Set'),
        ),
      ],
    );
  }
}
