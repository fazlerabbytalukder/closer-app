import 'dart:async';

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/always_with_me.dart';
import 'package:closer_app/core/services/widget_bridge.dart';
import 'package:closer_app/core/services/widget_contract.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/features/me/widget_previews.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Settings + preview for the "Always with me" home-screen widget: a memory
/// photo of the day, a romantic line, and the time since you last met.
class AlwaysWithMeScreen extends ConsumerWidget {
  const AlwaysWithMeScreen({super.key});

  Future<void> _pickLastMet(BuildContext context, WidgetRef ref, DateTime? current) async {
    final now = DateTime.now();
    final initial = current ?? now;
    final day = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? now : initial,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      helpText: 'When did you last see each other?',
    );
    if (day == null || !context.mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (!context.mounted) return;
    var when = DateTime(day.year, day.month, day.day, time?.hour ?? 12, time?.minute ?? 0);
    if (when.isAfter(now)) when = now;
    final ok = await runAction(context, () => ref.read(backendProvider).setLastMet(when));
    if (ok && context.mounted) showToast(context, 'Saved 💞');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pair = ref.watch(pairProvider).value;
    final me = ref.watch(authUidProvider).value;
    final name = ref.watch(partnerNameProvider);
    final lastMet = pair?.lastMetAt;
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text('Always with me')),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          Center(
            child: SizedBox(
              width: 340,
              child: AlwaysWidgetPreview(themeId: (me == null ? null : pair?.widgetTheme[me]) ?? WidgetThemes.classic),
            ),
          ),
          const SizedBox(height: Space.l),
          CloserCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AlwaysWithMe.sinceLabel(lastMet, now), style: context.tt.titleLarge),
                const SizedBox(height: Space.xs),
                Text(
                  lastMet == null
                      ? 'Tell Duosy when you last saw $name and the widget counts the time for you.'
                      : 'Last met ${DateFormat('EEEE d MMMM, HH:mm').format(lastMet)}',
                  style: context.tt.bodyMedium?.copyWith(color: context.cc.muted),
                ),
                const SizedBox(height: Space.m),
                CloserButton(
                  label: 'We’re together right now 💞',
                  kind: CloserButtonKind.accent,
                  onPressed: () async {
                    hapticMedium();
                    final ok = await runAction(context, () => ref.read(backendProvider).setLastMet(DateTime.now()));
                    if (ok && context.mounted) showToast(context, 'Enjoy every minute 💞');
                  },
                ),
                const SizedBox(height: Space.s),
                CloserButton(
                  label: 'Pick when we last met',
                  icon: Icons.event_rounded,
                  kind: CloserButtonKind.secondary,
                  onPressed: () => _pickLastMet(context, ref, lastMet),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.m),
          CloserCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What it shows', style: context.tt.titleMedium),
                const SizedBox(height: Space.s),
                const _Bullet('📸', 'A different memory photo every day, from what you two saved'),
                _Bullet('💌', 'A sweet line of the day, or $name’s latest one-tap message'),
                const _Bullet('⏱️', 'How long since you last saw each other'),
              ],
            ),
          ),
          const SizedBox(height: Space.m),
          CloserButton(
            label: 'Add to home screen',
            icon: Icons.add_to_home_screen_rounded,
            onPressed: () async {
              if (await WidgetBridge.canPin()) {
                await WidgetBridge.requestPin(WidgetReceivers.alwaysWithMe);
              } else if (context.mounted) {
                showToast(context, 'Long-press your home screen → Widgets → Duosy → Always with me');
              }
            },
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.emoji, this.text);

  final String emoji;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: Space.s),
          Expanded(child: Text(text, style: context.tt.bodyMedium)),
        ],
      ),
    );
  }
}

/// Flutter preview of the medium "Always with me" widget (same content and
/// layout rules as AlwaysWithMeWidget.kt).
class AlwaysWidgetPreview extends ConsumerStatefulWidget {
  const AlwaysWidgetPreview({required this.themeId, super.key});

  final String themeId;

  @override
  ConsumerState<AlwaysWidgetPreview> createState() => _AlwaysWidgetPreviewState();
}

class _AlwaysWidgetPreviewState extends ConsumerState<AlwaysWidgetPreview> {
  // Keeps "x h ago" fresh while the screen is open.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = paletteFor(widget.themeId);
    final me = ref.watch(authUidProvider).value;
    final pair = ref.watch(pairProvider).value;
    final name = ref.watch(partnerNameProvider);
    final items = ref.watch(itemsProvider).value ?? const <Item>[];
    final tap = ref.watch(latestTapProvider).value;
    final now = DateTime.now();
    final partnerUid = me == null ? '' : pair?.partnerOf(me) ?? '';
    final memory = AlwaysWithMe.memoryOfTheDay(items, partnerUid: partnerUid, now: now);
    final image = ref.watch(imageUrlProvider(memory?.thumbPath)).value;
    final message = AlwaysWithMe.message(
      mode: pair?.mode ?? PairMode.couple,
      now: now,
      partnerName: name,
      partnerTap: tap != null && tap.senderId == partnerUid ? tap : null,
    );

    return AspectRatio(
      aspectRatio: 2.2,
      child: WidgetFrame(
        palette: p,
        padding: 6,
        child: Row(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: WidgetPhoto(palette: p, url: memory == null ? null : image),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 4, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WidgetChip('💞 Always with me', palette: p),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Text(
                        '“$message”',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.text, fontWeight: FontWeight.w800, fontSize: 14, height: 1.25),
                      ),
                    ),
                    Text(
                      AlwaysWithMe.sinceLabel(pair?.lastMetAt, now),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted, fontWeight: FontWeight.w700, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
