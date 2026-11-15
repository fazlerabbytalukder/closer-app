import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Shared to-do lists (F13): tasks for you, for them or for both, with
/// due dates; tick them off together.
class TodoScreen extends ConsumerStatefulWidget {
  const TodoScreen({super.key});

  @override
  ConsumerState<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends ConsumerState<TodoScreen> {
  /// Selected list id; null = all lists.
  String? _list;
  bool _mineOnly = false;
  bool _showDone = false;

  static const _listEmojis = ['📝', '🏠', '🛒', '🧺', '✈️', '🎁', '💼', '🎉', '🐶', '💪'];

  Future<void> _editList([TodoList? existing]) async {
    final ctrl = TextEditingController(text: existing?.title ?? '');
    var emoji = existing?.emoji ?? _listEmojis.first;
    final result = await showDialog<(String, String)?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(existing == null ? 'New list' : 'Edit list'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLength: TodoList.maxTitle,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Groceries, Trip prep…'),
              ),
              Wrap(
                spacing: 4,
                children: [
                  for (final e in _listEmojis)
                    ChoiceChip(label: Text(e), selected: emoji == e, onSelected: (_) => setD(() => emoji = e)),
                ],
              ),
            ],
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () => Navigator.pop(ctx, ('', 'delete')),
                style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
                child: const Text('Delete list'),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, (ctrl.text.trim(), emoji)), child: const Text('Save')),
          ],
        ),
      ),
    );
    disposeAfterRoute(ctrl);
    if (result == null || !mounted) return;
    final backend = ref.read(backendProvider);
    if (result.$2 == 'delete' && existing != null) {
      final yes = await confirm(context, title: 'Delete “${existing.title}”?', body: 'Its tasks are deleted too, for both of you.', ok: 'Delete', destructive: true);
      if (yes && mounted) {
        final ok = await runAction(context, () => backend.deleteTodoList(existing.id));
        if (ok) setState(() => _list = null);
      }
      return;
    }
    String? id;
    final ok = await runAction(
      context,
      () async => id = await backend.saveTodoList(
        TodoList(id: existing?.id ?? '', title: result.$1, emoji: result.$2, createdBy: existing?.createdBy ?? ''),
      ),
    );
    if (ok && mounted) setState(() => _list = id);
  }

  Future<void> _editTodo(List<TodoList> lists, [Todo? existing]) async {
    var listId = existing?.listId ?? _list;
    if (lists.isEmpty) {
      String? created;
      final ok = await runAction(
        context,
        () async => created = await ref
            .read(backendProvider)
            .saveTodoList(const TodoList(id: '', title: 'Our to-dos', createdBy: '')),
      );
      if (!ok || !mounted) return;
      listId = created;
    }
    listId ??= lists.first.id;
    if (!mounted) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _TodoSheet(existing: existing, listId: listId!, lists: lists),
    );
    if (saved == true && mounted) hapticSoft();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authUidProvider).value;
    final lists = ref.watch(todoListsProvider).value ?? const <TodoList>[];
    final all = ref.watch(todosProvider).value ?? const <Todo>[];
    final now = DateTime.now();
    if (_list != null && !lists.any((l) => l.id == _list)) _list = null;
    final inScope = all.where((t) => (_list == null || t.listId == _list) && (!_mineOnly || t.isFor(me))).toList();
    final open = inScope.where((t) => !t.isDone).toList()
      ..sort((a, b) {
        final ad = a.due;
        final bd = b.due;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      });
    final done = inScope.where((t) => t.isDone).toList()..sort((a, b) => b.doneAt!.compareTo(a.doneAt!));
    final forMe = all.where((t) => !t.isDone && t.assignee == me).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Our to-dos'),
        actions: [
          IconButton(
            tooltip: _mineOnly ? 'Show everything' : 'Show only mine',
            icon: Icon(_mineOnly ? Icons.person_rounded : Icons.people_alt_rounded),
            onPressed: () => setState(() => _mineOnly = !_mineOnly),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editTodo(lists),
        icon: const Icon(Icons.add_task_rounded),
        label: const Text('Add a task'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, 100),
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(label: const Text('All'), selected: _list == null, onSelected: (_) => setState(() => _list = null)),
                ),
                for (final l in lists)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onLongPress: () => _editList(l),
                      child: ChoiceChip(
                        label: Text('${l.emoji} ${l.title}'),
                        selected: _list == l.id,
                        onSelected: (_) => setState(() => _list = l.id),
                      ),
                    ),
                  ),
                ActionChip(avatar: const Icon(Icons.add_rounded, size: 18), label: const Text('New list'), onPressed: _editList),
              ],
            ),
          ),
          if (forMe > 0 && !_mineOnly)
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: Text('$forMe task${forMe == 1 ? '' : 's'} for you', style: context.tt.titleSmall?.copyWith(color: context.cc.accent)),
            ),
          const SizedBox(height: Space.s),
          if (open.isEmpty && done.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: Space.xl),
              child: EmptyState(emoji: '✅', title: 'Nothing to do!', body: 'Add a task for yourself, for them, or for both of you.'),
            ),
          if (open.isEmpty && done.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.m),
              child: Text('All done here 🎉', textAlign: TextAlign.center, style: context.tt.titleMedium),
            ),
          for (final t in open) _TodoRow(todo: t, lists: lists, showList: _list == null, now: now, onEdit: () => _editTodo(lists, t)),
          if (done.isNotEmpty) ...[
            TextButton.icon(
              onPressed: () => setState(() => _showDone = !_showDone),
              icon: Icon(_showDone ? Icons.expand_less_rounded : Icons.expand_more_rounded),
              label: Text('Done (${done.length})'),
            ),
            if (_showDone)
              for (final t in done.take(50)) _TodoRow(todo: t, lists: lists, showList: _list == null, now: now, onEdit: () => _editTodo(lists, t)),
          ],
        ],
      ),
    );
  }
}

