import 'dart:async';

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/note_renderer.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/reactions.dart';
import 'package:closer_app/core/ui/soft_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

/// Quick-reply screen opened from the home-screen widget (closer://reply).
class ReplyScreen extends ConsumerStatefulWidget {
  const ReplyScreen({super.key});

  @override
  ConsumerState<ReplyScreen> createState() => _ReplyScreenState();
}

class _ReplyScreenState extends ConsumerState<ReplyScreen> {
  String? _sending;

  static const _quick = ['Love it 😍', 'Miss you 💕', 'Haha 😂', 'Call me? 📞', 'Aww 🥹', 'Same! ✨'];

  /// Pastel fill per quick reply (Figma "memory detail screen").
  static const _chipTones = [
    SoftTone.pink,
    SoftTone.violet,
    SoftTone.yellow,
    SoftTone.mint,
    SoftTone.blue,
    SoftTone.pink,
  ];

  /// Deep pink of the "Send a heart" button.
  static const _heartPink = Color(0xFFD6246E);

  Future<void> _quickNote(String text) async {
    setState(() => _sending = text);
    final name = ref.read(partnerNameProvider);
    var queued = false;
    final ok = await runAction(context, () async {
      final dir = await getTemporaryDirectory();
      final style = NoteStyle(bg: noteBackgrounds[_quick.indexOf(text) % noteBackgrounds.length].id, font: 'rounded');
      final file = await NoteRenderer.renderToFile(
        text: text,
        style: style,
        path: '${dir.path}/reply_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      try {
        await ref
            .read(backendProvider)
            .sendItem(SendRequest(type: ItemType.note, imagePath: file.path, text: text, noteStyle: style));
      } on SendQueuedException {
        queued = true; // saved; it goes out once back online
      }
    });
    if (!mounted) return;
    setState(() => _sending = null);
    if (ok) {
      hapticMedium();
      showToast(context, queued ? const SendQueuedException().message : 'Sent to $name 💌');
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authUidProvider).value;
    final pair = ref.watch(pairProvider).value;
    final name = ref.watch(partnerNameProvider);
    final latest = me == null ? null : pair?.latestItemByUser[pair.partnerOf(me)];
    final items = ref.watch(itemsProvider).value ?? const <Item>[];
    final item = latest == null ? null : items.where((i) => i.id == latest.itemId).firstOrNull;
    final image = ref.watch(imageUrlProvider(item?.storagePath ?? latest?.thumbPath)).value;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Column(
        children: [
          PlainPageHeader(title: item != null && item.hidesSenderFrom(me) ? 'From a secret admirer 🕵️' : 'From $name'),
          Expanded(
            child: SafeArea(
              top: false,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                children: [
                  if (latest == null)
                    const EmptyState(
                      emoji: '💌',
                      title: 'Nothing yet',
                      body: 'When they send something, it shows up here and on your widget.',
                    )
                  else ...[
                    // Tilted white card: the photo, then caption and time.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      child: Transform.rotate(
                        angle: 0.025,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                          decoration: BoxDecoration(
                            color: context.cc.card,
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: dark ? null : softCardShadow,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: AspectRatio(aspectRatio: 1, child: AppImage(image)),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  [if (latest.caption.isNotEmpty) latest.caption, timeAgo(latest.sentAt)].join(' · '),
                                  style: context.tt.bodySmall?.copyWith(
                                    color: context.cc.muted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (item != null) ...[const SizedBox(height: 14), Center(child: ReactionBar(item: item))],
                  ],
                  const SizedBox(height: 18),
                  Text('Quick reply', style: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (i, q) in _quick.indexed)
                        _QuickChip(
                          label: q,
                          tone: _chipTones[i % _chipTones.length],
                          busy: _sending == q,
                          onTap: _sending == null ? () => _quickNote(q) : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: PillButton(
                          label: 'Photo',
                          icon: Icons.photo_camera_outlined,
                          height: 48,
                          onPressed: () => context.pushReplacement('/send?tab=photo'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: PillButton(
                          label: 'Doodle',
                          icon: Icons.edit_outlined,
                          height: 48,
                          glow: false,
                          color: SoftTone.violet.fill(context),
                          foreground: dark ? Colors.white : Brand.royal,
                          onPressed: () => context.pushReplacement('/send?tab=doodle'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  PillButton(
                    label: 'Send a heart',
                    icon: Icons.favorite_rounded,
                    height: 48,
                    color: _heartPink,
                    onPressed: () async {
                      hapticMedium();
                      final ok = await runAction(context, () => ref.read(backendProvider).sendTap());
                      if (ok && context.mounted) showToast(context, '$name will feel that 💗');
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pastel quick-reply pill; shows a spinner while that reply is sending.
class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.tone, required this.busy, required this.onTap});

  final String label;
  final SoftTone tone;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: tone.fill(context),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: busy
              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: tone.icon))
              : Text(
                  label,
                  style: context.tt.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: dark ? Colors.white : Brand.ink,
                  ),
                ),
        ),
      ),
    );
  }
}
