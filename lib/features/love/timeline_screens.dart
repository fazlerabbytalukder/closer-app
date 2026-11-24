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

/// Stored moments plus a few the app knows about (the day you paired, your
/// anniversary, the first photo), oldest first.
final _allMomentsProvider = Provider<List<TimelineEntry>>((ref) {
  final pair = ref.watch(pairProvider).value;
  final stored = ref.watch(timelineProvider).value ?? const <TimelineEntry>[];
  final items = ref.watch(itemsProvider).value ?? const <Item>[];
  final couple = pair?.mode != PairMode.friends;
  final auto = <TimelineEntry>[
    if (pair?.anniversary case final a?)
      TimelineEntry(id: 'auto_anniversary', date: a, title: couple ? 'Together since this day' : 'Friends since this day', emoji: couple ? '💞' : '🤝', createdBy: '', auto: true),
    if (pair != null)
      TimelineEntry(id: 'auto_paired', date: pair.pairedAt, title: 'We connected on Duosy', emoji: '📲', createdBy: '', auto: true),
    if (items.isNotEmpty)
      () {
        final first = items.reduce((a, b) => a.createdAt.isBefore(b.createdAt) ? a : b);
        return TimelineEntry(
          id: 'auto_first_item',
          date: first.createdAt,
          title: 'Our first ${first.type == ItemType.note ? 'note' : first.type == ItemType.doodle ? 'doodle' : 'photo'} on Duosy',
          emoji: '📸',
          photoPath: first.type == ItemType.photo || first.type == ItemType.location ? first.thumbPath : null,
          createdBy: first.senderId,
          auto: true,
        );
      }(),
  ];
  return [...stored, ...auto]..sort((a, b) => a.date.compareTo(b.date));
});

class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moments = ref.watch(_allMomentsProvider);
    final stored = moments.where((m) => !m.auto).length;
    final pair = ref.watch(pairProvider).value;
    final title = pair?.mode == PairMode.friends ? 'Our friendship timeline' : 'Our love timeline';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/timeline/edit'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add a moment'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, 100),
        children: [
          if (stored == 0)
            CloserCard(
              color: context.cc.accentTint,
              child: Text(
                'Add the moments that matter: your first conversation, first date, trips, the day everything changed. Both of you can add and edit them.',
                style: context.tt.bodyMedium,
              ),
            ),
          const SizedBox(height: Space.s),
          for (final (i, m) in moments.indexed) ...[
            if (i == 0 || moments[i - 1].date.year != m.date.year) _YearMarker(year: m.date.year),
            _MomentRow(moment: m, last: i == moments.length - 1)
                .animate(delay: (40 * i).clamp(0, 400).ms)
                .fadeIn(duration: 300.ms)
                .moveX(begin: 16, end: 0, curve: Curves.easeOutCubic),
          ],
        ],
      ),
    );
  }
}

class _YearMarker extends StatelessWidget {
  const _YearMarker({required this.year});

