import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/features/love/love_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shared wishlist (F14): things to do together (date ideas, restaurants,
/// trips, experiences) and gift wishes the other one can secretly claim.
class WishlistScreen extends ConsumerWidget {
  const WishlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Wishlist'),
          bottom: const TabBar(tabs: [Tab(text: 'Together'), Tab(text: 'Gifts')]),
        ),
        floatingActionButton: Builder(
          builder: (ctx) => FloatingActionButton.extended(
            onPressed: () {
              final gifts = DefaultTabController.of(ctx).index == 1;
              ctx.push('/wishlist/edit${gifts ? '?category=gift' : ''}').ignore();
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add a wish'),
          ),
        ),
        body: const TabBarView(children: [_Together(), _Gifts()]),
      ),
    );
  }
}

class _Together extends ConsumerStatefulWidget {
  const _Together();

  @override
  ConsumerState<_Together> createState() => _TogetherState();
}

class _TogetherState extends ConsumerState<_Together> {
  WishCategory? _filter;

  @override
  Widget build(BuildContext context) {
    final wishes = (ref.watch(wishesProvider).value ?? const <Wish>[]).where((w) => !w.isGift).toList();
    final shown = wishes.where((w) => _filter == null || w.category == _filter).toList();
    final open = shown.where((w) => w.doneAt == null).toList();
    final done = shown.where((w) => w.doneAt != null).toList();
    final categories = WishCategory.values.where((c) => c != WishCategory.gift).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, 100),
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: const Text('All'), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
              ),
              for (final c in categories)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    avatar: Text(c.emoji),
                    label: Text(c.label),
                    selected: _filter == c,
                    onSelected: (_) => setState(() => _filter = c),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.s),
        if (wishes.isEmpty)
          EmptyState(
            emoji: '🌠',
            title: 'Dream up things to do',
            body: 'Restaurants to try, places to go, date ideas, experiences. Add them here and tick them off together.',
            action: 'Add a wish',
            onAction: () => context.push('/wishlist/edit'),
          ),
        for (final w in open) _WishCard(wish: w),
        if (done.isNotEmpty) ...[
          const SectionHeader('Done together ✓'),
          for (final w in done) _WishCard(wish: w),
        ],
      ],
    );
  }
}

class _Gifts extends ConsumerWidget {
  const _Gifts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authUidProvider).value;
    final name = ref.watch(partnerNameProvider);
    final gifts = (ref.watch(wishesProvider).value ?? const <Wish>[]).where((w) => w.isGift).toList();
    final theirs = gifts.where((w) => w.ownerUid != me).toList();
    final mine = gifts.where((w) => w.ownerUid == me).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, 100),
      children: [
        SectionHeader('$name wishes for'),
        if (theirs.isEmpty)
          Text('Nothing yet. Drop a hint that this list exists 😉', style: context.tt.bodyMedium?.copyWith(color: context.cc.muted))
        else
          for (final w in theirs) _WishCard(wish: w, claimable: true),
        const SectionHeader('You wish for'),
        CloserCard(
          color: context.cc.secondaryTint,
          padding: const EdgeInsets.all(Space.s + 4),
          child: Text(
            '$name can secretly mark a gift as “I’ll get this”. You’ll never see which ones 🤫',
            style: context.tt.bodySmall,
          ),
        ),
        const SizedBox(height: Space.s),
        if (mine.isEmpty)
          Text('Add things you’d love to get.', style: context.tt.bodyMedium?.copyWith(color: context.cc.muted))
        else
          for (final w in mine) _WishCard(wish: w),
      ],
    );
  }
}

class _WishCard extends ConsumerWidget {
  const _WishCard({required this.wish, this.claimable = false});

  final Wish wish;

