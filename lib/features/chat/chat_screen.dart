import 'dart:async';
import 'dart:io';

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/data/closer_backend.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/screen_guard.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/soft_ui.dart';
import 'package:closer_app/core/ui/voice.dart';
import 'package:closer_app/features/chat/chat_heads.dart';
import 'package:closer_app/features/chat/snap_widgets.dart';
import 'package:closer_app/features/love/love_widgets.dart';
import 'package:closer_bubbles/closer_bubbles.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

const _chatReactions = ['❤️', '😂', '😍', '🥹', '😮', '👍'];

/// Private chat (F11): text, photos, voice messages, disappearing snaps,
/// replies, reactions, "typing…" and "Seen". Screenshots and saved photos
/// show up as a line in the chat for both of you.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, this.inBubble = false});

  /// Running inside the chat head (Android bubble).
  final bool inBubble;

  /// True while the chat is on screen (no in-app notifications then).
  static bool isOpen = false;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> with WidgetsBindingObserver {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _recorder = VoiceRecorder();
  ReplyRef? _replyTo;
  bool _canPopOut = false;
  bool _recording = false;
  bool _sending = false;
  DateTime _lastTypingSent = DateTime(0);
  Timer? _typingIdle;
  Timer? _readDebounce;
  StreamSubscription<void>? _screenshots;
  DateTime _lastScreenshot = DateTime(0);

  /// The pair's disappearing setting, kept from the last build.
  ChatTtl _ttl = ChatTtl.fallback;

  /// Kept from initState: timers and dispose must not touch `ref`.
  late final CloserBackend _backend;

  @override
  void initState() {
    super.initState();
    _backend = ref.read(backendProvider);
    ChatScreen.isOpen = true;
    WidgetsBinding.instance.addObserver(this);
    _text.addListener(_onTextChanged);
    _screenshots = ScreenGuard.screenshots.listen((_) => _onScreenshot());
    if (!widget.inBubble && Platform.isAndroid) {
      unawaited(ChatBubbles.isSupported().then((v) => mounted ? setState(() => _canPopOut = v) : null));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  /// Tells the partner (one line per burst of screenshots).
  void _onScreenshot() {
    final now = DateTime.now();
    if (now.difference(_lastScreenshot) < const Duration(seconds: 3)) return;
    _lastScreenshot = now;
    final snap = SnapViewer.showing;
    final about = snap == null ? null : ReplyRef(id: snap.id, senderId: snap.senderId, preview: snap.preview);
    unawaited(
      _backend
          .sendChatEvent(ChatEvent.screenshot, about: about, ttl: _ttl)
          .catchError((Object e) => debugPrint('screenshot event: $e')),
    );
  }

  /// Leaving the chat (closed or app sent to the background): "after
  /// viewing" messages you've seen disappear.
  void _leave() {
    unawaited(_backend.clearViewedMessages().catchError((Object e) => debugPrint('clearViewed: $e')));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _leave();
  }

  Future<void> _pickTtl() async {
    final current = _ttl;
    // One colour per option, as in the Figma rows.
    SoftTone toneFor(ChatTtl t) => switch (t) {
      ChatTtl.viewed => SoftTone.blue,
      ChatTtl.never => SoftTone.yellow,
      _ when t == ChatTtl.fallback => SoftTone.pink,
      _ => SoftTone.mint,
    };
    final picked = await showSoftSheet<ChatTtl>(
      context,
      header: const SoftSheetHeader(
        icon: Icon(Icons.timer_outlined),
        tone: SoftTone.pink,
        title: 'Disappearing messages',
        subtitle: 'For new messages, for both of you. Either of you can change it.',
      ),
      children: [
        for (final t in ChatTtl.values)
          Builder(
            builder: (ctx) => SoftOptionTile(
              icon: t == ChatTtl.never
                  ? Icons.timer_off_outlined
                  : (t == ChatTtl.viewed ? Icons.visibility_outlined : Icons.timer_outlined),
              tone: toneFor(t),
              title: t == ChatTtl.fallback ? '${t.label} (default)' : t.label,
              subtitle: t.description,
              selected: t == current,
              onTap: () => Navigator.pop(ctx, t),
            ),
          ),
      ],
    );
    if (picked == null || picked == current || !mounted) return;
    final ok = await runAction(context, () => _backend.setChatTtl(picked));
    if (ok && mounted) hapticSoft();
  }

  @override
  void dispose() {
    ChatScreen.isOpen = false;
    WidgetsBinding.instance.removeObserver(this);
    _leave();
    unawaited(_screenshots?.cancel());
    _typingIdle?.cancel();
    _readDebounce?.cancel();
    if (_lastTypingSent.isAfter(DateTime.now().subtract(const Duration(seconds: 6)))) {
      unawaited(_backend.setTyping(typing: false).catchError((Object _) {}));
    }
    _text.dispose();
    _focus.dispose();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  void _markRead() {
    _readDebounce?.cancel();
    _readDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_backend.markChatRead().catchError((Object _) {}));
    });
  }

  void _onTextChanged() {
    setState(() {});
    if (_text.text.isEmpty) return;
    final now = DateTime.now();
    if (now.difference(_lastTypingSent) > const Duration(seconds: 4)) {
      _lastTypingSent = now;
      unawaited(_backend.setTyping(typing: true).catchError((Object _) {}));
    }
    _typingIdle?.cancel();
    _typingIdle = Timer(const Duration(seconds: 5), () {
      _lastTypingSent = DateTime(0);
      unawaited(_backend.setTyping(typing: false).catchError((Object _) {}));
    });
  }

  Future<void> _send(ChatDraft draft) async {
    setState(() => _sending = true);
    final ok = await runAction(context, () => ref.read(backendProvider).sendMessage(draft.withTtl(_ttl)));
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (ok) _replyTo = null;
    });
    if (ok) {
      hapticSoft();
      _typingIdle?.cancel();
      _lastTypingSent = DateTime(0);
    }
  }

  Future<void> _sendText() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    await _send(ChatDraft(text: t, replyTo: _replyTo));
  }

  Future<void> _pickPhoto() async {
    final source = await showSoftSheet<ImageSource>(
      context,
      header: SoftSheetHeader(
        icon: const Icon(Icons.image_outlined),
        title: 'Send a photo',
        subtitle: 'It shows up in your chat with $_partnerName.',
      ),
      children: _sourceOptions(),
    );
    if (source == null) return;
    final x = await ImagePicker().pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 90);
    if (x == null || !mounted) return;
    final caption = _text.text.trim();
    _text.clear();
    await _send(ChatDraft(type: MessageType.photo, localPath: x.path, text: caption, replyTo: _replyTo));
  }

  Future<void> _pickSnap() async {
    final source = await showSoftSheet<ImageSource>(
      context,
      header: SoftSheetHeader(
        icon: CustomPaint(size: const Size(22, 24), painter: _GhostPainter(SoftTone.violet.icon)),
        title: 'Disappearing snap',
        subtitle: 'Opens once or twice, then it’s gone.',
      ),
      children: _sourceOptions(),
    );
    if (source == null) return;
    final x = await ImagePicker().pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 90);
    if (x == null || !mounted) return;
    final views = await showSnapSendSheet(context, x.path, ref.read(partnerNameProvider));
    if (views == null || !mounted) return;
    await _send(ChatDraft(type: MessageType.snap, localPath: x.path, viewLimit: views, replyTo: _replyTo));
  }

  /// Camera / Gallery choices shared by the photo and snap sheets.
  List<Widget> _sourceOptions() => [
    Builder(
      builder: (ctx) => SoftOptionTile(
        icon: Icons.photo_camera_outlined,
        title: 'Camera',
        subtitle: 'Take a new photo',
        onTap: () => Navigator.pop(ctx, ImageSource.camera),
      ),
    ),
    Builder(
      builder: (ctx) => SoftOptionTile(
        icon: Icons.photo_library_outlined,
        tone: SoftTone.pink,
        title: 'Gallery',
        subtitle: 'Pick one from your photos',
        onTap: () => Navigator.pop(ctx, ImageSource.gallery),
      ),
    ),
  ];

  Future<void> _openSnap(ChatMessage m, String? me, String name) async {
    if (m.senderId == me) {
      final seen = switch (m.views) {
        0 => 'Not opened yet',
        1 => 'Opened once',
        _ => 'Opened ${m.views} times',
      };
      showToast(context, seen, icon: Icons.visibility_rounded);
      return;
    }
    if (m.snapUsedUp) {
      showToast(context, 'This snap is gone 👻');
      return;
    }
    hapticSoft();
    await SnapViewer.open(context, m, name);
  }

  Future<void> _savePhoto(ChatMessage m, String? me) async {
    final ok = await runAction(context, () => savePhotoToPhone(_backend, m.mediaPath));
    if (!ok || !mounted) return;
    showToast(context, 'Saved to your photos', icon: Icons.download_done_rounded);
    // Saving their photo tells them, like a screenshot does.
    if (m.senderId != me) {
      unawaited(
        _backend
            .sendChatEvent(
              ChatEvent.saved,
              about: ReplyRef(id: m.id, senderId: m.senderId, preview: m.preview),
              ttl: _ttl,
            )
            .catchError((Object e) => debugPrint('saved event: $e')),
      );
    }
  }

  /// Turns the chat into a floating chat head.
  Future<void> _popOut(String name, String? photo) async {
    final prefs = ref.read(prefsProvider);
    await prefs.setBool(ChatHeads.prefKey, true);
    if (!await ChatBubbles.areAllowed()) {
      if (!mounted) return;
      final go = await showSoftDialog(
        context,
        icon: const Icon(Icons.bubble_chart_outlined),
        title: 'Turn on chat heads',
        body:
            'Allow Duosy to show bubbles so your chat floats over other apps. '
            'In the settings, choose “All conversations can bubble”.',
        ok: 'Open settings',
      );
      if (go ?? false) await ChatBubbles.openSettings();
      return;
    }
    await ChatHeads.notify(prefs, name: name, photo: photo);
    if (!mounted) return;
    hapticSoft();
    showToast(context, 'Chat head is on — it floats over your other apps 💬', icon: Icons.bubble_chart_rounded);
  }

  Future<void> _startRecording() async {
    hapticMedium();
    try {
      final ok = await _recorder.start();
      if (!ok) {
        if (mounted) showToast(context, 'Allow the microphone to send voice messages', icon: Icons.mic_off_rounded);
        return;
      }
      if (mounted) setState(() => _recording = true);
    } on Object catch (e) {
      debugPrint('Recording failed: $e');
      if (mounted) showToast(context, 'Couldn’t start recording', icon: Icons.mic_off_rounded);
    }
  }

  Future<void> _finishRecording() async {
    if (!_recording) return;
    setState(() => _recording = false);
    final clip = await _recorder.stop();
    if (clip == null || !mounted) return;
    if (clip.durationMs < 700) {
      showToast(context, 'Hold on a bit longer to record');
      return;
    }
    await _send(
      ChatDraft(type: MessageType.voice, localPath: clip.path, durationMs: clip.durationMs, replyTo: _replyTo),
    );
  }

  Future<void> _cancelRecording() async {
    setState(() => _recording = false);
    await _recorder.cancel();
  }

  void _reply(ChatMessage m) {
    if (m.isDeleted || m.isEvent) return;
    hapticSoft();
    setState(() => _replyTo = ReplyRef(id: m.id, senderId: m.senderId, preview: m.preview));
    _focus.requestFocus();
  }

  Future<void> _actions(ChatMessage m, String? me) async {
    if (m.isDeleted || m.isEvent) return;
    hapticMedium();
    final mine = m.senderId == me;
    final current = me == null ? null : m.reactions[me];
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.m),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final e in _chatReactions)
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => Navigator.pop(ctx, 'react:$e'),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: current == e ? ctx.cc.accentTint : null,
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 28)),
                      ),
                    ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Reply'),
              onTap: () => Navigator.pop(ctx, 'reply'),
            ),
            if (m.type == MessageType.text)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Copy'),
                onTap: () => Navigator.pop(ctx, 'copy'),
              ),
            if (m.type == MessageType.photo && m.mediaPath != null)
              ListTile(
                leading: const Icon(Icons.download_rounded),
                title: const Text('Save to phone'),
                subtitle: mine ? null : Text('$_partnerName will see that you saved it'),
                onTap: () => Navigator.pop(ctx, 'save'),
              ),
            if (mine)
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: ctx.cs.error),
                title: Text('Delete for both of us', style: TextStyle(color: ctx.cs.error)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final backend = ref.read(backendProvider);
    if (action.startsWith('react:')) {
      final e = action.substring(6);
      await runAction(context, () => backend.reactToMessage(m.id, current == e ? null : e));
    } else if (action == 'reply') {
      _reply(m);
    } else if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.text));
      if (mounted) showToast(context, 'Copied');
    } else if (action == 'save') {
      await _savePhoto(m, me);
    } else if (action == 'delete') {
      await runAction(context, () => backend.deleteMessage(m.id));
    }
  }

  String get _partnerName => ref.read(partnerNameProvider);

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authUidProvider).value;
    final partnerUid = ref.watch(partnerUidProvider);
    final partner = ref.watch(partnerProvider).value;
    final name = ref.watch(partnerNameProvider);
    final states = ref.watch(chatStateProvider).value ?? const <String, ChatState>{};
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final ttl = _ttl = ref.watch(pairProvider).value?.chatTtl ?? ChatTtl.fallback;
    // Timed messages vanish on time, before the hourly cleanup deletes them.
    final messages = [
      for (final m in ref.watch(messagesProvider).value ?? const <ChatMessage>[])
        if (!m.isExpired(DateTime.now())) m,
    ];
    final partnerState = partnerUid == null ? null : states[partnerUid];
    final typing = partnerState?.isTyping(DateTime.now()) ?? false;
    final partnerRead = partnerState?.readAt;
    final lastMine = messages.lastWhere(
      (m) => m.senderId == me && !m.isEvent,
      orElse: () => ChatMessage(id: '', senderId: '', createdAt: DateTime(0)),
    );
    ref.listen(messagesProvider, (_, _) => _markRead());

    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Column(
        children: [
          // Floating white header pill (Figma "chat screen").
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Container(
                padding: EdgeInsets.fromLTRB(widget.inBubble ? 14 : 8, 8, 8, 8),
                decoration: BoxDecoration(
                  color: context.cc.card,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: dark ? null : _floatShadow,
                ),
                child: Row(
                  children: [
                    if (!widget.inBubble) ...[
                      _RoundIconButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Avatar(name: partner?.displayName ?? name, photo: partner?.photoUrl, size: 42),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.tt.titleLarge?.copyWith(fontSize: 19, height: 1.1),
                          ),
                          AnimatedSwitcher(
                            duration: 200.ms,
                            child: typing
                                ? Text(
                                    'typing…',
                                    key: const ValueKey('t'),
                                    style: context.tt.bodySmall?.copyWith(
                                      color: context.cs.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )
                                : partner?.mood != null
                                ? Text(
                                    '${partner!.mood!.emoji} ${partner.mood!.label}',
                                    key: const ValueKey('m'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.tt.bodySmall?.copyWith(
                                      color: context.cc.muted,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )
                                : const SizedBox.shrink(key: ValueKey('n')),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    _TtlChip(ttl: ttl, onTap: _pickTtl),
                    if (widget.inBubble) ...[
                      const SizedBox(width: 6),
                      _RoundIconButton(
                        icon: Icons.open_in_full_rounded,
                        tooltip: 'Open in Duosy',
                        onTap: () => launchUrl(Uri.parse('closer://chat'), mode: LaunchMode.externalApplication),
                      ),
                    ] else if (_canPopOut) ...[
                      const SizedBox(width: 6),
                      _RoundIconButton(
                        icon: Icons.bubble_chart_outlined,
                        tooltip: 'Pop out as a chat head',
                        onTap: () => _popOut(name, partner?.photoUrl),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: messages.isEmpty
                ? EmptyState(
                    emoji: '💬',
                    title: 'Just the two of you',
                    body: 'Say hi to $name. Only you two can see this chat.\n⏱️ ${ttl.description}.',
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    itemCount: messages.length + (typing ? 1 : 0) + 1,
                    itemBuilder: (context, i) {
                      if (typing && i == 0) return const _TypingBubble();
                      // Oldest end of the list: what the disappearing setting is.
                      if (i == messages.length + (typing ? 1 : 0)) return _TtlBanner(ttl: ttl, onTap: _pickTtl);
                      final idx = messages.length - 1 - (i - (typing ? 1 : 0));
                      final m = messages[idx];
                      final prev = idx > 0 ? messages[idx - 1] : null;
                      final next = idx < messages.length - 1 ? messages[idx + 1] : null;
                      final newDay = prev == null || !_sameDay(prev.createdAt, m.createdAt);
                      final groupedWithNext =
                          next != null &&
                          !next.isEvent &&
                          next.senderId == m.senderId &&
                          next.createdAt.difference(m.createdAt).inMinutes < 3;
                      final seen = m.id == lastMine.id && partnerRead != null && !partnerRead.isBefore(m.createdAt);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (newDay) _DaySeparator(day: m.createdAt, now: now),
                          if (m.isEvent)
                            _EventLine(message: m, mine: m.senderId == me, name: name)
                          else
                            _Bubble(
                              message: m,
                              mine: m.senderId == me,
                              me: me,
                              name: name,
                              tail: !groupedWithNext,
                              seen: seen,
                              onLongPress: () => _actions(m, me),
                              onSwipeReply: () => _reply(m),
                              onOpenSnap: () => _openSnap(m, me, name),
                            ),
                        ],
                      );
                    },
                  ),
          ),
          if (_replyTo != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
              decoration: BoxDecoration(
                color: context.cc.card,
                borderRadius: BorderRadius.circular(20),
                boxShadow: dark ? null : _floatShadow,
              ),
              child: Row(
                children: [
                  Container(width: 3, height: 36, color: context.cc.accent),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _replyTo!.senderId == me ? 'Replying to yourself' : 'Replying to $name',
                          style: context.tt.labelMedium?.copyWith(color: context.cc.accent),
                        ),
                        Text(
                          _replyTo!.preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.tt.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancel reply',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() => _replyTo = null),
                  ),
                ],
              ),
            ),
          // Floating white composer pill (Figma): photo + ghost icons,
          // lavender field and a solid violet mic / send button.
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: context.cc.card,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: dark ? null : _floatShadow,
                ),
                child: _recording
                    ? RecordingBar(recorder: _recorder, onCancel: _cancelRecording, onDone: _finishRecording)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _ComposerIcon(
                            tooltip: 'Send a photo',
                            onTap: _sending ? null : _pickPhoto,
                            child: Icon(Icons.image_outlined, color: context.cs.primary, size: 23),
                          ),
                          if (_text.text.trim().isEmpty)
                            _ComposerIcon(
                              tooltip: 'Send a disappearing snap',
                              onTap: _sending ? null : _pickSnap,
                              child: CustomPaint(size: const Size(20, 22), painter: _GhostPainter(context.cs.primary)),
                            ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: TextField(
                              controller: _text,
                              focusNode: _focus,
                              minLines: 1,
                              maxLines: 5,
                              maxLength: ChatMessage.maxText,
                              textCapitalization: TextCapitalization.sentences,
                              style: context.tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                              decoration: InputDecoration(
                                hintText: 'Message $name',
                                hintStyle: context.tt.bodyLarge?.copyWith(
                                  color: context.cc.muted,
                                  fontWeight: FontWeight.w600,
                                ),
                                counterText: '',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(26),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(26),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(26),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: dark ? context.cs.surfaceContainerHigh : const Color(0xFFF1EDFF),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          _SendCircle(
                            tooltip: _text.text.trim().isEmpty ? 'Record a voice message' : 'Send',
                            onTap: _sending ? null : (_text.text.trim().isEmpty ? _startRecording : _sendText),
                            child: _sending && _text.text.trim().isNotEmpty
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : Icon(
                                    _text.text.trim().isEmpty ? Icons.mic_none_rounded : Icons.send_rounded,
                                    color: Colors.white,
                                    size: 23,
                                  ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.day, required this.now});

  final DateTime day;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final yesterday = now.subtract(const Duration(days: 1));
    final label = _sameDay(day, now)
        ? 'Today'
        : _sameDay(day, yesterday)
        ? 'Yesterday'
        : DateFormat(day.year == now.year ? 'EEEE d MMMM' : 'd MMMM yyyy').format(day);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(color: context.cc.card, borderRadius: BorderRadius.circular(999)),
          child: Text(
            label,
            style: context.tt.labelSmall?.copyWith(
              color: context.cs.onSurface.withValues(alpha: 0.75),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

/// "📸 Sam took a screenshot" — centred, like a day separator.
class _EventLine extends StatelessWidget {
  const _EventLine({required this.message, required this.mine, required this.name});

  final ChatMessage message;
  final bool mine;
  final String name;

  @override
  Widget build(BuildContext context) {
    final who = mine ? 'You' : name;
    final about = message.replyTo;
    // Whose photo it was, from the reader's side.
    final String owner;
    if (about == null) {
      owner = '';
    } else if (about.senderId == message.senderId) {
      owner = mine ? 'your own' : 'their own';
    } else {
      owner = mine ? '$name’s' : 'your';
    }
    final what = (about?.preview.startsWith('👻') ?? false) ? 'snap' : 'photo';
    final text = switch (message.event) {
      ChatEvent.screenshot when about != null => '📸 $who took a screenshot of $owner $what',
      ChatEvent.screenshot => '📸 $who took a screenshot of the chat',
      ChatEvent.saved when about != null => '⬇️ $who saved $owner photo',
      ChatEvent.saved => '⬇️ $who saved a photo',
      ChatEvent.ttl => '⏱️ $who ${ChatTtl.parse(message.text).sentence}',
      null => '',
    };
    final time = DateFormat('HH:mm').format(message.createdAt);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(color: context.cc.accentTint, borderRadius: BorderRadius.circular(999)),
          child: Text(
            '$text · $time',
            textAlign: TextAlign.center,
            style: context.tt.labelSmall?.copyWith(color: context.cc.accent, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 250.ms);
  }
}

/// Top of the chat: "⏱️ Messages disappear after 24 hours".
class _TtlBanner extends StatelessWidget {
  const _TtlBanner({required this.ttl, required this.onTap});

  final ChatTtl ttl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = switch (ttl) {
      ChatTtl.never => 'Messages are kept. Tap to make them disappear.',
      ChatTtl.viewed => 'Messages disappear once they’re seen and the chat is closed.',
      _ => 'Messages disappear ${ttl.label} after they’re sent.',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.m),
      child: Center(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text.rich(
              TextSpan(
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 5),
                      child: Icon(
                        ttl == ChatTtl.never ? Icons.timer_off_outlined : Icons.timer_outlined,
                        size: 15,
                        color: context.cc.muted,
                      ),
                    ),
                  ),
                  TextSpan(text: text),
                ],
              ),
              textAlign: TextAlign.center,
              style: context.tt.labelMedium?.copyWith(color: context.cc.muted, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}

/// A snap in the chat: "Tap to view" for the partner, its status for you.
class _SnapTile extends StatelessWidget {
  const _SnapTile({required this.message, required this.mine, required this.fg, required this.onTap});

  final ChatMessage message;
  final bool mine;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final gone = m.snapUsedUp;
    final String title;
    final String sub;
    if (mine) {
      title = 'Snap';
      sub = switch (m.views) {
        0 => m.pending ? 'Sending…' : 'Delivered · opens ${m.viewLimit == 1 ? 'once' : 'twice'}',
        _ when gone => 'Opened',
        _ => 'Opened once · 1 view left',
      };
    } else if (gone) {
      title = 'Snap';
      sub = 'Opened';
    } else {
      title = 'Tap to view';
      sub = m.snapViewsLeft == 1 ? '1 view left' : '${m.snapViewsLeft} views left';
    }
    final active = !mine && !gone;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? context.cc.accent : fg.withValues(alpha: 0.12),
              border: gone ? Border.all(color: fg.withValues(alpha: 0.4), width: 1.5) : null,
            ),
            child: Text(gone ? '✓' : '👻', style: TextStyle(fontSize: 16, color: fg)),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: context.tt.titleSmall?.copyWith(color: fg, fontWeight: FontWeight.w700),
              ),
              Text(sub, style: context.tt.bodySmall?.copyWith(color: fg.withValues(alpha: 0.75))),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: context.cc.card, borderRadius: BorderRadius.circular(22)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(color: context.cc.muted, shape: BoxShape.circle),
                  )
                  .animate(onPlay: (c) => c.repeat(reverse: true), delay: (i * 150).ms)
                  .moveY(begin: 0, end: -4, duration: 350.ms, curve: Curves.easeInOut),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatefulWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.me,
    required this.name,
    required this.tail,
    required this.seen,
    required this.onLongPress,
    required this.onSwipeReply,
    required this.onOpenSnap,
  });

  final ChatMessage message;
  final bool mine;
  final String? me;
  final String name;
  final bool tail;
  final bool seen;
  final VoidCallback onLongPress;
  final VoidCallback onSwipeReply;
  final VoidCallback onOpenSnap;

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> {
  double _drag = 0;

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final mine = widget.mine;
    final fg = mine ? Colors.white : context.cs.onSurface;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Figma: fully rounded bubbles, no tail.
    final radius = BorderRadius.circular(22);
    final time = DateFormat('HH:mm').format(m.createdAt);

    Widget content;
    if (m.isDeleted) {
      content = Text(
        '🚫 Message deleted',
        style: TextStyle(color: fg.withValues(alpha: 0.7), fontStyle: FontStyle.italic),
      );
    } else {
      content = switch (m.type) {
        MessageType.text => Text(
          m.text,
          style: context.tt.bodyLarge?.copyWith(color: fg, height: 1.3, fontWeight: FontWeight.w700),
        ),
        MessageType.voice => VoicePlayer(
          mediaPath: m.mediaPath,
          durationMs: m.durationMs,
          onDark: mine,
          seed: m.id.hashCode,
        ),
        MessageType.snap => _SnapTile(message: m, mine: mine, fg: fg, onTap: widget.onOpenSnap),
        MessageType.event => const SizedBox.shrink(),
        MessageType.photo => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => _openPhoto(context, m.mediaPath),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240, maxHeight: 300),
                  child: m.mediaPath == null ? const SizedBox(width: 200, height: 150) : StoredImage(m.mediaPath),
                ),
              ),
            ),
            if (m.text.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(m.text, style: context.tt.bodyLarge?.copyWith(color: fg)),
            ],
          ],
        ),
      };
    }

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
      padding: m.type == MessageType.photo && !m.isDeleted
          ? const EdgeInsets.all(4)
          : const EdgeInsets.fromLTRB(16, 11, 16, 11),
      decoration: BoxDecoration(
        borderRadius: radius,
        color: mine ? Brand.royal : context.cc.card,
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: mine ? const Color(0x336A3DF0) : const Color(0x146A3DF0),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                  spreadRadius: -4,
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m.replyTo case final r? when !m.isDeleted)
            Container(
              margin: EdgeInsets.fromLTRB(
                m.type == MessageType.photo ? 6 : 0,
                m.type == MessageType.photo ? 6 : 0,
                0,
                6,
              ),
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              decoration: BoxDecoration(
                color: (mine ? Colors.white : context.cc.accent).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: mine ? Colors.white : context.cc.accent, width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.senderId == widget.me ? 'You' : widget.name,
                    style: context.tt.labelSmall?.copyWith(
                      color: mine ? Colors.white : context.cc.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    r.preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.tt.bodySmall?.copyWith(color: fg.withValues(alpha: 0.85)),
                  ),
                ],
              ),
            ),
          content,
        ],
      ),
    );

    return GestureDetector(
      onLongPress: widget.onLongPress,
      onHorizontalDragUpdate: m.isDeleted ? null : (d) => setState(() => _drag = (_drag + d.delta.dx).clamp(0, 70)),
      onHorizontalDragEnd: m.isDeleted
          ? null
          : (_) {
              if (_drag > 50) widget.onSwipeReply();
              setState(() => _drag = 0);
            },
      child: AnimatedContainer(
        duration: _drag == 0 ? 200.ms : Duration.zero,
        transform: Matrix4.translationValues(_drag, 0, 0),
        padding: EdgeInsets.only(top: 2, bottom: widget.tail ? 10 : 2),
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: EdgeInsets.only(bottom: m.reactions.isEmpty ? 0 : 14),
                  child: bubble,
                ),
                if (m.reactions.isNotEmpty)
                  Positioned(
                    bottom: 0,
                    right: mine ? null : -4,
                    left: mine ? -4 : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: context.cc.card,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 4, offset: Offset(0, 1))],
                      ),
                      child: Text(m.reactions.values.toSet().join(), style: const TextStyle(fontSize: 13)),
                    ).animate().scale(duration: 250.ms, curve: Curves.easeOutBack),
                  ),
              ],
            ),
            if (widget.tail)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      time,
                      style: context.tt.labelSmall?.copyWith(
                        color: context.cs.onSurface.withValues(alpha: 0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (mine && m.pending) ...[
                      const SizedBox(width: 3),
                      Icon(Icons.schedule_rounded, size: 11, color: context.cc.muted),
                    ] else if (mine && widget.seen) ...[
                      const SizedBox(width: 6),
                      Text(
                        'Seen',
                        style: context.tt.labelSmall?.copyWith(
                          color: const Color(0xFFC2185B),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openPhoto(BuildContext context, String? path) {
    if (path == null) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
              body: InteractiveViewer(
                child: Center(child: StoredImage(path, fit: BoxFit.contain)),
              ),
            ),
          ),
        )
        .ignore();
  }
}

/// Soft violet shadow under the floating header and composer pills.
const _floatShadow = [BoxShadow(color: Color(0x266A3DF0), blurRadius: 24, offset: Offset(0, 10), spreadRadius: -6)];

/// Lavender round button in the header (back, pop-out).
class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: dark ? context.cs.surfaceContainerHigh : const Color(0xFFF1EDFF),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 42, height: 42, child: Icon(icon, size: 21, color: context.cs.primary)),
        ),
      ),
    );
  }
}

