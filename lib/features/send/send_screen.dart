import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/data/closer_backend.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/ads.dart';
import 'package:closer_app/core/services/location.dart';
import 'package:closer_app/core/services/note_renderer.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/soft_ui.dart';
import 'package:closer_app/features/send/doodle_canvas.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
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
  const SendScreen({super.key, this.initialTab, this.secret = false});

  final String? initialTab;

  /// Start with "Send as a secret admirer" switched on.
  final bool secret;

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 4,
    vsync: this,
    initialIndex: switch (widget.initialTab) {
      'note' => 1,
      'doodle' => 2,
      'location' => 3,
      _ => 0,
    },
  );
  final _photoKey = GlobalKey();
  final _noteKey = GlobalKey();
  final _doodleKey = GlobalKey();
  final _locationKey = GlobalKey();
  final _caption = TextEditingController();
  final _note = TextEditingController();
  final _doodle = DoodleController();
  final _stickers = <_Sticker>[];

  String? _photo;
  String _noteBg = noteBackgrounds.first.id;
  String _noteFont = 'rounded';
  bool _saveToMemories = true;
  late bool _secret = widget.secret;
  bool _sending = false;

  // Location tab: camera shot + where/when it was taken.
  String? _locPhoto;
  GeoTag? _geo;
  DateTime? _locTime;
  bool _locating = false;
  bool _autoOpened = false;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      setState(() {});
      // Jump straight into the camera the first time Location is opened.
      if (_type == ItemType.location && !_tabs.indexIsChanging && !_autoOpened && _locPhoto == null) {
        _autoOpened = true;
        unawaited(_captureLocation());
      }
    });
    if (widget.initialTab == 'location') {
      _autoOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _captureLocation());
    }
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
    ItemType.location => _locPhoto != null && _geo != null && !_locating,
  };

  Future<void> _pick(ImageSource source) async {
    final x = await ImagePicker().pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 92);
    if (x != null) setState(() => _photo = x.path);
  }

  /// Checks location permission, starts finding the position, opens the
  /// camera, then waits for the fix so the photo can be stamped.
  Future<void> _captureLocation({bool retakeOnly = false}) async {
    if (_locating) return;
    final XFile? x;
    final Future<GeoTag> geoFuture;
    try {
      await LocationService.ensureReady();
      // Start the GPS fix while the user frames the shot.
      final known = _geo;
      geoFuture = retakeOnly && known != null ? Future.value(known) : LocationService.current();
      x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2000, maxHeight: 2000, imageQuality: 92);
    } on CloserException catch (e) {
      if (mounted) showToast(context, e.message, icon: Icons.location_off_rounded);
      return;
    } on MissingPluginException {
      // New native plugin (geolocator) not in this build: needs a full rebuild.
      if (mounted) {
        showToast(
          context,
          'Location isn’t ready in this build — stop the app and run it again.',
          icon: Icons.location_off_rounded,
        );
      }
      return;
    } on Object catch (e, st) {
      debugPrint('Location capture failed: $e\n$st');
      if (mounted) showToast(context, 'Couldn’t open the camera or location ($e).', icon: Icons.location_off_rounded);
      return;
    }
    if (!mounted) return;
    if (x == null) {
      unawaited(geoFuture.then((_) {}, onError: (Object _) {}));
      return;
    }
    final path = x.path;
    setState(() {
      _locPhoto = path;
      _locTime = DateTime.now();
      _locating = true;
    });
    await _resolve(() => geoFuture);
  }

  Future<void> _refreshLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    await _resolve(() => LocationService.ensureReady().then((_) => LocationService.current()));
  }

  Future<void> _resolve(Future<GeoTag> Function() find) async {
    try {
      final geo = await find();
      if (mounted) setState(() => _geo = geo);
    } on CloserException catch (e) {
      if (mounted) showToast(context, e.message, icon: Icons.location_off_rounded);
    } on Object {
      if (mounted) showToast(context, 'Couldn’t find your location. Try again.', icon: Icons.location_off_rounded);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
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
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(e, style: const TextStyle(fontSize: 32)),
                        ),
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
    final key = switch (_type) {
      ItemType.photo => _photoKey,
      ItemType.note => _noteKey,
      ItemType.doodle => _doodleKey,
      ItemType.location => _locationKey,
    };
    final name = ref.read(partnerNameProvider);
    final ok = await runAction(context, () async {
      final path = await captureToFile(key);
      await ref
          .read(backendProvider)
          .sendItem(
            SendRequest(
              type: _type,
              imagePath: path,
              caption: _type == ItemType.note ? '' : _caption.text.trim(),
              text: _type == ItemType.note ? _note.text.trim() : null,
              noteStyle: _type == ItemType.note ? NoteStyle(bg: _noteBg, font: _noteFont) : null,
              geo: _type == ItemType.location ? _geo : null,
              saveToMemories: _saveToMemories,
              secret: _secret && _type != ItemType.location,
            ),
          );
    });
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      hapticMedium();
      showToast(
        context,
        _secret && _type != ItemType.location
            ? 'Sent anonymously 🕵️ Reveal it from Memories when you’re ready'
            : 'Sent to $name’s widget 💌',
        icon: Icons.check_circle_rounded,
      );
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
                'Get unlimited sends with Duosy Plus — for both of you. Or watch a short ad for +${FreeLimits.rewardedExtraSends} more today.',
                textAlign: TextAlign.center,
                style: ctx.tt.bodyMedium?.copyWith(color: ctx.cc.muted),
              ),
              const SizedBox(height: Space.l),
              CloserButton(
                label: 'Try Duosy Plus free',
                kind: CloserButtonKind.accent,
                onPressed: () => Navigator.pop(ctx, 'plus'),
              ),
              const SizedBox(height: Space.s),
              CloserButton(
                label: 'Watch an ad for +${FreeLimits.rewardedExtraSends}',
                kind: CloserButtonKind.secondary,
                onPressed: () => Navigator.pop(ctx, 'ad'),
              ),
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
      body: Column(
        children: [
          // Violet header with a close button and the four kinds as tiles
          // (Figma "send photo screen").
          VioletPageHeader(
            title: 'Send',
            leadingIcon: Icons.close_rounded,
            leadingTooltip: 'Close',
            backdropHeight: 156,
            actions: [
              if (left != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: left == 0 ? context.cs.error : Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
                  ),
                  child: Text(
                    '$left of ${FreeLimits.sendsPerDay} left today',
                    style: context.tt.labelMedium?.copyWith(color: Colors.white),
                  ),
                ),
            ],
            child: Row(
              children: [
                for (final (i, t) in const [
                  (Icons.photo_camera_outlined, 'Photo'),
                  (Icons.sticky_note_2_outlined, 'Note'),
                  (Icons.edit_outlined, 'Doodle'),
                  (Icons.location_on_outlined, 'Location'),
                ].indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _KindTile(
                      icon: t.$1,
                      label: t.$2,
                      selected: _tabs.index == i,
                      onTap: () => _tabs.animateTo(i),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              physics: const NeverScrollableScrollPhysics(),
              children: [_photoTab(), _noteTab(), _doodleTab(), _locationTab()],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Column(
                children: [
                  _OptionCard(
                    title: 'Also save to Memories',
                    value: _saveToMemories,
                    onChanged: (v) => setState(() => _saveToMemories = v),
                  ),
                  // A stamped location gives the sender away, so no secrets there.
                  if (_type != ItemType.location) ...[
                    const SizedBox(height: 10),
                    _OptionCard(
                      title: 'Send as a secret admirer 🕵️',
                      subtitle: '$name won’t see it’s from you until you reveal it',
                      value: _secret,
                      onChanged: (v) => setState(() => _secret = v),
                    ),
                  ],
                  const SizedBox(height: 14),
                  PillButton(
                    label: 'Send to $name’s widget',
                    icon: Icons.send_outlined,
                    loading: _sending,
                    onPressed: _canSend ? _send : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The chosen photo in a white photo-frame card (Figma location polaroid).
  /// Only the inner square is captured, so the frame never ends up in the
  /// sent image. The sticker tip sits on the frame's bottom strip.
  Widget _framed(Widget child, GlobalKey key) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
        decoration: BoxDecoration(
          color: context.cc.card,
          borderRadius: BorderRadius.circular(28),
          boxShadow: dark ? null : softCardShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: RepaintBoundary(key: key, child: child),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
              child: Row(
                children: [
                  IconTile(
                    icon: _stickers.isEmpty ? Icons.pinch_outlined : Icons.emoji_emotions_outlined,
                    tone: SoftTone.pink,
                    size: 34,
                    filled: true,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _stickers.isEmpty
                          ? 'Pinch to zoom, then add a caption or stickers'
                          : 'Drag stickers to move, pinch to resize, long-press to remove',
                      style: context.tt.bodySmall?.copyWith(color: context.cc.muted, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoTab() {
    final photo = _photo;
    return ListView(
      // The violet header already covers the status bar.
      padding: EdgeInsets.zero,
      children: [
        if (photo == null)
          // Pink "Share a moment" card with the mascot (Figma).
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9CCB),
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: const [
                    BoxShadow(color: Color(0x40FF5C9E), blurRadius: 30, offset: Offset(0, 16), spreadRadius: -12),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Whole mascot (the progress one is cropped to peek from a card edge).
                    Image.asset('assets/together/streak_mascot.png', width: 112, height: 124),
                    const SizedBox(height: 10),
                    Text('Share a moment', style: context.tt.headlineSmall?.copyWith(color: Brand.ink, fontSize: 24)),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _SourceButton(
                          icon: Icons.photo_camera_outlined,
                          label: 'Camera',
                          primary: true,
                          onTap: () => _pick(ImageSource.camera),
                        ),
                        const SizedBox(width: 10),
                        _SourceButton(
                          icon: Icons.image_outlined,
                          label: 'Gallery',
                          onTap: () => _pick(ImageSource.gallery),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          )
        else ...[
          _framed(
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
          // Caption pill and round tool buttons (Figma "send location after
          // click photo" row).
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: _CaptionPill(controller: _caption, maxLength: Item.maxCaption),
                ),
                const SizedBox(width: 10),
                CircleIconButton(icon: Icons.emoji_emotions_outlined, tooltip: 'Add sticker', onTap: _pickStickers),
                const SizedBox(width: 10),
                CircleIconButton(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Choose another photo',
                  onTap: () => _pick(ImageSource.gallery),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _noteTab() {
    return ListView(
      // The violet header already covers the status bar.
      padding: EdgeInsets.zero,
      children: [
        // Slightly tilted white photo frame around the note (Figma "send note
        // screen"). Only the note square inside is captured and sent.
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 22, 32, 18),
          child: Transform.rotate(
            angle: -0.035,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.cc.card,
                borderRadius: BorderRadius.circular(26),
                boxShadow: Theme.of(context).brightness == Brightness.dark ? null : softCardShadow,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: RepaintBoundary(
                  key: _noteKey,
                  child: NoteCard(
                    text: _note.text,
                    style: NoteStyle(bg: _noteBg, font: _noteFont),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _NoteField(controller: _note, onChanged: () => setState(() {})),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final bg in noteBackgrounds)
                    _NoteSwatch(
                      background: bg,
                      selected: _noteBg == bg.id,
                      onTap: () => setState(() => _noteBg = bg.id),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _FontPicker(selected: _noteFont, onSelect: (f) => setState(() => _noteFont = f)),
              const SizedBox(height: 14),
            ],
          ),
        ),
      ],
    );
  }

  Widget _doodleTab() {
    const colors = [
      Color(0xFFFF6B8A),
      Color(0xFF2F7BE6),
      Color(0xFF5DBB63),
      Color(0xFFFFB547),
      Color(0xFF7C6CF2),
      Color(0xFF1C2433),
      Colors.white,
    ];
    final photo = _photo;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // No scrolling here: drags on the canvas must draw. The colours and
    // tools keep their natural height and the square canvas takes whatever
    // room is left (Expanded + AspectRatio), so nothing can overflow.
    return LayoutBuilder(
      builder: (context, c) {
        return Column(
          children: [
            // White drawing card (Figma "send doodle screen"); only the square
            // inside is captured.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: dark ? null : softCardShadow,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: RepaintBoundary(
                          key: _doodleKey,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (photo != null)
                                Image.file(File(photo), fit: BoxFit.cover)
                              else
                                const ColoredBox(color: Colors.white),
                              DoodleCanvas(controller: _doodle),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final c in colors)
                        _PenSwatch(
                          color: c,
                          selected: !_doodle.eraser && _doodle.color == c,
                          onTap: () => _doodle.setColor(c),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Tools in one white pill: size, pen / eraser, undo, photo.
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 2, 6, 2),
                    decoration: BoxDecoration(
                      color: context.cc.card,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: dark ? null : softCardShadow,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.notes_rounded, size: 21, color: context.cs.onSurface),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 5,
                              activeTrackColor: Brand.royal,
                              inactiveTrackColor: dark ? context.cs.surfaceContainerHigh : const Color(0xFFE4DDFB),
                              thumbColor: Brand.royal,
                              overlayColor: Brand.royal.withValues(alpha: 0.12),
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                              trackShape: const RoundedRectSliderTrackShape(),
                            ),
                            child: Slider(
                              value: _doodle.width,
                              min: 3,
                              max: 24,
                              onChanged: _doodle.setWidth,
                              label: 'Pen size',
                            ),
                          ),
                        ),
                        _ToolButton(
                          tooltip: 'Eraser',
                          icon: _doodle.eraser ? Icons.auto_fix_high_outlined : Icons.edit_outlined,
                          active: _doodle.eraser,
                          onTap: _doodle.toggleEraser,
                        ),
                        _ToolButton(
                          tooltip: 'Undo',
                          icon: Icons.undo_rounded,
                          onTap: _doodle.isEmpty ? null : _doodle.undo,
                        ),
                        _ToolButton(
                          tooltip: photo == null ? 'Draw over a photo' : 'Remove photo',
                          icon: photo == null ? Icons.image_outlined : Icons.hide_image_outlined,
                          onTap: () => photo == null ? _pick(ImageSource.gallery) : setState(() => _photo = null),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _locationTab() {
    final photo = _locPhoto;
    if (photo == null) {
      return ListView(
        // The violet header already covers the status bar.
        padding: EdgeInsets.zero,
        children: [
          // Pink card with the mascot and a pin badge (Figma "send location").
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: AspectRatio(
              aspectRatio: 0.92,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9CCB),
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: const [
                    BoxShadow(color: Color(0x40FF5C9E), blurRadius: 30, offset: Offset(0, 16), spreadRadius: -12),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 140,
                      height: 128,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          Image.asset('assets/together/streak_mascot.png', width: 104, height: 115),
                          Positioned(
                            right: 6,
                            top: 0,
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Color(0x33C2185B), blurRadius: 10, offset: Offset(0, 4))],
                              ),
                              child: Icon(Icons.location_on_outlined, size: 23, color: SoftTone.pink.icon),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Show where you are',
                      textAlign: TextAlign.center,
                      style: context.tt.headlineSmall?.copyWith(color: Brand.ink, fontSize: 24),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Snap a photo — we’ll stamp it with your place and time.',
                      textAlign: TextAlign.center,
                      style: context.tt.bodyMedium?.copyWith(color: Brand.ink.withValues(alpha: 0.85)),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: 190,
                      child: PillButton(
                        label: 'Open camera',
                        icon: Icons.photo_camera_outlined,
                        height: 50,
                        loading: _locating,
                        onPressed: _captureLocation,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
      // The violet header already covers the status bar.
      padding: EdgeInsets.zero,
      children: [
        // Tilted white photo card with the place stamp under the photo
        // (Figma "send location after click photo"). The card's contents are
        // the captured image, so the stamp travels with it.
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 22, 26, 18),
          child: Transform.rotate(
            angle: -0.03,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                boxShadow: dark ? null : softCardShadow,
              ),
              child: AspectRatio(
                aspectRatio: 1,
                child: RepaintBoundary(
                  key: _locationKey,
                  child: ColoredBox(
                    color: Colors.white,
                    child: Column(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: SizedBox.expand(child: Image.file(File(photo), fit: BoxFit.cover)),
                          ),
                        ),
                        _LocationStamp(geo: _geo, time: _locTime ?? DateTime.now(), locating: _locating),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: _CaptionPill(controller: _caption, maxLength: Item.maxCaption),
              ),
              const SizedBox(width: 10),
              CircleIconButton(
                icon: Icons.gps_fixed_rounded,
                tooltip: 'Update location',
                onTap: _locating ? null : _refreshLocation,
              ),
              const SizedBox(width: 10),
              CircleIconButton(
                icon: Icons.photo_camera_outlined,
                tooltip: 'Retake photo',
                onTap: _locating ? null : () => _captureLocation(retakeOnly: true),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Place stamp under a location photo: pink pin tile, place, coordinates
/// and time, on white. It is part of the captured image.
class _LocationStamp extends StatelessWidget {
  const _LocationStamp({required this.geo, required this.time, required this.locating});

  final GeoTag? geo;
  final DateTime time;
  final bool locating;

  @override
  Widget build(BuildContext context) {
    final g = geo;
    // Fixed colours: the stamp is baked into the photo, so it must not follow
    // dark mode.
    const ink = Color(0xFF1E1B3A);
    const muted = Color(0xFF5B5675);
    const small = TextStyle(color: muted, fontWeight: FontWeight.w700, fontSize: 12, height: 1.3);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: Color(0xFFFFE3F0), shape: BoxShape.circle),
            child: locating
                ? const Padding(
                    padding: EdgeInsets.all(11),
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFC2185B)),
                  )
                : const Icon(Icons.location_on_outlined, color: Color(0xFFC2185B), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  g == null
                      ? (locating ? 'Finding your location…' : 'Location unavailable')
                      : (g.place.isEmpty ? 'Here right now' : g.place),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: ink, fontFamily: 'Fredoka', fontWeight: FontWeight.w600, fontSize: 16),
                ),
                if (g != null) Text(g.coords, style: small),
                Text(DateFormat('EEE d MMM yyyy · HH:mm').format(time), style: small),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Doodle pen colour; the chosen one gets a dark ring with a white gap.
class _PenSwatch extends StatelessWidget {
  const _PenSwatch({required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Pen colour',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 42,
          height: 42,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.cc.card,
            border: Border.all(color: selected ? context.cs.onSurface : Colors.transparent, width: 2.5),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: color == Colors.white ? Border.all(color: const Color(0xFFD2C7F7), width: 1.5) : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon button in the doodle tool pill; violet tint when [active].
class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.tooltip, required this.icon, required this.onTap, this.active = false});

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? SoftTone.violet.fill(context) : Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(
              icon,
              size: 21,
              color: onTap == null
                  ? context.cs.onSurface.withValues(alpha: 0.3)
                  : (active ? Brand.royal : context.cs.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of Photo / Note / Doodle / Location on the violet header: frosted
/// tile, white when chosen with violet icon and label.
class _KindTile extends StatelessWidget {
  const _KindTile({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Brand.royal : Colors.white;
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: selected ? 1 : 0.4)),
          boxShadow: selected
              ? const [BoxShadow(color: Color(0x332A1A6E), blurRadius: 14, offset: Offset(0, 6), spreadRadius: -4)]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 21, color: fg),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.tt.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Camera (solid violet) / Gallery (white) pill on the pink card.
class _SourceButton extends StatelessWidget {
  const _SourceButton({required this.icon, required this.label, required this.onTap, this.primary = false});

  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.white : Brand.royal;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: primary
            ? const [BoxShadow(color: Color(0x596A3DF0), blurRadius: 18, offset: Offset(0, 8), spreadRadius: -4)]
            : const [BoxShadow(color: Color(0x1AFF5C9E), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Material(
        color: primary ? Brand.royal : Colors.white,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 19, color: fg),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: context.tt.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// White card with a title (+ muted line) and a compact switch.
class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.title, required this.value, required this.onChanged, this.subtitle});

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.cc.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: dark ? null : softCardShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      if (subtitle != null)
                        Text(subtitle!, style: context.tt.bodySmall?.copyWith(color: context.cc.muted, height: 1.3)),
                    ],
                  ),
                ),
                SoftSwitch(value: value, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// White pill text field with a soft shadow (Figma "Add a caption").
class _CaptionPill extends StatelessWidget {
  const _CaptionPill({required this.controller, required this.maxLength});

  final TextEditingController controller;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const none = OutlineInputBorder(borderSide: BorderSide.none);
    return Container(
      decoration: BoxDecoration(
        color: context.cc.card,
        borderRadius: BorderRadius.circular(999),
        boxShadow: dark ? null : softCardShadow,
      ),
      child: TextField(
        controller: controller,
        maxLength: maxLength,
        textCapitalization: TextCapitalization.sentences,
        style: context.tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: 'Add a caption',
          hintStyle: context.tt.bodyLarge?.copyWith(color: context.cc.muted, fontWeight: FontWeight.w600),
          counterText: '',
          filled: false,
          border: none,
          enabledBorder: none,
          focusedBorder: none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
    );
  }
}

/// White rounded note field with the count inside (Figma "0/140").
class _NoteField extends StatelessWidget {
  const _NoteField({required this.controller, required this.onChanged});

  static const maxLength = 140;

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const none = OutlineInputBorder(borderSide: BorderSide.none);
    return Container(
      decoration: BoxDecoration(
        color: context.cc.card,
        borderRadius: BorderRadius.circular(22),
        boxShadow: dark ? null : softCardShadow,
      ),
      child: TextField(
        controller: controller,
        maxLength: maxLength,
        maxLines: 3,
        minLines: 1,
        textCapitalization: TextCapitalization.sentences,
        style: context.tt.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
        onChanged: (_) => onChanged(),
        decoration: InputDecoration(
          hintText: 'Write something sweet…',
          hintStyle: context.tt.bodyLarge?.copyWith(color: context.cc.muted, fontWeight: FontWeight.w700),
          counterText: '',
          filled: false,
          border: none,
          enabledBorder: none,
          focusedBorder: none,
          contentPadding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(
              '${controller.text.length}/$maxLength',
              style: context.tt.labelSmall?.copyWith(color: context.cc.muted, fontWeight: FontWeight.w800),
            ),
          ),
          suffixIconConstraints: const BoxConstraints(minHeight: 20, minWidth: 20),
        ),
      ),
    );
  }
}

/// Note colour circle; the chosen one gets a dark ring with a white gap.
class _NoteSwatch extends StatelessWidget {
  const _NoteSwatch({required this.background, required this.selected, required this.onTap});

  final NoteBackground background;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Background ${background.id}',
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 46,
          height: 46,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.cc.card,
            border: Border.all(color: selected ? context.cs.onSurface : Colors.transparent, width: 2.5),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: background.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
              boxShadow: [
                BoxShadow(
                  color: background.colors.last.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded / Serif / Mono in a white pill; the chosen one is solid violet
/// with a check, the others show their own typeface.
class _FontPicker extends StatelessWidget {
  const _FontPicker({required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  static const _fonts = [('rounded', 'Rounded', null), ('serif', 'Serif', 'serif'), ('mono', 'Mono', 'monospace')];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: context.cc.card,
        borderRadius: BorderRadius.circular(999),
        boxShadow: dark ? null : softCardShadow,
      ),
      child: Row(
        children: [
          for (final (id, label, family) in _fonts)
            Expanded(
              child: Semantics(
                button: true,
                selected: selected == id,
                child: GestureDetector(
                  onTap: () => onSelect(id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: selected == id ? Brand.royal : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (selected == id) ...[
                          const Icon(Icons.check_rounded, size: 17, color: Colors.white),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          label,
                          style: context.tt.labelLarge?.copyWith(
                            fontFamily: family,
                            fontWeight: FontWeight.w800,
                            color: selected == id ? Colors.white : context.cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