  /// The partner's gift: show the secret "I'll get this" toggle.
  final bool claimable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = wish;
    final claimed = claimable && (ref.watch(wishClaimsProvider).value?.contains(w.id) ?? false);
    final done = w.doneAt != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: CloserCard(
        onTap: () => context.push('/wishlist/edit?id=${w.id}'),
        padding: const EdgeInsets.all(Space.s + 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.small),
              child: SizedBox(
                width: 56,
                height: 56,
                child: w.photoPath != null
                    ? StoredImage(w.photoPath)
                    : ColoredBox(
                        color: context.cc.accentTint,
                        child: Center(child: Text(w.category.emoji, style: const TextStyle(fontSize: 28))),
                      ),
              ),
            ),
            const SizedBox(width: Space.s + 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    w.title,
                    style: context.tt.titleSmall?.copyWith(
                      decoration: done ? TextDecoration.lineThrough : null,
                      color: done ? context.cc.muted : null,
                    ),
                  ),
                  if (w.note.isNotEmpty || w.price.isNotEmpty)
                    Text(
                      [if (w.price.isNotEmpty) w.price, if (w.note.isNotEmpty) w.note].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
                    ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (w.url.isNotEmpty)
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(Icons.open_in_new_rounded, size: 16),
                          label: const Text('Open link'),
                          onPressed: () {
                            final uri = Uri.tryParse(w.url.startsWith('http') ? w.url : 'https://${w.url}');
                            if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication).ignore();
                          },
                        ),
                      if (claimable)
                        FilterChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(claimed ? 'You’re getting this 🤫' : 'I’ll get this'),
                          selected: claimed,
                          onSelected: (v) async {
                            hapticSoft();
                            await runAction(context, () => ref.read(backendProvider).claimWish(w.id, claim: v));
                          },
                        )
                      else
                        FilterChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(done ? (w.isGift ? 'Got it 🎉' : 'Done ✓') : (w.isGift ? 'I got it' : 'We did it!')),
                          selected: done,
                          onSelected: (v) async {
                            hapticSoft();
                            await runAction(context, () => ref.read(backendProvider).setWishDone(w.id, done: v));
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Add or edit a wish.
class WishEditScreen extends ConsumerStatefulWidget {
  const WishEditScreen({super.key, this.wishId, this.category});

  final String? wishId;
  final WishCategory? category;

  @override
  ConsumerState<WishEditScreen> createState() => _WishEditScreenState();
}

class _WishEditScreenState extends ConsumerState<WishEditScreen> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _url = TextEditingController();
  final _price = TextEditingController();
  WishCategory _category = WishCategory.date;
  String? _storedPhoto;
  String? _newPhoto;
  bool _removePhoto = false;
  Wish? _existing;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _existing = (ref.read(wishesProvider).value ?? const <Wish>[]).where((w) => w.id == widget.wishId).firstOrNull;
    final e = _existing;
    if (e != null) {
      _title.text = e.title;
      _note.text = e.note;
      _url.text = e.url;
      _price.text = e.price;
      _category = e.category;
      _storedPhoto = e.photoPath;
    } else {
      _category = widget.category ?? WishCategory.date;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _url.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final backend = ref.read(backendProvider);
    final e = _existing;
    final ok = await runAction(context, () async {
      var photo = _removePhoto ? null : _storedPhoto;
      if (_newPhoto != null) photo = await backend.uploadPhoto(_newPhoto!);
      await backend.saveWish(
        Wish(
          id: e?.id ?? '',
          title: _title.text,
          category: _category,
          note: _note.text,
          url: _url.text,
          price: _price.text,
          photoPath: photo,
          ownerUid: e?.ownerUid,
          createdBy: e?.createdBy ?? '',
        ),
      );
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authUidProvider).value;
    final e = _existing;
    // A gift wish belongs to whoever wants it; only they edit it.
    final readOnly = e != null && e.isGift && e.ownerUid != me;
    // Switching a saved wish between gift and shared would change its owner.
    final categories = e == null ? WishCategory.values : WishCategory.values.where((c) => (c == WishCategory.gift) == e.isGift);

    return Scaffold(
      appBar: AppBar(
        title: Text(e == null ? 'New wish' : (readOnly ? e.title : 'Edit wish')),
        actions: [
          if (e != null && !readOnly)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final yes = await confirm(context, title: 'Delete this wish?', body: 'It’s removed for both of you.', ok: 'Delete', destructive: true);
                if (!yes || !context.mounted) return;
                final ok = await runAction(context, () => ref.read(backendProvider).deleteWish(e.id));
                if (ok && context.mounted) context.pop();
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          if (readOnly) ...[
            if (e.photoPath != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.small + 4),
                child: AspectRatio(aspectRatio: 4 / 3, child: StoredImage(e.photoPath)),
              ),
            const SizedBox(height: Space.m),
            Text(e.title, style: context.tt.headlineSmall),
            if (e.price.isNotEmpty) Text(e.price, style: context.tt.titleMedium?.copyWith(color: context.cc.accent)),
            if (e.note.isNotEmpty) ...[const SizedBox(height: Space.s), Text(e.note, style: context.tt.bodyLarge)],
            const SizedBox(height: Space.m),
            if (e.url.isNotEmpty)
              CloserButton(
                label: 'Open link',
                icon: Icons.open_in_new_rounded,
                kind: CloserButtonKind.secondary,
                onPressed: () {
                  final uri = Uri.tryParse(e.url.startsWith('http') ? e.url : 'https://${e.url}');
                  if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication).ignore();
                },
              ),
          ] else ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in categories)
                  ChoiceChip(
                    avatar: Text(c.emoji),
                    label: Text(c == WishCategory.gift ? 'Gift for me' : c.label),
                    selected: _category == c,
                    onSelected: (_) => setState(() => _category = c),
                  ),
              ],
            ),
            const SizedBox(height: Space.m),
            TextField(
              controller: _title,
              maxLength: Wish.maxTitle,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: switch (_category) {
                  WishCategory.gift => 'What would you love to get?',
                  WishCategory.restaurant => 'Which restaurant?',
                  WishCategory.travel => 'Where to?',
                  WishCategory.date => 'Date idea',
                  _ => 'What is it?',
                },
              ),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _note,
              maxLength: Wish.maxNote,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Notes (size, colour, why…)'),
            ),
            TextField(
              controller: _url,
              maxLength: Wish.maxUrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Link (optional)', prefixIcon: Icon(Icons.link_rounded)),
            ),
            TextField(
              controller: _price,
              maxLength: Wish.maxPrice,
              decoration: const InputDecoration(labelText: 'Price (optional)', prefixIcon: Icon(Icons.sell_rounded)),
            ),
            const SizedBox(height: Space.s),
            if (_newPhoto != null || _storedPhoto == null || _removePhoto)
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
            CloserButton(
              label: e == null ? 'Add to wishlist' : 'Save',
              kind: CloserButtonKind.accent,
              loading: _busy,
              onPressed: _title.text.trim().isEmpty ? null : _save,
            ),
          ],
        ],
      ),
    );
  }
}
