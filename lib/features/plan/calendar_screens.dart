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

/// Dot / accent colour per event category.
Color categoryColor(EventCategory c) => switch (c) {
      EventCategory.date => const Color(0xFFFF6B8A),
      EventCategory.meetup => const Color(0xFF7B6CF6),
      EventCategory.trip => const Color(0xFF2F7BE6),
      EventCategory.call => const Color(0xFF5DBB63),
      EventCategory.birthday => const Color(0xFFFFB547),
      EventCategory.anniversary => const Color(0xFFE5506F),
      EventCategory.other => const Color(0xFF8A90A0),
    };

String _dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Shared calendar (F12, with the F7 countdowns merged in): countdowns on
/// top, a month grid, the selected day, and what's coming up.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _selected = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  void _add([DateTime? day]) => context.push('/calendar/edit?date=${_dayKey(day ?? _selected)}');

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(eventsProvider).value ?? const <Countdown>[];
    final countdowns = ref.watch(countdownsProvider).value ?? const <Countdown>[];
    final now = DateTime.now();
    final onSelected = events.where((e) => e.occursOn(_selected)).toList()
      ..sort((a, b) => (a.hasTime ? a.date.hour * 60 + a.date.minute : -1).compareTo(b.hasTime ? b.date.hour * 60 + b.date.minute : -1));
    final upcoming = events.where((e) => !e.isPast(now) && e.daysLeft(now) <= 60).toList()
      ..sort((a, b) => a.nextMoment(now).compareTo(b.nextMoment(now)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Our calendar'),
        actions: [IconButton(tooltip: 'Add to calendar', icon: const Icon(Icons.add_rounded), onPressed: _add)],
      ),
      floatingActionButton: FloatingActionButton(tooltip: 'Add to calendar', onPressed: _add, child: const Icon(Icons.add_rounded)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, 100),
        children: [
          if (countdowns.isNotEmpty) ...[
            SizedBox(
              height: 128,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: countdowns.length,
                separatorBuilder: (_, _) => const SizedBox(width: Space.s),
                itemBuilder: (_, i) => _CountdownCard(c: countdowns[i], now: now, big: i == 0),
              ),
            ),
            const SizedBox(height: Space.m),
          ],
          CloserCard(
            padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.s, Space.m),
            child: _MonthGrid(
              month: _month,
              selected: _selected,
              events: events,
              onMonth: (m) => setState(() => _month = m),
              onDay: (d) => setState(() => _selected = d),
              onLongPress: _add,
            ),
          ),
          SectionHeader(
            _isSameDay(_selected, now) ? 'Today' : DateFormat('EEEE d MMMM').format(_selected),
            action: 'Add',
            onAction: _add,
          ),
          if (onSelected.isEmpty)
            Text('Nothing planned. Tap Add to plan something 💫', style: context.tt.bodyMedium?.copyWith(color: context.cc.muted))
          else
            for (final e in onSelected) EventTile(event: e, day: _selected),
          if (upcoming.isNotEmpty) ...[
            const SectionHeader('Coming up'),
            for (final e in upcoming.take(10)) EventTile(event: e),
          ],
          const SizedBox(height: Space.m),
          const AdBanner(),
        ],
      ),
    );
  }
}

bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

class _CountdownCard extends StatelessWidget {
  const _CountdownCard({required this.c, required this.now, required this.big});

