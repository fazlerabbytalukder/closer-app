import 'dart:async';

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/data/closer_backend.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/voice.dart';
import 'package:closer_app/features/love/love_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

const _chatReactions = ['❤️', '😂', '😍', '🥹', '😮', '👍'];

/// Private chat (F11): text, photos, voice messages, replies, reactions,
/// "typing…" and "Seen".
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  /// True while the chat is on screen (no in-app notifications then).
  static bool isOpen = false;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _recorder = VoiceRecorder();
  ReplyRef? _replyTo;
  bool _recording = false;
  bool _sending = false;
  DateTime _lastTypingSent = DateTime(0);
  Timer? _typingIdle;
  Timer? _readDebounce;

  /// Kept from initState: timers and dispose must not touch `ref`.
  late final CloserBackend _backend;

  @override
  void initState() {
    super.initState();
    _backend = ref.read(backendProvider);
    ChatScreen.isOpen = true;
    _text.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  @override
  void dispose() {
    ChatScreen.isOpen = false;
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
    final ok = await runAction(context, () => ref.read(backendProvider).sendMessage(draft));
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
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.photo_camera_rounded), title: const Text('Camera'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
            ListTile(leading: const Icon(Icons.photo_library_rounded), title: const Text('Gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
          ],
        ),
      ),
    );
    if (source == null) return;
    final x = await ImagePicker().pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 90);
    if (x == null || !mounted) return;
    final caption = _text.text.trim();
    _text.clear();
    await _send(ChatDraft(type: MessageType.photo, localPath: x.path, text: caption, replyTo: _replyTo));
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
    await _send(ChatDraft(type: MessageType.voice, localPath: clip.path, durationMs: clip.durationMs, replyTo: _replyTo));
  }

  Future<void> _cancelRecording() async {
    setState(() => _recording = false);
    await _recorder.cancel();
  }

  void _reply(ChatMessage m) {
    if (m.isDeleted) return;
    hapticSoft();
    setState(() => _replyTo = ReplyRef(id: m.id, senderId: m.senderId, preview: m.preview));
    _focus.requestFocus();
  }

  Future<void> _actions(ChatMessage m, String? me) async {
    if (m.isDeleted) return;
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
                        decoration: BoxDecoration(shape: BoxShape.circle, color: current == e ? ctx.cc.accentTint : null),
                        child: Text(e, style: const TextStyle(fontSize: 28)),
                      ),
                    ),
                ],
              ),
            ),
            ListTile(leading: const Icon(Icons.reply_rounded), title: const Text('Reply'), onTap: () => Navigator.pop(ctx, 'reply')),
            if (m.type == MessageType.text)
              ListTile(leading: const Icon(Icons.copy_rounded), title: const Text('Copy'), onTap: () => Navigator.pop(ctx, 'copy')),
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
    } else if (action == 'delete') {
      await runAction(context, () => backend.deleteMessage(m.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authUidProvider).value;
    final partnerUid = ref.watch(partnerUidProvider);
    final partner = ref.watch(partnerProvider).value;
    final name = ref.watch(partnerNameProvider);
    final messages = ref.watch(messagesProvider).value ?? const <ChatMessage>[];
    final states = ref.watch(chatStateProvider).value ?? const <String, ChatState>{};
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final partnerState = partnerUid == null ? null : states[partnerUid];
    final typing = partnerState?.isTyping(DateTime.now()) ?? false;
    final partnerRead = partnerState?.readAt;
    final lastMine = messages.lastWhere((m) => m.senderId == me, orElse: () => ChatMessage(id: '', senderId: '', createdAt: DateTime(0)));
    ref.listen(messagesProvider, (_, _) => _markRead());

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Avatar(name: partner?.displayName ?? name, photo: partner?.photoUrl, size: 36),
            const SizedBox(width: Space.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: context.tt.titleMedium, overflow: TextOverflow.ellipsis),
                  AnimatedSwitcher(
                    duration: 200.ms,
                    child: typing
                        ? Text('typing…', key: const ValueKey('t'), style: context.tt.bodySmall?.copyWith(color: context.cc.accent))
                        : partner?.mood != null
                            ? Text('${partner!.mood!.emoji} ${partner.mood!.label}', key: const ValueKey('m'), style: context.tt.bodySmall?.copyWith(color: context.cc.muted))
                            : const SizedBox.shrink(key: ValueKey('n')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? EmptyState(emoji: '💬', title: 'Just the two of you', body: 'Say hi to $name. Only you two can see this chat.')
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(Space.s + 4, Space.s, Space.s + 4, Space.s),
                    itemCount: messages.length + (typing ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (typing && i == 0) return const _TypingBubble();
                      final idx = messages.length - 1 - (i - (typing ? 1 : 0));
                      final m = messages[idx];
                      final prev = idx > 0 ? messages[idx - 1] : null;
                      final next = idx < messages.length - 1 ? messages[idx + 1] : null;
                      final newDay = prev == null || !_sameDay(prev.createdAt, m.createdAt);
                      final groupedWithNext = next != null && next.senderId == m.senderId && next.createdAt.difference(m.createdAt).inMinutes < 3;
                      final seen = m.id == lastMine.id && partnerRead != null && !partnerRead.isBefore(m.createdAt);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (newDay) _DaySeparator(day: m.createdAt, now: now),
                          _Bubble(
                            message: m,
                            mine: m.senderId == me,
                            me: me,
                            name: name,
                            tail: !groupedWithNext,
                            seen: seen,
                            onLongPress: () => _actions(m, me),
                            onSwipeReply: () => _reply(m),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          if (_replyTo != null)
            Container(
              color: context.cc.card,
              padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.xs, 0),
              child: Row(
                children: [
                  Container(width: 3, height: 36, color: context.cc.accent),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_replyTo!.senderId == me ? 'Replying to yourself' : 'Replying to $name',
                            style: context.tt.labelMedium?.copyWith(color: context.cc.accent)),
                        Text(_replyTo!.preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall),
                      ],
                    ),
                  ),
                  IconButton(tooltip: 'Cancel reply', icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _replyTo = null)),
                ],
              ),
            ),
          Material(
            color: context.cc.card,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.xs, Space.xs, Space.xs, Space.xs),
                child: _recording
                    ? RecordingBar(recorder: _recorder, onCancel: _cancelRecording, onDone: _finishRecording)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(tooltip: 'Send a photo', icon: const Icon(Icons.add_photo_alternate_rounded), onPressed: _sending ? null : _pickPhoto),
                          Expanded(
                            child: TextField(
                              controller: _text,
                              focusNode: _focus,
                              minLines: 1,
                              maxLines: 5,
                              maxLength: ChatMessage.maxText,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                hintText: 'Message $name',
                                counterText: '',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                                filled: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          if (_text.text.trim().isEmpty)
                            IconButton.filledTonal(
                              tooltip: 'Record a voice message',
                              icon: const Icon(Icons.mic_rounded),
                              onPressed: _sending ? null : _startRecording,
                            )
                          else
                            IconButton.filled(
                              tooltip: 'Send',
                              icon: _sending
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.send_rounded),
                              onPressed: _sending ? null : _sendText,
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
      padding: const EdgeInsets.symmetric(vertical: Space.s),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(color: context.cc.card, borderRadius: BorderRadius.circular(999)),
          child: Text(label, style: context.tt.labelSmall?.copyWith(color: context.cc.muted)),
        ),
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
        decoration: BoxDecoration(color: context.cc.card, borderRadius: BorderRadius.circular(18)),
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
  });

  final ChatMessage message;
  final bool mine;
  final String? me;
  final String name;
  final bool tail;
  final bool seen;
  final VoidCallback onLongPress;
  final VoidCallback onSwipeReply;

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
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(!mine && widget.tail ? 4 : 18),
      bottomRight: Radius.circular(mine && widget.tail ? 4 : 18),
    );
    final time = DateFormat('HH:mm').format(m.createdAt);

    Widget content;
    if (m.isDeleted) {
      content = Text('🚫 Message deleted', style: TextStyle(color: fg.withValues(alpha: 0.7), fontStyle: FontStyle.italic));
    } else {
      content = switch (m.type) {
        MessageType.text => Text(m.text, style: context.tt.bodyLarge?.copyWith(color: fg, height: 1.3)),
        MessageType.voice => VoicePlayer(mediaPath: m.mediaPath, durationMs: m.durationMs, onDark: mine, seed: m.id.hashCode),
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
      padding: m.type == MessageType.photo && !m.isDeleted ? const EdgeInsets.all(4) : const EdgeInsets.fromLTRB(14, 9, 14, 9),
      decoration: BoxDecoration(
        borderRadius: radius,
        color: mine ? null : context.cc.card,
        gradient: mine ? LinearGradient(colors: context.cc.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m.replyTo case final r? when !m.isDeleted)
            Container(
              margin: EdgeInsets.fromLTRB(m.type == MessageType.photo ? 6 : 0, m.type == MessageType.photo ? 6 : 0, 0, 6),
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
                    style: context.tt.labelSmall?.copyWith(color: mine ? Colors.white : context.cc.accent, fontWeight: FontWeight.w800),
                  ),
                  Text(r.preview, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall?.copyWith(color: fg.withValues(alpha: 0.85))),
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
        padding: EdgeInsets.only(top: 2, bottom: widget.tail ? 6 : 1),
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
                padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(time, style: context.tt.labelSmall?.copyWith(color: context.cc.muted, fontSize: 10)),
                    if (mine && m.pending) ...[
                      const SizedBox(width: 3),
                      Icon(Icons.schedule_rounded, size: 11, color: context.cc.muted),
                    ] else if (mine && widget.seen) ...[
                      const SizedBox(width: 4),
                      Text('Seen', style: context.tt.labelSmall?.copyWith(color: context.cc.accent, fontSize: 10)),
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
          body: InteractiveViewer(child: Center(child: StoredImage(path, fit: BoxFit.contain))),
        ),
      ),
    ).ignore();
  }
}