class _TodoRow extends ConsumerWidget {
  const _TodoRow({required this.todo, required this.lists, required this.showList, required this.now, required this.onEdit});

  final Todo todo;
  final List<TodoList> lists;
  final bool showList;
  final DateTime now;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authUidProvider).value;
    final name = ref.watch(partnerNameProvider);
    final t = todo;
    final list = lists.where((l) => l.id == t.listId).firstOrNull;
    final who = t.assignee == null ? 'Both' : (t.assignee == me ? 'You' : name);
    final overdue = t.isOverdue(now);
    final doneByOther = t.isDone && t.doneBy != null && t.doneBy != me;
    final meta = [
      if (showList && list != null) '${list.emoji} ${list.title}',
      if (t.due != null) (overdue ? 'Overdue · ' : 'Due ') + DateFormat('EEE d MMM').format(t.due!),
      if (doneByOther) 'Done by $name',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: CloserCard(
        onTap: onEdit,
        padding: const EdgeInsets.fromLTRB(4, 4, Space.s + 4, 4),
        child: Row(
          children: [
            Checkbox(
              value: t.isDone,
              shape: const CircleBorder(),
              onChanged: (v) {
                hapticSoft();
                runAction(context, () => ref.read(backendProvider).setTodoDone(t.id, done: v ?? false)).ignore();
              },
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: 250.ms,
                    style: (context.tt.bodyLarge ?? const TextStyle()).copyWith(
                      decoration: t.isDone ? TextDecoration.lineThrough : null,
                      color: t.isDone ? context.cc.muted : null,
                    ),
                    child: Text(t.text),
                  ),
                  if (meta.isNotEmpty)
                    Text(
                      meta.join(' · '),
                      style: context.tt.bodySmall?.copyWith(color: overdue ? context.cs.error : context.cc.muted),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: t.assignee == me ? context.cc.accentTint : context.cc.secondaryTint,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(who, style: context.tt.labelSmall),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodoSheet extends ConsumerStatefulWidget {
  const _TodoSheet({required this.listId, required this.lists, this.existing});

  final Todo? existing;
  final String listId;
  final List<TodoList> lists;

  @override
  ConsumerState<_TodoSheet> createState() => _TodoSheetState();
}

enum _Who { me, partner, both }

class _TodoSheetState extends ConsumerState<_TodoSheet> {
  late final _text = TextEditingController(text: widget.existing?.text ?? '');
  late String _listId = widget.listId;
  late DateTime? _due = widget.existing?.due;
  late _Who _who;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final me = ref.read(authUidProvider).value;
    final a = widget.existing?.assignee;
    _who = a == null ? _Who.both : (a == me ? _Who.me : _Who.partner);
    if (widget.existing == null) _who = _Who.me;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final me = ref.read(authUidProvider).value;
    final partner = ref.read(partnerUidProvider);
    setState(() => _busy = true);
    final e = widget.existing;
    final ok = await runAction(
      context,
      () => ref.read(backendProvider).saveTodo(
            Todo(
              id: e?.id ?? '',
              listId: _listId,
              text: _text.text,
              assignee: switch (_who) {
                _Who.me => me,
                _Who.partner => partner,
                _Who.both => null,
              },
              due: _due,
              createdBy: e?.createdBy ?? '',
            ),
          ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(partnerNameProvider);
    final e = widget.existing;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, MediaQuery.viewInsetsOf(context).bottom + Space.m),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(e == null ? 'New task' : 'Edit task', style: context.tt.titleLarge)),
              if (e != null)
                IconButton(
                  tooltip: 'Delete task',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () async {
                    final ok = await runAction(context, () => ref.read(backendProvider).deleteTodo(e.id));
                    if (ok && context.mounted) Navigator.pop(context, true);
                  },
                ),
            ],
          ),
          TextField(
            controller: _text,
            autofocus: e == null,
            maxLength: Todo.maxText,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'What needs doing?'),
            onSubmitted: (_) => _save(),
          ),
          if (widget.lists.length > 1)
            DropdownButtonFormField<String>(
              initialValue: widget.lists.any((l) => l.id == _listId) ? _listId : widget.lists.first.id,
              decoration: const InputDecoration(labelText: 'List'),
              items: [for (final l in widget.lists) DropdownMenuItem(value: l.id, child: Text('${l.emoji} ${l.title}'))],
              onChanged: (v) => setState(() => _listId = v ?? _listId),
            ),
          const SizedBox(height: Space.m),
          SegmentedButton<_Who>(
            segments: [
              const ButtonSegment(value: _Who.me, label: Text('Me')),
              ButtonSegment(value: _Who.partner, label: Text(name, overflow: TextOverflow.ellipsis)),
              const ButtonSegment(value: _Who.both, label: Text('Both')),
            ],
            selected: {_who},
            onSelectionChanged: (v) => setState(() => _who = v.first),
          ),
          const SizedBox(height: Space.s),
          Wrap(
            spacing: 6,
            children: [
              for (final (label, days) in [('Today', 0), ('Tomorrow', 1), ('This weekend', -1)])
                ChoiceChip(
                  label: Text(label),
                  selected: _due != null && _sameDay(_due!, _dueFor(days)),
                  onSelected: (_) => setState(() => _due = _dueFor(days)),
                ),
              ActionChip(
                avatar: const Icon(Icons.event_rounded, size: 18),
                label: Text(_due == null ? 'Pick a date' : DateFormat('EEE d MMM').format(_due!)),
                onPressed: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(context: context, initialDate: _due ?? now, firstDate: now.subtract(const Duration(days: 365)), lastDate: now.add(const Duration(days: 365 * 3)));
                  if (d != null) setState(() => _due = d);
                },
              ),
              if (_due != null) ActionChip(label: const Text('No date'), onPressed: () => setState(() => _due = null)),
            ],
          ),
          const SizedBox(height: Space.m),
          CloserButton(label: e == null ? 'Add task' : 'Save', loading: _busy, onPressed: _save),
        ],
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// 0 = today, 1 = tomorrow, -1 = the coming Saturday.
  static DateTime _dueFor(int days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (days >= 0) return today.add(Duration(days: days));
    final toSat = (DateTime.saturday - now.weekday) % 7;
    return today.add(Duration(days: toSat));
  }
}
