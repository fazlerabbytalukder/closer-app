import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/data/closer_backend.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/ads.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/soft_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

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
      ..sort(
        (a, b) => (a.hasTime ? a.date.hour * 60 + a.date.minute : -1).compareTo(
          b.hasTime ? b.date.hour * 60 + b.date.minute : -1,
        ),
      );
    final upcoming = events.where((e) => !e.isPast(now) && e.daysLeft(now) <= 60).toList()
      ..sort((a, b) => a.nextMoment(now).compareTo(b.nextMoment(now)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Our calendar'),
        actions: [IconButton(tooltip: 'Add to calendar', icon: const Icon(Icons.add_rounded), onPressed: _add)],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add to calendar',
        onPressed: _add,
        child: const Icon(Icons.add_rounded),
      ),
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
            Text(
              'Nothing planned. Tap Add to plan something 💫',
              style: context.tt.bodyMedium?.copyWith(color: context.cc.muted),
            )
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
          colors: big
              ? context.cc.gradient
              : [categoryColor(c.category), categoryColor(c.category).withValues(alpha: 0.7)],
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
              style: (big ? context.tt.headlineSmall : context.tt.titleLarge)?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              c.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.tt.bodyMedium?.copyWith(color: Colors.white),
            ),
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
              child: Text(
                DateFormat('MMMM yyyy').format(month),
                textAlign: TextAlign.center,
                style: context.tt.titleMedium,
              ),
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
                child: Text(
                  w,
                  textAlign: TextAlign.center,
                  style: context.tt.labelSmall?.copyWith(color: context.cc.muted),
                ),
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
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected ? Colors.white : categoryColor(e.category),
                        ),
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
      if (e.hasTime && e.endDate == null)
        TimeOfDay.fromDateTime(e.date).format(context)
      else if (day != null)
        'All day',
      if (e.repeatsYearly) 'every year',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: CloserCard(
        onTap: () => context.push('/calendar/edit?id=${e.id}'),
        padding: const EdgeInsets.all(Space.s + 4),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 40,
              decoration: BoxDecoration(color: categoryColor(e.category), borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: Space.s + 4),
            Text(e.emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: Space.s + 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.title, style: context.tt.titleSmall),
                  Text(
                    [
                      when,
                      if (e.place.isNotEmpty) e.place,
                      if (e.isDate && e.isVirtual) 'online' else if (e.isDate) 'in person',
                    ].join(' · '),
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

  static const _emojis = [
    '💑',
    '🤗',
    '✈️',
    '📞',
    '🎂',
    '💍',
    '🍽️',
    '🎬',
    '🎉',
    '🏖️',
    '🎄',
    '🎓',
    '🏠',
    '❤️',
    '🎁',
    '📅',
  ];

  /// Reminder presets, in minutes before the moment.
  static const _remindPresets = [0, 5, 15, 30, 60, 120, 1440, 2880, 4320, 10080];

  /// All-day events are reminded by the daily job, so whole days only.
  static const _dayPresets = [0, 1440, 2880, 4320, 10080];

  bool get _isAllDay => _allDay || _endDate != null;

  /// All-day reminders round down to whole days.
  int get _effectiveRemind => _isAllDay ? (_remind ~/ Countdown.minutesPerDay) * Countdown.minutesPerDay : _remind;
  static const _customRemind = -1;

  DateTime get _moment => _isAllDay
      ? DateTime(_date.year, _date.month, _date.day)
      : DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

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
      () => ref
          .read(backendProvider)
          .saveCountdown(
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

  /// "Remind us" choices as a soft bottom sheet: one card per option, the
  /// current one ringed and ticked, then "Custom…".
  Future<void> _pickRemind(List<int> values, int current) async {
    IconData iconFor(int m) => switch (m) {
      0 => Icons.notifications_active_outlined,
      < 60 => Icons.timer_outlined,
      < Countdown.minutesPerDay => Icons.schedule_rounded,
      < 7 * Countdown.minutesPerDay => Icons.today_outlined,
      _ => Icons.date_range_outlined,
    };
    SoftTone toneFor(int m) => switch (m) {
      0 => SoftTone.pink,
      < Countdown.minutesPerDay => SoftTone.mint,
      < 7 * Countdown.minutesPerDay => SoftTone.violet,
      _ => SoftTone.blue,
    };
    final picked = await showSoftSheet<int>(
      context,
      header: SoftSheetHeader(
        icon: const Icon(Icons.notifications_none_rounded),
        tone: SoftTone.yellow,
        title: 'Remind us',
        subtitle: _isAllDay
            ? 'You both get a notification, and again on the day.'
            : 'You both get a notification, and again at the time.',
      ),
      children: [
        for (final m in values)
          Builder(
            builder: (ctx) => SoftOptionTile(
              icon: iconFor(m),
              tone: toneFor(m),
              title: Countdown.describeRemind(m, hasTime: !_isAllDay),
              selected: m == current,
              onTap: () => Navigator.pop(ctx, m),
            ),
          ),
        Builder(
          builder: (ctx) => SoftOptionTile(
            icon: Icons.tune_rounded,
            tone: SoftTone.yellow,
            title: 'Custom…',
            subtitle: 'Pick minutes, hours or days',
            onTap: () => Navigator.pop(ctx, _customRemind),
          ),
        ),
      ],
    );
    if (picked == null || !mounted) return;
    if (picked == _customRemind) {
      await _pickCustomRemind();
    } else {
      setState(() => _remind = picked);
    }
  }

  Future<void> _pickCustomRemind() async {
    final picked = await showDialog<int>(
      context: context,
      builder: (_) => _CustomRemindDialog(initialMinutes: _remind),
    );
    if (picked != null) setState(() => _remind = picked);
    if (picked != null && _isAllDay && picked % Countdown.minutesPerDay != 0 && mounted) {
      showToast(context, 'All-day reminders are in whole days');
    }
  }

  /// Date / time row: white card, tinted icon tile, bold text, pencil.
  Widget _pickerRow(IconData icon, SoftTone tone, String text, VoidCallback onTap, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _SoftCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      child: Row(
        children: [
          IconTile(icon: icon, tone: tone, size: 42, filled: true),
          const SizedBox(width: 14),
          Expanded(
            child: Text(text, style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          ),
          trailing ?? Icon(Icons.edit_outlined, size: 20, color: context.cs.onSurface),
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
    final countdownLocked =
        !plus && !_countdown && !(_existing?.showAsCountdown ?? false) && countdownsUsed >= FreeLimits.countdowns;
    final editing = _existing != null;

    final dark = Theme.of(context).brightness == Brightness.dark;
    final hint = switch (_category) {
      EventCategory.date => 'Dinner at Luigi’s',
      EventCategory.trip => 'Paris trip',
      EventCategory.call => 'Long call',
      EventCategory.birthday => 'Sam’s birthday',
      _ => 'What’s happening?',
    };

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          VioletPageHeader(
            title: editing ? 'Edit' : (_category == EventCategory.date ? 'Plan a date' : 'Add to calendar'),
            actions: [
              if (editing)
                IconButton(
                  tooltip: 'Delete',
                  color: Colors.white,
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () async {
                    final yes = await confirm(
                      context,
                      title: 'Delete it?',
                      body: '“${_existing!.title}” will be removed for both of you.',
                      ok: 'Delete',
                      destructive: true,
                    );
                    if (!yes || !context.mounted) return;
                    final ok = await runAction(context, () => ref.read(backendProvider).deleteCountdown(_existing!.id));
                    if (ok && context.mounted) context.pop();
                  },
                ),
            ],
            // Pink card on the header edge: the title field, the chosen
            // date and time, and the mascot (Figma "add event calendar").
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFFF8CC6), Color(0xFFFFA9D3)]),
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(color: Color(0x66FF5C9E), blurRadius: 30, offset: Offset(0, 18), spreadRadius: -12),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -6,
                    bottom: -22,
                    child: Image.asset('assets/home/progress_mascot.png', width: 96, height: 106),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 90, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _title,
                          maxLength: Countdown.maxTitle,
                          textCapitalization: TextCapitalization.sentences,
                          style: context.tt.bodyLarge?.copyWith(color: Brand.ink, fontWeight: FontWeight.w700),
                          decoration: InputDecoration(
                            hintText: hint,
                            hintStyle: context.tt.bodyLarge?.copyWith(
                              color: Brand.ink.withValues(alpha: 0.55),
                              fontWeight: FontWeight.w600,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            isDense: true,
                            counterText: '',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(color: Brand.royal, width: 1.6),
                            ),
                            suffixIcon: Padding(
                              padding: const EdgeInsets.only(right: 14),
                              child: Text(
                                '${_title.text.length}/${Countdown.maxTitle}',
                                style: context.tt.labelSmall?.copyWith(
                                  color: Brand.ink.withValues(alpha: 0.6),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            suffixIconConstraints: const BoxConstraints(minHeight: 20, minWidth: 20),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(
                            [
                              DateFormat('EEEE d MMMM yyyy').format(_date),
                              if (_endDate != null)
                                'Until ${DateFormat('EEEE d MMMM yyyy').format(_endDate!)}'
                              else if (!_allDay)
                                _time.format(context)
                              else
                                'All day',
                            ].join('\n'),
                            style: context.tt.titleSmall?.copyWith(
                              color: Brand.ink,
                              fontWeight: FontWeight.w800,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 10,
                  children: [
                    for (final c in EventCategory.values)
                      _ChoicePill(
                        leading: Text(c.emoji, style: const TextStyle(fontSize: 15)),
                        label: c.label,
                        selected: _category == c,
                        onTap: () => setState(() => _applyCategoryDefaults(c)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final e in _emojis)
                        GestureDetector(
                          onTap: () => setState(() => _emoji = e),
                          child: Container(
                            width: 42,
                            margin: const EdgeInsets.only(right: 4),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _emoji == e ? SoftTone.violet.fill(context) : Colors.transparent,
                              border: Border.all(
                                color: _emoji == e ? context.cs.primary : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Text(e, style: const TextStyle(fontSize: 21)),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (_category == EventCategory.date) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _ChoicePill(
                          leading: const Icon(Icons.favorite_rounded, size: 17),
                          label: 'In person',
                          selected: !_virtual,
                          expand: true,
                          onTap: () => setState(() => _virtual = false),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ChoicePill(
                          leading: const Icon(Icons.videocam_rounded, size: 18),
                          label: 'Online',
                          selected: _virtual,
                          expand: true,
                          onTap: () => setState(() => _virtual = true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                _pickerRow(
                  Icons.calendar_today_outlined,
                  SoftTone.pink,
                  DateFormat('EEEE d MMMM yyyy').format(_date),
                  () async {
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
                  },
                ),
                if (!_allDay && _endDate == null)
                  _pickerRow(Icons.schedule_rounded, SoftTone.mint, _time.format(context), () async {
                    final t = await showTimePicker(context: context, initialTime: _time);
                    if (t != null) setState(() => _time = t);
                  }),
                if (_endDate != null)
                  _pickerRow(
                    Icons.date_range_rounded,
                    SoftTone.violet,
                    'Until ${DateFormat('EEEE d MMMM yyyy').format(_endDate!)}',
                    () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _endDate,
                        firstDate: _date,
                        lastDate: _date.add(const Duration(days: 365)),
                      );
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
                    child: Text(
                      'That time has already passed',
                      style: context.tt.bodySmall?.copyWith(color: context.cs.error, fontWeight: FontWeight.w700),
                    ),
                  ),
                const SizedBox(height: 4),
                // All four switches in one white card, split by hairlines.
                _SoftCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _ToggleRow(
                        title: 'All day',
                        value: _allDay || _endDate != null,
                        onChanged: _endDate != null ? null : (v) => setState(() => _allDay = v),
                      ),
                      const _Hairline(),
                      _ToggleRow(
                        title: 'Lasts several days',
                        subtitle: 'Trips, holidays, visits',
                        value: _endDate != null,
                        onChanged: (v) => setState(() {
                          _endDate = v ? _date.add(const Duration(days: 2)) : null;
                          if (v) _allDay = true;
                        }),
                      ),
                      const _Hairline(),
                      _ToggleRow(
                        title: 'Repeats every year',
                        subtitle: 'Birthdays, anniversaries',
                        value: _yearly,
                        onChanged: (v) => setState(() => _yearly = v),
                      ),
                      const _Hairline(),
                      _ToggleRow(
                        title: 'Show as a countdown',
                        subtitle: countdownLocked
                            ? 'Free plan includes ${FreeLimits.countdowns} countdowns'
                            : 'Big on Home and on the countdown widget',
                        value: _countdown,
                        onChanged: (v) {
                          if (v && countdownLocked) {
                            context.push('/paywall?from=countdowns').ignore();
                            return;
                          }
                          setState(() => _countdown = v);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _FieldCard(
                  controller: _place,
                  maxLength: Countdown.maxPlace,
                  icon: _virtual ? Icons.link_rounded : Icons.place_outlined,
                  hint: _virtual && _category == EventCategory.date
                      ? 'Call link or app (optional)'
                      : 'Where (optional)',
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 12),
                _FieldCard(
                  controller: _note,
                  maxLength: Countdown.maxNote,
                  icon: Icons.notes_rounded,
                  hint: 'Notes (optional)',
                  multiline: true,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 12),
                _SoftCard(
                  padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                  onTap: () => _pickRemind(remindValues, remind),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Remind us', style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                      Text(
                        Countdown.describeRemind(remind, hasTime: !_isAllDay),
                        style: context.tt.labelLarge?.copyWith(color: context.cs.primary, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.expand_more_rounded, color: context.cs.primary),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  remind == 0
                      ? 'You both get a notification ${_isAllDay ? 'on the day' : 'at the time'}.'
                      : 'You both get a notification ${Countdown.describeRemind(remind)}, and again ${_isAllDay ? 'on the day' : 'at the time'}.',
                  style: context.tt.bodySmall?.copyWith(color: context.cc.muted, height: 1.4),
                ),
                const SizedBox(height: 20),
                PillButton(
                  label: editing ? 'Save' : 'Add to our calendar',
                  loading: _busy,
                  glow: !dark,
                  onPressed: _title.text.trim().isEmpty || _inPast ? null : _save,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// White pill choice with a leading emoji or icon; solid violet when chosen.
class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
    this.expand = false,
  });

  final Widget? leading;
  final String label;
  final bool selected;
  final bool expand;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = selected ? Colors.white : context.cs.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          boxShadow: dark || selected ? null : softCardShadow,
        ),
        child: Material(
          color: selected ? Brand.royal : context.cc.card,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (leading case final l?) ...[
                    IconTheme.merge(
                      data: IconThemeData(color: fg),
                      child: l,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: context.tt.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// White rounded card with a soft shadow.
class _SoftCard extends StatelessWidget {
  const _SoftCard({required this.child, this.padding = const EdgeInsets.all(14), this.onTap});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.cc.card,
        borderRadius: BorderRadius.circular(22),
        boxShadow: dark ? null : softCardShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, indent: 16, endIndent: 16, color: context.cs.outlineVariant.withValues(alpha: 0.5));
}

/// Title (+ muted line) with a lavender / violet switch on the right.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.title, required this.value, required this.onChanged, this.subtitle});

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  if (subtitle != null) Text(subtitle!, style: context.tt.bodySmall?.copyWith(color: context.cc.muted)),
                ],
              ),
            ),
            SoftSwitch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// White card text field with a violet leading icon and the count inside.
class _FieldCard extends StatelessWidget {
  const _FieldCard({
    required this.controller,
    required this.maxLength,
    required this.icon,
    required this.hint,
    required this.onChanged,
    this.multiline = false,
  });

  final TextEditingController controller;
  final int maxLength;
  final IconData icon;
  final String hint;
  final bool multiline;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const none = OutlineInputBorder(borderSide: BorderSide.none);
    return Container(
      decoration: BoxDecoration(
        color: context.cc.card,
        borderRadius: BorderRadius.circular(22),
        boxShadow: dark ? null : softCardShadow,
      ),
      child: TextField(
        controller: controller,
        maxLength: maxLength,
        minLines: 1,
        maxLines: multiline ? 4 : 1,
        textCapitalization: multiline ? TextCapitalization.sentences : TextCapitalization.none,
        style: context.tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        onChanged: (_) => onChanged(),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: context.tt.bodyLarge?.copyWith(color: context.cc.muted, fontWeight: FontWeight.w600),
          counterText: '',
          border: none,
          enabledBorder: none,
          focusedBorder: none,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
          prefixIcon: Icon(icon, color: context.cs.primary, size: 22),
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(
              '${controller.text.length}/$maxLength',
              style: context.tt.labelSmall?.copyWith(color: context.cc.muted, fontWeight: FontWeight.w800),
            ),
          ),
          suffixIconConstraints: const BoxConstraints(minHeight: 20, minWidth: 20),
        ),
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
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SoftSheetHeader(
              icon: Icon(Icons.tune_rounded),
              tone: SoftTone.yellow,
              title: 'Remind us before',
              subtitle: 'How long before should we both get a nudge?',
              centered: true,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: context.tt.headlineSmall?.copyWith(fontSize: 26),
              decoration: softFieldDecoration(context, hint: 'How long before'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final (i, u) in _units.keys.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _ChoicePill(
                      label: u,
                      selected: _unit == u,
                      expand: true,
                      onTap: () => setState(() => _unit = u),
                    ),
                  ),
                ],
              ],
            ),
            if (minutes == null && _amount.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Pick something up to 60 days',
                  textAlign: TextAlign.center,
                  style: context.tt.bodySmall?.copyWith(color: context.cs.error, fontWeight: FontWeight.w700),
                ),
              ),
            const SizedBox(height: 20),
            PillButton(
              label: 'Set',
              height: 52,
              onPressed: minutes == null ? null : () => Navigator.pop(context, minutes),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: context.tt.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}
