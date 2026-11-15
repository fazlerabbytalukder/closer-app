import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Row of reaction emojis for an item (photo, note, doodle). Tapping one
/// sets your reaction (tap it again to remove it) and floats a little burst
/// of that emoji upwards. Shows what your partner reacted with.
class ReactionBar extends ConsumerStatefulWidget {
  const ReactionBar({required this.item, this.onDark = false, super.key});

  final Item item;

  /// Light text for dark backgrounds (the full-screen viewer).
  final bool onDark;

  @override
  ConsumerState<ReactionBar> createState() => _ReactionBarState();
}

class _ReactionBarState extends ConsumerState<ReactionBar> {
  final _bursts = <(int, String)>[];

  /// Optimistic value while the server call is in flight.
  String? _pending;
  bool _busy = false;

  Future<void> _react(String emoji, String? current) async {
    if (_busy) return;
    final next = current == emoji ? null : emoji;
    hapticSoft();
    setState(() {
      _busy = true;
      _pending = next ?? '';
      if (next != null) _bursts.add((DateTime.now().microsecondsSinceEpoch, next));
    });
    await runAction(context, () => ref.read(backendProvider).reactToItem(widget.item.id, next));
    if (mounted) {
      setState(() {
        _busy = false;
        _pending = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authUidProvider).value;
    final name = ref.watch(partnerNameProvider);
    final saved = me == null ? null : widget.item.reactions[me];
    final mine = _pending == null ? saved : (_pending!.isEmpty ? null : _pending);
    final theirs = widget.item.reactions.entries.where((e) => e.key != me).map((e) => e.value).firstOrNull;
    final fg = widget.onDark ? Colors.white : context.cs.onSurface;
    final muted = widget.onDark ? Colors.white70 : context.cc.muted;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (theirs != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.xs),
            child: Text(
              widget.item.senderId == me ? '$name reacted $theirs' : '$name reacted $theirs too',
              style: context.tt.bodySmall?.copyWith(color: muted, fontWeight: FontWeight.w600),
            ).animate().fadeIn(duration: 250.ms),
          ),
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: (widget.onDark ? Colors.white : context.cs.surfaceContainerHighest).withValues(alpha: widget.onDark ? 0.12 : 0.6),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final e in reactionEmojis)
                    Semantics(
                      button: true,
                      selected: mine == e,
                      label: mine == e ? 'Remove reaction $e' : 'React with $e',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _react(e, mine),
                        child: AnimatedContainer(
                          duration: 200.ms,
                          curve: Curves.easeOutBack,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: mine == e ? context.cc.accent.withValues(alpha: 0.25) : Colors.transparent,
                          ),
                          child: AnimatedScale(
                            scale: mine == e ? 1.25 : 1,
                            duration: 200.ms,
                            curve: Curves.easeOutBack,
                            child: Text(e, style: TextStyle(fontSize: 22, color: fg)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            for (final (id, emoji) in _bursts)
              for (var i = 0; i < 5; i++)
                Positioned(
                  key: ValueKey('$id-$i'),
                  bottom: 20,
                  child: IgnorePointer(
                    child: Text(emoji, style: const TextStyle(fontSize: 26))
                        .animate(
                          delay: (i * 70).ms,
                          onComplete: i == 4 ? (_) => setState(() => _bursts.removeWhere((b) => b.$1 == id)) : null,
                        )
                        .scale(begin: const Offset(0.4, 0.4), end: const Offset(1.2, 1.2), duration: 300.ms, curve: Curves.easeOutBack)
                        .moveY(begin: 0, end: -90 - i * 14.0, duration: 900.ms, curve: Curves.easeOut)
                        .moveX(begin: 0, end: (i - 2) * 26.0, duration: 900.ms)
                        .fadeOut(delay: 450.ms, duration: 450.ms),
                  ),
                ),
          ],
        ),
      ],
    );
  }
}

/// Small stacked reaction emojis drawn over a memory tile.
class ReactionBadge extends StatelessWidget {
  const ReactionBadge({required this.reactions, super.key});

  final Map<String, String> reactions;

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Text(reactions.values.toSet().join(), style: const TextStyle(fontSize: 12)),
    );
  }
}
