import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/data/closer_backend.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/ads.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/soft_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Memories scrapbook (F9): timeline grid grouped by month. Free plans see
/// the last 30 days; older memories are blurred behind Plus.
class MemoriesScreen extends ConsumerWidget {
  const MemoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(itemsProvider);
    final plus = ref.watch(isPlusProvider);
    final items = (itemsAsync.value ?? const <Item>[]).where((i) => i.saveToMemories).toList();
    final cutoff = DateTime.now().subtract(const Duration(days: FreeLimits.memoriesDays));

    final groups = <String, List<Item>>{};
    for (final i in items) {
      groups.putIfAbsent(DateFormat('MMMM yyyy').format(i.createdAt), () => []).add(i);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: softAppBar(context, 'Memories'),
      body: items.isEmpty
          ? EmptyState(
              emoji: '📸',
              title: 'Your scrapbook starts here',
              body: 'Everything you two send is saved here, month by month.',
              action: 'Send something',
              onAction: () => context.push('/send'),
            )
          : CustomScrollView(
              slivers: [
                const SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: Space.m),
                  sliver: SliverToBoxAdapter(child: AdBanner()),
                ),
                for (final e in groups.entries) ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.s),
                    sliver: SliverToBoxAdapter(
                      child: Text(e.key, style: context.tt.titleMedium),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.m),
                    sliver: SliverGrid.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                      ),
                      itemCount: e.value.length,
                      itemBuilder: (context, i) {
                        final item = e.value[i];
                        final locked = !plus && item.createdAt.isBefore(cutoff);
                        return _Tile(item: item, locked: locked);
                      },
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
    );
  }
}

class _Tile extends ConsumerWidget {
  const _Tile({required this.item, required this.locked});

  final Item item;
  final bool locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref.watch(imageUrlProvider(item.thumbPath)).value;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.small),
      child: LockedCard(
        locked: locked,
        label: 'Plus',
        sigma: 10,
        onTap: () => context.push('/paywall?from=memories'),
        child: Semantics(
          button: true,
          label: '${item.type.name}${item.caption.isEmpty ? '' : ': ${item.caption}'}',
          child: GestureDetector(
            onTap: () => context.push('/item/${item.id}'),
            child: SizedBox.expand(child: AppImage(image)),
          ),
        ),
      ),
    );
  }
}

class ItemViewerScreen extends ConsumerWidget {
  const ItemViewerScreen({required this.itemId, super.key});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(itemsProvider).value ?? const <Item>[];
    final item = items.where((i) => i.id == itemId).firstOrNull;
    final me = ref.watch(authUidProvider).value;
    final name = ref.watch(partnerNameProvider);
    final image = ref.watch(imageUrlProvider(item?.storagePath)).value;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: item == null ? null : Text(item.senderId == me ? 'You' : name),
        actions: [
          if (image != null && !image.startsWith('http'))
            IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: () => SharePlus.instance.share(ShareParams(files: [XFile(image)])),
            ),
        ],
      ),
      body: item == null
          ? const Center(child: Text('Not found', style: TextStyle(color: Colors.white)))
          : Column(
              children: [
                Expanded(
                  child: InteractiveViewer(
                    child: Center(child: AppImage(image, fit: BoxFit.contain)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(Space.m),
                  child: Column(
                    children: [
                      if (item.caption.isNotEmpty)
                        Text(item.caption, style: context.tt.titleMedium?.copyWith(color: Colors.white)),
                      if (item.geo case final geo?)
                        TextButton.icon(
                          style: TextButton.styleFrom(foregroundColor: Colors.white),
                          icon: const Icon(Icons.location_on_rounded),
                          label: Text(geo.place.isEmpty ? geo.coords : geo.place, overflow: TextOverflow.ellipsis),
                          onPressed: () => launchUrl(geo.mapsUri, mode: LaunchMode.externalApplication),
                        ),
                      Text(
                        DateFormat('EEEE d MMMM yyyy, HH:mm').format(item.createdAt),
                        style: context.tt.bodySmall?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