/// Pink "⏱ 24h" chip: the disappearing-messages setting.
class _TtlChip extends StatelessWidget {
  const _TtlChip({required this.ttl, required this.onTap});

  final ChatTtl ttl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFFC2185B);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: 'Disappearing messages: ${ttl.label}',
      child: Material(
        color: dark ? ink.withValues(alpha: 0.22) : const Color(0xFFFFE3F0),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  ttl == ChatTtl.never ? Icons.timer_off_outlined : Icons.timer_outlined,
                  size: 17,
                  color: dark ? const Color(0xFFFF9CCB) : ink,
                ),
                const SizedBox(width: 5),
                Text(
                  ttl.short,
                  style: context.tt.labelLarge?.copyWith(
                    color: dark ? const Color(0xFFFF9CCB) : ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Plain icon button inside the composer pill.
class _ComposerIcon extends StatelessWidget {
  const _ComposerIcon({required this.tooltip, required this.onTap, required this.child});

  final String tooltip;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.4 : 1,
          child: SizedBox(width: 44, height: 48, child: Center(child: child)),
        ),
      ),
    );
  }
}

/// Solid violet circle: record a voice message, or send.
class _SendCircle extends StatelessWidget {
  const _SendCircle({required this.tooltip, required this.onTap, required this.child});

