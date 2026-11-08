import 'dart:async';

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/note_renderer.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

  Future<void> _quickNote(String text) async {
    setState(() => _sending = text);
    final name = ref.read(partnerNameProvider);
    final ok = await runAction(context, () async {
      final dir = await getTemporaryDirectory();
      final style = NoteStyle(bg: noteBackgrounds[_quick.indexOf(text) % noteBackgrounds.length].id, font: 'rounded');
      final file = await NoteRenderer.renderToFile(
        text: text,
        style: style,
        path: '${dir.path}/reply_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await ref.read(backendProvider).sendItem(
            SendRequest(type: ItemType.note, imagePath: file.path, text: text, noteStyle: style),
          );
    });
    if (!mounted) return;
    setState(() => _sending = null);
    if (ok) {
      hapticMedium();
      showToast(context, 'Sent to $name 💌');
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

    return Scaffold(
      appBar: AppBar(title: Text('From $name')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Space.m),
          children: [
            if (latest == null)
              const EmptyState(emoji: '💌', title: 'Nothing yet', body: 'When they send something, it shows up here and on your widget.')
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.card),
                child: AspectRatio(aspectRatio: 1, child: AppImage(image)),
              ),
              const SizedBox(height: Space.s),
              Text(
                [if (latest.caption.isNotEmpty) latest.caption, timeAgo(latest.sentAt)].join(' · '),
                style: context.tt.bodyMedium?.copyWith(color: context.cc.muted),
              ),
            ],
            const SizedBox(height: Space.l),
            Text('Quick reply', style: context.tt.titleMedium),
            const SizedBox(height: Space.s),
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                for (final q in _quick)
                  ActionChip(
                    label: _sending == q
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(q),
                    onPressed: _sending == null ? () => _quickNote(q) : null,
                  ),
              ],
            ),
            const SizedBox(height: Space.l),
            Row(
              children: [
                Expanded(
                  child: CloserButton(
                    label: 'Photo',
                    icon: Icons.photo_camera_rounded,
                    onPressed: () => context.pushReplacement('/send?tab=photo'),
                  ),
                ),
                const SizedBox(width: Space.s),
                Expanded(
                  child: CloserButton(
                    label: 'Doodle',
                    icon: Icons.brush_rounded,
                    kind: CloserButtonKind.secondary,
                    onPressed: () => context.pushReplacement('/send?tab=doodle'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.s),
            CloserButton(
              label: 'Send a heart',
              icon: Icons.favorite_rounded,
              kind: CloserButtonKind.accent,
              onPressed: () async {
                hapticMedium();
                final ok = await runAction(context, () => ref.read(backendProvider).sendTap());
                if (ok && context.mounted) showToast(context, '$name will feel that 💗');
              },
            ),
          ],
        ),
      ),
    );
  }
}