  final Countdown c;
  final DateTime now;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final days = c.daysLeft(now);
    return SizedBox(
      width: big ? 220 : 150,
      child: CloserCard(
        onTap: () => context.push('/calendar/edit?id=${c.id}'),
        gradient: LinearGradient(
          colors: big ? context.cc.gradient : [categoryColor(c.category), categoryColor(c.category).withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        padding: const EdgeInsets.all(Space.s + 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.emoji, style: TextStyle(fontSize: big ? 26 : 22)),
            const Spacer(),
            Text(
              days == 0 ? 'Today!' : '$days ${days == 1 ? 'day' : 'days'}',
              style: (big ? context.tt.headlineSmall : context.tt.titleLarge)?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodyMedium?.copyWith(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.events,
    required this.onMonth,
    required this.onDay,
    required this.onLongPress,
  });

  final DateTime month;
  final DateTime selected;
  final List<Countdown> events;
  final ValueChanged<DateTime> onMonth;
  final ValueChanged<DateTime> onDay;
  final ValueChanged<DateTime> onLongPress;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final lead = first.weekday - 1; // Monday first
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cells = ((lead + daysInMonth) / 7).ceil() * 7;
    final today = DateTime.now();
    final weekdays = [for (var i = 0; i < 7; i++) DateFormat('E').format(DateTime(2024, 1, 1 + i)).substring(0, 2)];

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: () => onMonth(DateTime(month.year, month.month - 1)),
            ),
            Expanded(
              child: Text(DateFormat('MMMM yyyy').format(month), textAlign: TextAlign.center, style: context.tt.titleMedium),
            ),
            IconButton(
              tooltip: 'Next month',
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: () => onMonth(DateTime(month.year, month.month + 1)),
            ),
          ],
        ),
        Row(
          children: [
            for (final w in weekdays)
              Expanded(
                child: Text(w, textAlign: TextAlign.center, style: context.tt.labelSmall?.copyWith(color: context.cc.muted)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.95,
          children: [
            for (var i = 0; i < cells; i++)
              if (i < lead || i >= lead + daysInMonth)
                const SizedBox.shrink()
              else
                _DayCell(
                  day: DateTime(month.year, month.month, i - lead + 1),
                  selected: _isSameDay(selected, DateTime(month.year, month.month, i - lead + 1)),
                  today: _isSameDay(today, DateTime(month.year, month.month, i - lead + 1)),
                  events: events.where((e) => e.occursOn(DateTime(month.year, month.month, i - lead + 1))).toList(),
                  onTap: onDay,
                  onLongPress: onLongPress,
                ),
          ],
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.today,
    required this.events,
    required this.onTap,
    required this.onLongPress,
  });

  final DateTime day;
  final bool selected;
  final bool today;
  final List<Countdown> events;
  final ValueChanged<DateTime> onTap;
  final ValueChanged<DateTime> onLongPress;

  @override
  Widget build(BuildContext context) {
    final accent = context.cc.accent;
    return Semantics(
      button: true,
      selected: selected,
      label: '${DateFormat('EEEE d MMMM').format(day)}, ${events.length} event${events.length == 1 ? '' : 's'}',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onTap(day),
        onLongPress: () => onLongPress(day),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: selected ? accent : null,
            borderRadius: BorderRadius.circular(12),
            border: today && !selected ? Border.all(color: accent, width: 1.5) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${day.day}',
                style: context.tt.bodyMedium?.copyWith(
                  color: selected ? Colors.white : null,
                  fontWeight: today || selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: 6,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final e in events.take(3))
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? Colors.white : categoryColor(e.category)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One event in a list. [day] shows "Day 2 of 4" for multi-day events.
class EventTile extends StatelessWidget {
  const EventTile({required this.event, super.key, this.day});

  final Countdown event;
  final DateTime? day;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final now = DateTime.now();
    final start = e.nextOccurrence(now);
    final when = [
      if (day == null) DateFormat('EEE d MMM').format(e.repeatsYearly ? start : e.date),
      if (e.endDate != null) 'until ${DateFormat('d MMM').format(e.endDate!)}',
      if (e.hasTime && e.endDate == null) TimeOfDay.fromDateTime(e.date).format(context) else if (day != null) 'All day',
      if (e.repeatsYearly) 'every year',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: CloserCard(
        onTap: () => context.push('/calendar/edit?id=${e.id}'),
        padding: const EdgeInsets.all(Space.s + 4),
        child: Row(
          children: [
            Container(width: 4, height: 40, decoration: BoxDecoration(color: categoryColor(e.category), borderRadius: BorderRadius.circular(4))),
            const SizedBox(width: Space.s + 4),
            Text(e.emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: Space.s + 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.title, style: context.tt.titleSmall),
                  Text(
                    [when, if (e.place.isNotEmpty) e.place, if (e.isDate && e.isVirtual) 'online' else if (e.isDate) 'in person'].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
                  ),
                ],
              ),
            ),
            if (e.showAsCountdown && !e.isPast(now))
              Text('${e.daysLeft(now)}d', style: context.tt.titleMedium?.copyWith(color: context.cc.secondary)),
          ],
        ),
      ),
    );
  }
}

/// Add or edit a calendar event (or countdown, or date).
class EventEditScreen extends ConsumerStatefulWidget {
  const EventEditScreen({
    super.key,
    this.eventId,
    this.initialDate,
    this.category,
    this.title,
    this.emoji,
    this.isVirtual,
  });

  final String? eventId;
  final DateTime? initialDate;
  final EventCategory? category;
  final String? title;
  final String? emoji;
  final bool? isVirtual;

  @override
  ConsumerState<EventEditScreen> createState() => _EventEditScreenState();
}

class _EventEditScreenState extends ConsumerState<EventEditScreen> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _place = TextEditingController();
  late DateTime _date;
  DateTime? _endDate;
  TimeOfDay _time = const TimeOfDay(hour: 19, minute: 0);
  bool _allDay = false;
  EventCategory _category = EventCategory.other;
  String _emoji = '📅';
  bool _yearly = false;
  bool _countdown = false;
  bool _virtual = false;
  int _remind = 60; // minutes before
  Countdown? _existing;
  bool _busy = false;

  static const _emojis = ['💑', '🤗', '✈️', '📞', '🎂', '💍', '🍽️', '🎬', '🎉', '🏖️', '🎄', '🎓', '🏠', '❤️', '🎁', '📅'];

  /// Reminder presets, in minutes before the moment.
  static const _remindPresets = [0, 5, 15, 30, 60, 120, 1440, 2880, 4320, 10080];

  /// All-day events are reminded by the daily job, so whole days only.
  static const _dayPresets = [0, 1440, 2880, 4320, 10080];

  bool get _isAllDay => _allDay || _endDate != null;

  /// All-day reminders round down to whole days.
  int get _effectiveRemind => _isAllDay ? (_remind ~/ Countdown.minutesPerDay) * Countdown.minutesPerDay : _remind;
  static const _customRemind = -1;

  DateTime get _moment =>
      _isAllDay ? DateTime(_date.year, _date.month, _date.day) : DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  /// A one-off event has to be in the future when it's new.
  bool get _inPast {
    if (_yearly || _existing != null) return false;
    final last = _endDate ?? _moment;
    final end = _isAllDay ? DateTime(last.year, last.month, last.day, 23, 59) : last;
    return end.isBefore(DateTime.now());
  }

  @override
  void initState() {
    super.initState();
    final list = ref.read(eventsProvider).value ?? const <Countdown>[];
    _existing = list.where((c) => c.id == widget.eventId).firstOrNull;
    final e = _existing;
    final now = DateTime.now();
    _date = widget.initialDate ?? DateTime(now.year, now.month, now.day + 1);
    if (e != null) {
      _title.text = e.title;
      _note.text = e.note;
      _place.text = e.place;
      _date = e.date;
      _endDate = e.endDate;
      _allDay = !e.hasTime;
      if (e.hasTime) _time = TimeOfDay.fromDateTime(e.date);
      _category = e.category;
      _emoji = e.emoji;
      _yearly = e.repeatsYearly;
      _countdown = e.showAsCountdown;
      _virtual = e.isVirtual;
      _remind = e.remindMinutesBefore;
    } else {
      _category = widget.category ?? EventCategory.other;
      _emoji = widget.emoji ?? _category.emoji;
      _title.text = widget.title ?? '';
      _virtual = widget.isVirtual ?? false;
      _applyCategoryDefaults(_category, keepEmoji: widget.emoji != null);
    }
  }

  void _applyCategoryDefaults(EventCategory c, {bool keepEmoji = false}) {
    _category = c;
    if (!keepEmoji) _emoji = c.emoji;
    switch (c) {
      case EventCategory.birthday || EventCategory.anniversary:
        _yearly = true;
        _allDay = true;
        _countdown = true;
        _remind = Countdown.minutesPerDay;
      case EventCategory.trip:
        _allDay = true;
        _countdown = true;
        _remind = Countdown.minutesPerDay;
      case EventCategory.date || EventCategory.meetup || EventCategory.call:
        _allDay = false;
        _remind = 60;
      case EventCategory.other:
        break;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _place.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final e = _existing;
    final ok = await runAction(
      context,
      () => ref.read(backendProvider).saveCountdown(
            Countdown(
              id: e?.id ?? '',
              title: _title.text.trim(),
              date: _moment,
              hasTime: !_isAllDay,
              emoji: _emoji,
              repeatsYearly: _yearly,
              remindMinutesBefore: _effectiveRemind,
              createdBy: e?.createdBy ?? '',
              category: _category,
              endDate: _endDate,
              note: _note.text.trim(),
              place: _place.text.trim(),
              isVirtual: _category == EventCategory.date && _virtual,
              showAsCountdown: _countdown,
              done: e?.done ?? false,
              ratings: e?.ratings ?? const {},
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
    if (picked != null && _isAllDay && picked % Countdown.minutesPerDay != 0 && mounted) {
      showToast(context, 'All-day reminders are in whole days');
    }
  }

  Widget _pickerRow(IconData icon, String text, VoidCallback onTap, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: Space.s),
        child: CloserCard(
          onTap: onTap,
          child: Row(
            children: [
              Icon(icon),
              const SizedBox(width: Space.m),
              Expanded(child: Text(text, style: context.tt.titleMedium)),
              trailing ?? const Icon(Icons.edit_rounded, size: 18),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final presets = _isAllDay ? _dayPresets : _remindPresets;
    final remind = _effectiveRemind;
    final remindValues = [...presets, if (!presets.contains(remind)) remind];
    final plus = ref.watch(isPlusProvider);
    final countdownsUsed = (ref.watch(countdownsProvider).value ?? const <Countdown>[]).length;
    final countdownLocked = !plus && !_countdown && !(_existing?.showAsCountdown ?? false) && countdownsUsed >= FreeLimits.countdowns;
    final editing = _existing != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit' : (_category == EventCategory.date ? 'Plan a date' : 'Add to calendar')),
        actions: [
          if (editing)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final yes = await confirm(context, title: 'Delete it?', body: '“${_existing!.title}” will be removed for both of you.', ok: 'Delete', destructive: true);
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
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in EventCategory.values)
                ChoiceChip(
                  avatar: Text(c.emoji),
                  label: Text(c.label),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _applyCategoryDefaults(c)),
                ),
            ],
          ),
          const SizedBox(height: Space.m),
          TextField(
            controller: _title,
            maxLength: Countdown.maxTitle,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'What’s happening?',
              hintText: switch (_category) {
                EventCategory.date => 'Dinner at Luigi’s',
                EventCategory.trip => 'Paris trip',
                EventCategory.call => 'Long call',
                EventCategory.birthday => 'Sam’s birthday',
                _ => 'Something to look forward to',
              },
            ),
            onChanged: (_) => setState(() {}),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final e in _emojis)
                  GestureDetector(
                    onTap: () => setState(() => _emoji = e),
                    child: Container(
                      width: 44,
                      margin: const EdgeInsets.only(right: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _emoji == e ? context.cc.accentTint : Colors.transparent,
                        border: Border.all(color: _emoji == e ? context.cc.accent : Colors.transparent, width: 2),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.m),
          if (_category == EventCategory.date) ...[
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('In person'), icon: Icon(Icons.favorite_rounded)),
                ButtonSegment(value: true, label: Text('Online'), icon: Icon(Icons.videocam_rounded)),
              ],
              selected: {_virtual},
              onSelectionChanged: (v) => setState(() => _virtual = v.first),
            ),
            const SizedBox(height: Space.m),
          ],
          _pickerRow(Icons.event_rounded, DateFormat('EEEE d MMMM yyyy').format(_date), () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(1950),
              lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
            );
            if (d != null) {
              setState(() {
                _date = d;
                if (_endDate != null && _endDate!.isBefore(d)) _endDate = null;
              });
            }
          }),
          if (!_allDay && _endDate == null)
            _pickerRow(Icons.schedule_rounded, _time.format(context), () async {
              final t = await showTimePicker(context: context, initialTime: _time);
              if (t != null) setState(() => _time = t);
            }),
          if (_endDate != null)
            _pickerRow(
              Icons.date_range_rounded,
              'Until ${DateFormat('EEEE d MMMM yyyy').format(_endDate!)}',
              () async {
                final d = await showDatePicker(context: context, initialDate: _endDate, firstDate: _date, lastDate: _date.add(const Duration(days: 365)));
                if (d != null) setState(() => _endDate = d);
              },
              trailing: IconButton(
                tooltip: 'Single day',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() => _endDate = null),
              ),
            ),
          if (_inPast)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s, left: Space.s),
              child: Text('That time has already passed', style: context.tt.bodySmall?.copyWith(color: context.cs.error)),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('All day'),
            value: _allDay || _endDate != null,
            onChanged: _endDate != null ? null : (v) => setState(() => _allDay = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Lasts several days'),
            subtitle: const Text('Trips, holidays, visits'),
            value: _endDate != null,
            onChanged: (v) => setState(() {
              _endDate = v ? _date.add(const Duration(days: 2)) : null;
              if (v) _allDay = true;
            }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Repeats every year'),
            subtitle: const Text('Birthdays, anniversaries'),
            value: _yearly,
            onChanged: (v) => setState(() => _yearly = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show as a countdown'),
            subtitle: Text(
              countdownLocked
                  ? 'Free plan includes ${FreeLimits.countdowns} countdowns'
                  : 'Big on Home and on the countdown widget',
            ),
            value: _countdown,
            onChanged: (v) {
              if (v && countdownLocked) {
                context.push('/paywall?from=countdowns').ignore();
                return;
              }
              setState(() => _countdown = v);
            },
          ),
          TextField(
            controller: _place,
            maxLength: Countdown.maxPlace,
            decoration: InputDecoration(
              labelText: _virtual && _category == EventCategory.date ? 'Call link or app (optional)' : 'Where (optional)',
              prefixIcon: Icon(_virtual ? Icons.link_rounded : Icons.place_rounded),
            ),
          ),
          TextField(
            controller: _note,
            maxLength: Countdown.maxNote,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Notes (optional)', prefixIcon: Icon(Icons.notes_rounded)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Remind us'),
            trailing: DropdownButton<int>(
              value: remind,
              underline: const SizedBox.shrink(),
              items: [
                for (final m in remindValues)
                  DropdownMenuItem(value: m, child: Text(Countdown.describeRemind(m, hasTime: !_isAllDay))),
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
          Text(
            remind == 0
                ? 'You both get a notification ${_isAllDay ? 'on the day' : 'at the time'}.'
                : 'You both get a notification ${Countdown.describeRemind(remind)}, and again ${_isAllDay ? 'on the day' : 'at the time'}.',
            style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
          ),
          const SizedBox(height: Space.l),
          CloserButton(
            label: editing ? 'Save' : 'Add to our calendar',
            kind: CloserButtonKind.accent,
            loading: _busy,
            onPressed: _title.text.trim().isEmpty || _inPast ? null : _save,
          ),
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