  final String tooltip;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: onTap == null ? Brand.royal.withValues(alpha: 0.5) : Brand.royal,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 48, height: 48, child: Center(child: child)),
        ),
      ),
    );
  }
}

/// Outline ghost (Figma's snap icon): domed head, wavy hem, two eyes.
class _GhostPainter extends CustomPainter {
  const _GhostPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final body = Path()
      ..moveTo(w * 0.1, h * 0.92)
      ..lineTo(w * 0.1, h * 0.45)
      ..arcToPoint(Offset(w * 0.9, h * 0.45), radius: Radius.circular(w * 0.4))
      ..lineTo(w * 0.9, h * 0.92)
      ..quadraticBezierTo(w * 0.8, h * 0.8, w * 0.7, h * 0.92)
      ..quadraticBezierTo(w * 0.6, h * 0.8, w * 0.5, h * 0.92)
      ..quadraticBezierTo(w * 0.4, h * 0.8, w * 0.3, h * 0.92)
      ..quadraticBezierTo(w * 0.2, h * 0.8, w * 0.1, h * 0.92)
      ..close();
    canvas.drawPath(body, stroke);
    final eye = Paint()..color = color;
    canvas
      ..drawCircle(Offset(w * 0.37, h * 0.43), w * 0.065, eye)
      ..drawCircle(Offset(w * 0.63, h * 0.43), w * 0.065, eye);
  }

  @override
  bool shouldRepaint(_GhostPainter old) => old.color != color;
}
