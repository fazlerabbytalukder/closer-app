import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/features/love/love_widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

/// Colours of each shrine theme: (top, bottom, ink).
const _themes = <String, (Color, Color, Color)>{
  'rose': (Color(0xFFFF8FB1), Color(0xFFFFE3EA), Color(0xFF5A1F33)),
  'lavender': (Color(0xFF9F8CFF), Color(0xFFEFEBFF), Color(0xFF2E2470)),
  'sunset': (Color(0xFFFFA26B), Color(0xFFFFF0E0), Color(0xFF5A2A12)),
  'midnight': (Color(0xFF1E2550), Color(0xFF3A3F7A), Color(0xFFF2F4FA)),
  'mint': (Color(0xFF5DC9A0), Color(0xFFE3F7EE), Color(0xFF14412F)),
};

/// "My love shrine": a space you build for your person, and one they build
/// for you.
class ShrineScreen extends ConsumerWidget {
  const ShrineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(partnerNameProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Love shrine'),
          bottom: TabBar(tabs: [Tab(text: 'From $name'), Tab(text: 'For $name')]),
        ),
        body: const TabBarView(children: [_PartnerShrine(), _MyShrine()]),
      ),
    );
  }
}

class _PartnerShrine extends ConsumerWidget {
  const _PartnerShrine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = ref.watch(partnerUidProvider);
    final name = ref.watch(partnerNameProvider);
    final shrine = partner == null ? null : ref.watch(shrinesProvider).value?[partner];
    if (shrine == null || shrine.isEmpty) {
      return EmptyState(
        emoji: '🕯️',
        title: '$name hasn’t built your shrine yet',
        body: 'Build one for them first. Maybe they’ll take the hint 😉',
      );
    }
    return _ShrineView(shrine: shrine, heading: shrine.title.isEmpty ? 'Made for you by $name' : shrine.title, editable: false);
  }
}

class _MyShrine extends ConsumerWidget {
  const _MyShrine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authUidProvider).value;
    final name = ref.watch(partnerNameProvider);
    if (me == null) return const SizedBox.shrink();
    final shrine = ref.watch(shrinesProvider).value?[me] ?? Shrine(ownerUid: me);
    return _ShrineView(shrine: shrine, heading: shrine.title.isEmpty ? 'For $name, with love' : shrine.title, editable: true);
  }
}

class _ShrineView extends ConsumerWidget {
  const _ShrineView({required this.shrine, required this.heading, required this.editable});

  final Shrine shrine;
  final String heading;
  final bool editable;

  Future<void> _save(BuildContext context, WidgetRef ref, Shrine next) async {
    await runAction(context, () => ref.read(backendProvider).saveShrine(next));
  }