  final int year;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.s, bottom: Space.s),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: context.cc.accent, borderRadius: BorderRadius.circular(999)),
            child: Text('$year', style: context.tt.labelLarge?.copyWith(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _MomentRow extends StatelessWidget {
  const _MomentRow({required this.moment, required this.last});

  final TimelineEntry moment;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final m = moment;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.cc.card,
                    border: Border.all(color: context.cc.accent, width: 2),
                  ),
                  child: Text(m.emoji, style: const TextStyle(fontSize: 18)),
                ),
                if (!last)
                  Expanded(
                    child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 2), color: context.cc.accent.withValues(alpha: 0.3)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Space.s),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: Space.m),
              child: CloserCard(
                onTap: m.auto ? null : () => context.push('/timeline/edit?id=${m.id}'),
                padding: const EdgeInsets.all(Space.s + 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(DateFormat('d MMMM yyyy').format(m.date), style: context.tt.labelMedium?.copyWith(color: context.cc.accent)),
                    const SizedBox(height: 2),
                    Text(m.title, style: context.tt.titleMedium),
                    if (m.note.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(m.note, style: context.tt.bodyMedium?.copyWith(color: context.cc.muted)),
                    ],
                    if (m.photoPath != null) ...[
                      const SizedBox(height: Space.s),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.small),
                        child: AspectRatio(aspectRatio: 16 / 10, child: StoredImage(m.photoPath)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Add or edit a moment.
class TimelineEditScreen extends ConsumerStatefulWidget {
  const TimelineEditScreen({super.key, this.entryId});

  final String? entryId;

  @override
  ConsumerState<TimelineEditScreen> createState() => _TimelineEditScreenState();
}

class _TimelineEditScreenState extends ConsumerState<TimelineEditScreen> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  String _emoji = '💞';
  String? _storedPhoto;
  String? _newPhoto;
  bool _removePhoto = false;
  bool _loaded = false;
  bool _busy = false;

  static const _emojis = ['💞', '💬', '☕', '💋', '✈️', '🏡', '💍', '🎂', '🌟', '🎉', '🌅', '🐶', '🎓', '🎄'];

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  TimelineEntry? get _existing => widget.entryId == null
      ? null
      : (ref.read(timelineProvider).value ?? const <TimelineEntry>[]).where((e) => e.id == widget.entryId).firstOrNull;

  void _load() {
    if (_loaded) return;
    final e = _existing;
    if (widget.entryId != null && e == null) return; // wait for data
    _loaded = true;
    if (e == null) return;
    _title.text = e.title;
    _note.text = e.note;
    _date = e.date;
    _emoji = e.emoji;
    _storedPhoto = e.photoPath;
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final backend = ref.read(backendProvider);
    final ok = await runAction(context, () async {
      var photo = _removePhoto ? null : _storedPhoto;
      if (_newPhoto != null) photo = await backend.uploadPhoto(_newPhoto!);
      await backend.saveTimelineEntry(
        TimelineEntry(
          id: widget.entryId ?? '',
          date: _date,
          title: _title.text,
          emoji: _emoji,
          note: _note.text,
          photoPath: photo,
          createdBy: _existing?.createdBy ?? '',
        ),
      );
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      hapticMedium();
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(timelineProvider);
    _load();
    final editing = widget.entryId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit moment' : 'New moment'),
        actions: [
          if (editing)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final ok = await confirm(context, title: 'Delete this moment?', body: 'It disappears for both of you.', ok: 'Delete', destructive: true);
                if (!ok || !context.mounted) return;
                final done = await runAction(context, () => ref.read(backendProvider).deleteTimelineEntry(widget.entryId!));
                if (done && context.mounted) context.pop();
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          if (!editing) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (e, t) in TimelineEntry.presets)
                  ActionChip(
                    label: Text('$e $t'),
                    onPressed: () => setState(() {
                      _emoji = e;
                      _title.text = t;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: Space.m),
          ],
          TextField(
            controller: _title,
            maxLength: TimelineEntry.maxTitle,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'What happened?'),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final e in _emojis)
                  GestureDetector(
                    onTap: () => setState(() => _emoji = e),
                    child: AnimatedContainer(
                      duration: 150.ms,
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
          const SizedBox(height: Space.s),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_rounded),
            title: Text(DateFormat('EEEE d MMMM yyyy').format(_date)),
            subtitle: const Text('Tap to change the date'),
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(1950), lastDate: DateTime.now().add(const Duration(days: 365 * 5)));
              if (d != null) setState(() => _date = d);
            },
          ),
          TextField(
            controller: _note,
            maxLength: TimelineEntry.maxNote,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'The story (optional)'),
          ),
          const SizedBox(height: Space.s),
          if (_newPhoto != null || (_storedPhoto == null || _removePhoto))
            PhotoField(path: _newPhoto, onChanged: (p) => setState(() => _newPhoto = p))
          else
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.small + 4),
                  child: AspectRatio(aspectRatio: 4 / 3, child: StoredImage(_storedPhoto)),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: IconButton.filledTonal(
                    tooltip: 'Remove photo',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() => _removePhoto = true),
                  ),
                ),
              ],
            ),
          const SizedBox(height: Space.l),
          CloserButton(label: editing ? 'Save' : 'Add to our timeline', kind: CloserButtonKind.accent, loading: _busy, onPressed: _save),
        ],
      ),
    );
  }
}
