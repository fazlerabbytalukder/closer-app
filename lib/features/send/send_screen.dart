import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/data/closer_backend.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/ads.dart';
import 'package:closer_app/core/services/note_renderer.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/features/send/doodle_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Captures a RepaintBoundary to a PNG file.
Future<String> captureToFile(GlobalKey key, {double pixelRatio = 3}) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/closer_send_${DateTime.now().millisecondsSinceEpoch}.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  return file.path;
}

class _Sticker {
  _Sticker(this.emoji, this.offset);

  final String emoji;
  Offset offset;
  double scale = 1;
}

const _stickerPacks = <(String, bool, List<String>)>[
  ('Love', false, ['💗', '💕', '💌', '😘', '🥰', '💋', '🌹', '💍']),
  ('Fun', false, ['😂', '✨', '🔥', '🎉', '👀', '🫶', '🙈', '⭐']),
  ('Cozy', true, ['☕', '🧸', '🕯️', '🍪', '🌙', '🧦', '📚', '🫖']),
  ('Seasonal', true, ['🎄', '🎃', '🌸', '☀️', '🍂', '❄️', '🐣', '🎆']),
];

class SendScreen extends ConsumerStatefulWidget {
  const SendScreen({super.key, this.initialTab});

  final String? initialTab;

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 3,
    vsync: this,
    initialIndex: switch (widget.initialTab) { 'note' => 1, 'doodle' => 2, _ => 0 },
  );
  final _photoKey = GlobalKey();
  final _noteKey = GlobalKey();
  final _doodleKey = GlobalKey();
  final _caption = TextEditingController();
  final _note = TextEditingController();
  final _doodle = DoodleController();
  final _stickers = <_Sticker>[];

  String? _photo;
  String _noteBg = noteBackgrounds.first.id;
  String _noteFont = 'rounded';
  bool _saveToMemories = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() => setState(() {}));
    _doodle.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _caption.dispose();
    _note.dispose();
    _doodle.dispose();
    super.dispose();
  }

  ItemType get _type => ItemType.values[_tabs.index];

  bool get _canSend => switch (_type) {
        ItemType.photo => _photo != null,
        ItemType.note => _note.text.trim().isNotEmpty,
        ItemType.doodle => !_doodle.isEmpty,
      };

  Future<void> _pick(ImageSource source) async {
    final x = await ImagePicker().pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 92);
    if (x != null) setState(() => _photo = x.path);
  }

  Future<void> _pickStickers() async {
    final plus = ref.read(isPlusProvider);
    final emoji = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
          children: [
            for (final (name, isPlus, list) in _stickerPacks) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.s),
                child: Row(
                  children: [
                    Text(name, style: ctx.tt.titleSmall),
                    if (isPlus && !plus) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.workspace_premium_rounded, size: 16, color: Brand.amber),
                    ],
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in list)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        if (isPlus && !plus) {
                          Navigator.pop(ctx);
                          unawaited(context.push('/paywall?from=stickers'));
                          return;
                        }
                        Navigator.pop(ctx, e);
                      },
                      child: Opacity(
                        opacity: isPlus && !plus ? 0.45 : 1,
                        child: Padding(padding: const EdgeInsets.all(6), child: Text(e, style: const TextStyle(fontSize: 32))),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
    if (emoji != null) {
      setState(() => _stickers.add(_Sticker(emoji, const Offset(120, 120))));
    }
  }

  Future<void> _send() async {
    if (!_canSend || _sending) return;
    final left = ref.read(sendsLeftProvider);
    if (left != null && left <= 0) {
      await _limitReached();
      return;
    }
    setState(() => _sending = true);
    final key = switch (_type) { ItemType.photo => _photoKey, ItemType.note => _noteKey, ItemType.doodle => _doodleKey };
    final name = ref.read(partnerNameProvider);
    final ok = await runAction(context, () async {
      final path = await captureToFile(key);
      await ref.read(backendProvider).sendItem(
            SendRequest(
              type: _type,
              imagePath: path,
              caption: _type == ItemType.note ? '' : _caption.text.trim(),
              text: _type == ItemType.note ? _note.text.trim() : null,
              noteStyle: _type == ItemType.note ? NoteStyle(bg: _noteBg, font: _noteFont) : null,
              saveToMemories: _saveToMemories,
            ),
          );
    });
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      hapticMedium();
      showToast(context, 'Sent to $name’s widget 💌', icon: Icons.check_circle_rounded);
      context.pop();
    }
  }

  Future<void> _limitReached() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('💌', style: TextStyle(fontSize: 48)),
              const SizedBox(height: Space.s),
              Text('You’ve sent ${FreeLimits.sendsPerDay} today', style: ctx.tt.titleLarge),
              const SizedBox(height: Space.s),
              Text(
                'Get unlimited sends with Closer Plus — for both of you. Or watch a short ad for +${FreeLimits.rewardedExtraSends} more today.',
                textAlign: TextAlign.center,
                style: ctx.tt.bodyMedium?.copyWith(color: ctx.cc.muted),
              ),
              const SizedBox(height: Space.l),
              CloserButton(label: 'Try Closer Plus free', kind: CloserButtonKind.accent, onPressed: () => Navigator.pop(ctx, 'plus')),
              const SizedBox(height: Space.s),
              CloserButton(label: 'Watch an ad for +${FreeLimits.rewardedExtraSends}', kind: CloserButtonKind.secondary, onPressed: () => Navigator.pop(ctx, 'ad')),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'plus') {
      await context.push('/paywall?from=sends');
    } else if (choice == 'ad') {
      final rewarded = await Ads.showRewarded(context);
      if (rewarded && mounted) {
        await runAction(context, () => ref.read(backendProvider).grantRewardedSends());
        if (mounted) showToast(context, '+${FreeLimits.rewardedExtraSends} sends unlocked for today');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(partnerNameProvider);
    final left = ref.watch(sendsLeftProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Close', onPressed: () => context.pop()),
        title: const Text('Send'),
        actions: [
          if (left != null)
            Padding(
              padding: const EdgeInsets.only(right: Space.m),
              child: Center(
                child: CounterChip(
                  label: '$left of ${FreeLimits.sendsPerDay} left today',
                  color: left == 0 ? context.cs.error : context.cc.secondary,
                ),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: context.tt.labelLarge,
          tabs: const [
            Tab(icon: Icon(Icons.photo_camera_rounded), text: 'Photo'),
            Tab(icon: Icon(Icons.sticky_note_2_rounded), text: 'Note'),
            Tab(icon: Icon(Icons.brush_rounded), text: 'Doodle'),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: TabBarView(
                controller: _tabs,
                physics: const NeverScrollableScrollPhysics(),
                children: [_photoTab(), _noteTab(), _doodleTab()],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
              child: Column(
                children: [
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Also save to Memories'),
                    value: _saveToMemories,
                    onChanged: (v) => setState(() => _saveToMemories = v),
                  ),
                  CloserButton(
                    label: 'Send to $name’s widget',
                    icon: Icons.send_rounded,
                    kind: CloserButtonKind.accent,
                    loading: _sending,
                    onPressed: _canSend ? _send : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _square(Widget child, GlobalKey key) => Padding(
        padding: const EdgeInsets.all(Space.m),
        child: Center(
          child: AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.card),
              child: RepaintBoundary(key: key, child: child),
            ),
          ),
        ),
      );

  Widget _photoTab() {
    final photo = _photo;
    return ListView(
      children: [
        if (photo == null)
          Padding(
            padding: const EdgeInsets.all(Space.m),
            child: AspectRatio(
              aspectRatio: 1,
              child: CloserCard(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('📸', style: TextStyle(fontSize: 56)),
                    const SizedBox(height: Space.m),
                    Text('Share a moment', style: context.tt.titleLarge),
                    const SizedBox(height: Space.l),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CloserButton(label: 'Camera', icon: Icons.photo_camera_rounded, expand: false, onPressed: () => _pick(ImageSource.camera)),
                        const SizedBox(width: Space.s),
                        CloserButton(label: 'Gallery', icon: Icons.photo_library_rounded, expand: false, kind: CloserButtonKind.secondary, onPressed: () => _pick(ImageSource.gallery)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          )
        else ...[
          _square(
            LayoutBuilder(
              builder: (context, c) => Stack(
                fit: StackFit.expand,
                children: [
                  InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Image.file(File(photo), fit: BoxFit.cover, width: c.maxWidth, height: c.maxHeight),
                  ),
                  for (final s in _stickers)
                    Positioned(
                      left: s.offset.dx - 28 * s.scale,
                      top: s.offset.dy - 28 * s.scale,
                      child: GestureDetector(
                        onScaleUpdate: (d) => setState(() {
                          s
                            ..offset += d.focalPointDelta
                            ..scale = (s.scale * (d.scale == 1 ? 1 : (1 + (d.scale - 1) * 0.05))).clamp(0.5, 3);
                        }),
                        onLongPress: () => setState(() => _stickers.remove(s)),
                        child: Text(s.emoji, style: TextStyle(fontSize: 48 * s.scale)),
                      ),
                    ),
                ],
              ),
            ),
            _photoKey,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _caption,
                    maxLength: Item.maxCaption,
                    decoration: const InputDecoration(hintText: 'Add a caption', counterText: ''),
                  ),
                ),
                const SizedBox(width: Space.s),
                RoundIconButton(icon: Icons.emoji_emotions_rounded, label: 'Add sticker', onPressed: _pickStickers),
                const SizedBox(width: Space.s),
                RoundIconButton(icon: Icons.refresh_rounded, label: 'Choose another photo', onPressed: () => _pick(ImageSource.gallery)),
              ],
            ),
          ),
          if (_stickers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: Text('Drag stickers to move, pinch to resize, long-press to remove', textAlign: TextAlign.center, style: context.tt.bodySmall?.copyWith(color: context.cc.muted)),
            ),
        ],
      ],
    );
  }

  Widget _noteTab() {
    return ListView(
      children: [
        _square(NoteCard(text: _note.text, style: NoteStyle(bg: _noteBg, font: _noteFont)), _noteKey),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m),
          child: Column(
            children: [
              TextField(
                controller: _note,
                maxLength: 140,
                maxLines: 3,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Write something sweet…'),
                onChanged: (_) => setState(() {}),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final bg in noteBackgrounds)
                      Padding(
                        padding: const EdgeInsets.only(right: Space.s),
                        child: Semantics(
                          label: 'Background ${bg.id}',
                          selected: _noteBg == bg.id,
                          button: true,
                          child: GestureDetector(
                            onTap: () => setState(() => _noteBg = bg.id),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(colors: bg.colors),
                                border: Border.all(color: _noteBg == bg.id ? context.cs.onSurface : Colors.transparent, width: 3),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Space.s),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'rounded', label: Text('Rounded')),
                  ButtonSegment(value: 'serif', label: Text('Serif', style: TextStyle(fontFamily: 'serif'))),
                  ButtonSegment(value: 'mono', label: Text('Mono', style: TextStyle(fontFamily: 'monospace'))),
                ],
                selected: {_noteFont},
                onSelectionChanged: (s) => setState(() => _noteFont = s.first),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _doodleTab() {
    const colors = [Color(0xFFFF6B8A), Color(0xFF2F7BE6), Color(0xFF5DBB63), Color(0xFFFFB547), Color(0xFF7C6CF2), Color(0xFF1C2433), Colors.white];
    final photo = _photo;
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _square(
          Stack(
            fit: StackFit.expand,
            children: [
              if (photo != null) Image.file(File(photo), fit: BoxFit.cover) else const ColoredBox(color: Colors.white),
              DoodleCanvas(controller: _doodle),
            ],
          ),
          _doodleKey,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m),
          child: Column(
            children: [
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final c in colors)
                      Padding(
                        padding: const EdgeInsets.only(right: Space.s),
                        child: Semantics(
                          button: true,
                          selected: !_doodle.eraser && _doodle.color == c,
                          label: 'Pen colour',
                          child: GestureDetector(
                            onTap: () => _doodle.setColor(c),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: !_doodle.eraser && _doodle.color == c ? context.cs.onSurface : context.cs.outlineVariant,
                                  width: !_doodle.eraser && _doodle.color == c ? 3 : 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.line_weight_rounded, size: 20),
                  Expanded(
                    child: Slider(value: _doodle.width, min: 3, max: 24, onChanged: _doodle.setWidth, label: 'Pen size'),
                  ),
                  IconButton(
                    tooltip: 'Eraser',
                    isSelected: _doodle.eraser,
                    icon: const Icon(Icons.auto_fix_normal_rounded),
                    selectedIcon: const Icon(Icons.auto_fix_high_rounded),
                    onPressed: _doodle.toggleEraser,
                  ),
                  IconButton(tooltip: 'Undo', icon: const Icon(Icons.undo_rounded), onPressed: _doodle.isEmpty ? null : _doodle.undo),
                  IconButton(
                    tooltip: photo == null ? 'Draw over a photo' : 'Remove photo',
                    icon: Icon(photo == null ? Icons.add_photo_alternate_rounded : Icons.hide_image_rounded),
                    onPressed: () => photo == null ? _pick(ImageSource.gallery) : setState(() => _photo = null),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
