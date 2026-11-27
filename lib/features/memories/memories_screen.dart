import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/data/closer_backend.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/ads.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/reactions.dart';
import 'package:closer_app/core/ui/soft_ui.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
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

    final top = MediaQuery.paddingOf(context).top;
    final entries = groups.entries.toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          // Violet header with the title and mascots (Figma "memories-screen");
          // the first month pill sits on its rounded bottom edge.
          SliverToBoxAdapter(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(left: 0, right: 0, top: 0, height: top + 110, child: const HeroBackdrop(radius: 32)),
                Positioned(
                  right: -8,
                  top: top - 14,
                  child: Image.asset('assets/together/header_mascots.png', width: 112, height: 124)
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .moveY(begin: 0, end: -5, duration: 1800.ms, curve: Curves.easeInOut),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(20, top + 22, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Memories',
                        style: context.tt.headlineLarge?.copyWith(color: Colors.white, fontSize: 40, height: 1.1),
                      ),
                      SizedBox(height: entries.isEmpty ? 64 : 22),
                      if (entries.isNotEmpty) _MonthPill(entries.first.key),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 100),
                child: EmptyState(
                  emoji: '📸',
                  title: 'Your scrapbook starts here',
                  body: 'Everything you two send is saved here, month by month.',
                  action: 'Send something',
                  onAction: () => context.push('/send'),
                ),
              ),
            )
          else ...[
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, Space.s, 20, 0),
              sliver: SliverToBoxAdapter(child: AdBanner()),
            ),
            for (final (g, e) in entries.indexed) ...[
              if (g > 0)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: Align(alignment: Alignment.centerLeft, child: _MonthPill(e.key)),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.9,
                  ),
                  itemCount: e.value.length,
                  itemBuilder: (context, i) {
                    final item = e.value[i];
                    final locked = !plus && item.createdAt.isBefore(cutoff);
                    return _Tile(item: item, locked: locked, tilt: _tilts[i % _tilts.length]);
                  },
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ],
      ),
    );
  }

  /// Small alternating tilts (radians) so the grid reads like a scrapbook.
  static const _tilts = [-0.035, 0.03, 0.025, -0.03];
}

/// White month label pill (Figma: "November 2026" on the header edge).
class _MonthPill extends StatelessWidget {
  const _MonthPill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
      decoration: BoxDecoration(
        color: context.cc.card,
        borderRadius: BorderRadius.circular(999),
        boxShadow: dark ? null : softCardShadow,
      ),
      child: Text(label, style: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
    );
  }
}

/// Polaroid-style memory: the thumbnail inside a white frame with a deeper
/// bottom edge, slightly tilted, with a soft shadow.
class _Tile extends ConsumerWidget {
  const _Tile({required this.item, required this.locked, required this.tilt});

  final Item item;
  final bool locked;
  final double tilt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref.watch(imageUrlProvider(item.thumbPath)).value;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Transform.rotate(
      angle: tilt,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 22),
        decoration: BoxDecoration(
          color: context.cc.card,
          borderRadius: BorderRadius.circular(Radii.tile),
          boxShadow: dark ? null : softCardShadow,
        ),
        child: ClipRRect(
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
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AppImage(image),
                    if (item.secret && item.revealedAt == null)
                      const Positioned(top: 6, left: 6, child: Text('🕵️', style: TextStyle(fontSize: 18))),
                    if (item.reactions.isNotEmpty)
                      Positioned(right: 6, bottom: 6, child: ReactionBadge(reactions: item.reactions)),
                  ],
                ),
              ),
            ),
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
        title: item == null
            ? null
            : Text(
                item.senderId == me
                    ? 'You'
                    : item.hidesSenderFrom(me)
                    ? 'A secret admirer 🕵️'
                    : name,
              ),
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
          ? const Center(
              child: Text('Not found', style: TextStyle(color: Colors.white)),
            )
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
                      if (item.secret) _SecretLine(item: item, mine: item.senderId == me, name: name),
                      const SizedBox(height: Space.s),
                      ReactionBar(item: item, onDark: true),
                      const SizedBox(height: Space.s),
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

/// Secret-admirer status under an item: the sender can reveal it; the
/// receiver sees a playful hint until then.
class _SecretLine extends ConsumerWidget {
  const _SecretLine({required this.item, required this.mine, required this.name});

  final Item item;
  final bool mine;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const style = TextStyle(color: Colors.white70);
    if (item.revealedAt != null) {
      return Padding(
        padding: const EdgeInsets.only(top: Space.xs),
        child: Text(mine ? 'You revealed yourself 💘' : 'Your secret admirer was $name 💘', style: style),
      );
    }
    if (!mine) {
      return const Padding(
        padding: EdgeInsets.only(top: Space.xs),
        child: Text('From a secret admirer… any guesses? 👀', style: style),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: Colors.white),
        icon: const Text('🕵️'),
        label: const Text('Sent anonymously · Reveal it was you'),
        onPressed: () async {
          final ok = await confirm(
            context,
            title: 'Reveal yourself?',
            body: '$name will find out this was from you.',
            ok: 'Reveal',
          );
          if (!ok || !context.mounted) return;
          final done = await runAction(context, () => ref.read(backendProvider).revealSecret(item.id));
          if (done && context.mounted) showToast(context, 'Revealed! 💘');
        },
      ),
    );
  }
}