  Future<String?> _pickAndUpload(BuildContext context, WidgetRef ref) async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2000, maxHeight: 2000, imageQuality: 92);
    if (x == null || !context.mounted) return null;
    String? path;
    final ok = await runAction(context, () async => path = await ref.read(backendProvider).uploadPhoto(x.path));
    return ok ? path : null;
  }

  Future<String?> _askText(BuildContext context, {required String title, String initial = '', String hint = '', int max = Shrine.maxText}) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: max,
          maxLines: 4,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    ).whenComplete(() => disposeAfterRoute(ctrl));
  }

  Future<void> _addFavorite(BuildContext context, WidgetRef ref) async {
    final label = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.m),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final l in Shrine.favoriteLabels) ActionChip(label: Text('Favourite ${l.toLowerCase()}'), onPressed: () => Navigator.pop(ctx, l)),
            ],
          ),
        ),
      ),
    );
    if (label == null || !context.mounted) return;
    final value = await _askText(context, title: 'Their favourite ${label.toLowerCase()}', hint: 'Write it here');
    if (value == null || value.isEmpty || !context.mounted) return;
    await _save(context, ref, shrine.copyWith(favorites: [...shrine.favorites, ShrineFavorite(label, value)]));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (top, bottom, ink) = _themes[shrine.theme] ?? _themes['rose']!;
    final items = ref.watch(itemsProvider).value ?? const <Item>[];
    final pinned = [
      for (final id in shrine.pinnedItemIds) ?items.where((i) => i.id == id).firstOrNull,
    ];

    Widget section(String title, {required List<Widget> children, VoidCallback? onAdd}) => Padding(
          padding: const EdgeInsets.only(top: Space.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: context.tt.titleMedium?.copyWith(color: ink))),
                  if (editable && onAdd != null)
                    IconButton(tooltip: 'Add', icon: Icon(Icons.add_circle_rounded, color: ink), onPressed: onAdd),
                ],
              ),
              const SizedBox(height: Space.s),
              ...children,
            ],
          ),
        );

    return DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom])),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.xl * 2),
        children: [
          // Header: cover photo framed by drifting hearts and candles.
          SizedBox(
            height: 230,
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (final (i, g) in ['🕯️', '💗', '✨', '🌹', '🕯️', '💫'].indexed)
                  Align(
                    alignment: Alignment(i.isEven ? -0.9 : 0.9, -0.8 + (i ~/ 2) * 0.8),
                    child: Text(g, style: const TextStyle(fontSize: 24))
                        .animate(onPlay: (c) => c.repeat(reverse: true), delay: (i * 300).ms)
                        .moveY(begin: 0, end: -8, duration: 1800.ms, curve: Curves.easeInOut)
                        .fade(begin: 0.6, end: 1, duration: 1800.ms),
                  ),
                GestureDetector(
                  onTap: editable
                      ? () async {
                          final p = await _pickAndUpload(context, ref);
                          if (p != null && context.mounted) await _save(context, ref, shrine.copyWith(coverPath: () => p));
                        }
                      : null,
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 5),
                      boxShadow: [BoxShadow(color: top.withValues(alpha: 0.6), blurRadius: 30, spreadRadius: 4)],
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: shrine.coverPath == null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('💗', style: TextStyle(fontSize: 48)),
                                if (editable) Text('Add a photo', style: context.tt.labelLarge?.copyWith(color: ink)),
                              ],
                            ),
                          )
                        : StoredImage(shrine.coverPath),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: editable
                ? () async {
                    final t = await _askText(context, title: 'Name your shrine', initial: shrine.title, hint: heading, max: Shrine.maxTitle);
                    if (t != null && context.mounted) await _save(context, ref, shrine.copyWith(title: t));
                  }
                : null,
            child: Text(
              heading + (editable ? ' ✏️' : ''),
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Nunito', fontSize: 24, fontWeight: FontWeight.w700, color: ink),
            ),
          ),
          if (editable) ...[
            const SizedBox(height: Space.s),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final t in Shrine.themes)
                  GestureDetector(
                    onTap: () => _save(context, ref, shrine.copyWith(theme: t)),
                    child: Container(
                      width: 28,
                      height: 28,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [_themes[t]!.$1, _themes[t]!.$2]),
                        border: Border.all(color: shrine.theme == t ? ink : Colors.white, width: shrine.theme == t ? 3 : 2),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          section(
            'Photos',
            onAdd: shrine.photos.length >= Shrine.maxPhotos
                ? null
                : () async {
                    final p = await _pickAndUpload(context, ref);
                    if (p != null && context.mounted) await _save(context, ref, shrine.copyWith(photos: [...shrine.photos, p]));
                  },
            children: [
              if (shrine.photos.isEmpty)
                _Hint(editable ? 'Add up to 9 photos of them' : 'No photos yet', ink)
              else
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  children: [
                    for (final p in shrine.photos)
                      GestureDetector(
                        onLongPress: editable
                            ? () async {
                                final ok = await confirm(context, title: 'Remove this photo?', body: 'It leaves the shrine.', ok: 'Remove');
                                if (ok && context.mounted) {
                                  await _save(context, ref, shrine.copyWith(photos: [...shrine.photos]..remove(p)));
                                }
                              }
                            : null,
                        child: ClipRRect(borderRadius: BorderRadius.circular(Radii.small), child: StoredImage(p)),
                      ),
                  ],
                ),
            ],
          ),
          section(
            'Favourite things',
            onAdd: shrine.favorites.length >= Shrine.maxFavorites ? null : () => _addFavorite(context, ref),
            children: [
              if (shrine.favorites.isEmpty) _Hint(editable ? 'Their favourite song, food, place…' : 'Nothing here yet', ink),
              for (final f in shrine.favorites)
                _GlassCard(
                  onLongPress: editable
                      ? () => _save(context, ref, shrine.copyWith(favorites: [...shrine.favorites]..remove(f)))
                      : null,
                  child: Row(
                    children: [
                      Text('${f.label}  ', style: context.tt.labelLarge?.copyWith(color: ink.withValues(alpha: 0.7))),
                      Expanded(child: Text(f.value, style: context.tt.titleSmall?.copyWith(color: ink))),
                    ],
                  ),
                ),
            ],
          ),
          section(
            'Messages',
            onAdd: shrine.messages.length >= Shrine.maxMessages
                ? null
                : () async {
                    final m = await _askText(context, title: 'A message for them', hint: 'Something from the heart');
                    if (m != null && m.isNotEmpty && context.mounted) {
                      await _save(context, ref, shrine.copyWith(messages: [...shrine.messages, m]));
                    }
                  },
            children: [
              if (shrine.messages.isEmpty) _Hint(editable ? 'Leave little messages to read anytime' : 'No messages yet', ink),
              for (final m in shrine.messages)
                _GlassCard(
                  onLongPress: editable ? () => _save(context, ref, shrine.copyWith(messages: [...shrine.messages]..remove(m))) : null,
                  child: Text('“$m”', style: TextStyle(fontFamily: 'Nunito', fontSize: 17, fontStyle: FontStyle.italic, color: ink, height: 1.4)),
                ),
            ],
          ),
          section(
            'Shared memories',
            onAdd: shrine.pinnedItemIds.length >= Shrine.maxPinned
                ? null
                : () async {
                    final picked = await showModalBottomSheet<String>(
                      context: context,
                      isScrollControlled: true,
                      builder: (ctx) => _MemoryPicker(exclude: shrine.pinnedItemIds),
                    );
                    if (picked != null && context.mounted) {
                      await _save(context, ref, shrine.copyWith(pinnedItemIds: [...shrine.pinnedItemIds, picked]));
                    }
                  },
            children: [
              if (pinned.isEmpty) _Hint(editable ? 'Pin favourite memories you sent each other' : 'No memories pinned yet', ink),
              if (pinned.isNotEmpty)
                SizedBox(
                  height: 120,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final i in pinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GestureDetector(
                            onTap: () => context.push('/item/${i.id}'),
                            onLongPress: editable
                                ? () => _save(context, ref, shrine.copyWith(pinnedItemIds: [...shrine.pinnedItemIds]..remove(i.id)))
                                : null,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(Radii.small),
                              child: SizedBox(width: 120, child: StoredImage(i.thumbPath)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          if (editable) ...[
            const SizedBox(height: Space.l),
            Text(
              'Long-press anything to remove it. Your person sees this shrine in their “From you” tab.',
              textAlign: TextAlign.center,
              style: context.tt.bodySmall?.copyWith(color: ink.withValues(alpha: 0.75)),
            ),
          ],
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text, this.ink);

  final String text;
  final Color ink;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: context.tt.bodyMedium?.copyWith(color: ink.withValues(alpha: 0.7)));
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child, this.onLongPress});

  final Widget child;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(Radii.small + 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.small + 4),
          onLongPress: onLongPress,
          child: Padding(padding: const EdgeInsets.all(Space.s + 4), child: child),
        ),
      ),
    );
  }
}

class _MemoryPicker extends ConsumerWidget {
  const _MemoryPicker({required this.exclude});

  final List<String> exclude;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = (ref.watch(itemsProvider).value ?? const <Item>[])
        .where((i) => i.saveToMemories && i.thumbPath != null && !exclude.contains(i.id))
        .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          children: [
            Padding(padding: const EdgeInsets.all(Space.m), child: Text('Pin a memory', style: context.tt.titleLarge)),
            Expanded(
              child: items.isEmpty
                  ? const EmptyState(emoji: '📸', title: 'No memories yet')
                  : GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: Space.m),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 6, crossAxisSpacing: 6),
                      itemCount: items.length,
                      itemBuilder: (_, i) => GestureDetector(
                        onTap: () => Navigator.pop(context, items[i].id),
                        child: ClipRRect(borderRadius: BorderRadius.circular(Radii.small), child: StoredImage(items[i].thumbPath)),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
