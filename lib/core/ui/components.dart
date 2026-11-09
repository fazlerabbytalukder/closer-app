import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/theme/gloss.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum CloserButtonKind { primary, accent, secondary, ghost }

/// Pill button used across the app.
class CloserButton extends StatelessWidget {
  const CloserButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.kind = CloserButtonKind.primary,
    this.icon,
    this.loading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final CloserButtonKind kind;
  final IconData? icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          );
    final onTap = loading ? null : onPressed;
    final Widget button = switch (kind) {
      CloserButtonKind.primary => FilledButton(onPressed: onTap, child: child),
      CloserButtonKind.accent => FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: context.cc.accent,
          foregroundColor: Colors.white,
          shadowColor: context.cc.accent,
        ),
        onPressed: onTap,
        child: child,
      ),
      CloserButtonKind.secondary => OutlinedButton(onPressed: onTap, child: child),
      CloserButtonKind.ghost => TextButton(onPressed: onTap, child: child),
    };
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Rounded white card with optional tap.
class CloserCard extends StatelessWidget {
  const CloserCard({
    required this.child,
    super.key,
    this.onTap,
    this.padding = const EdgeInsets.all(Space.m),
    this.color,
    this.gradient,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color? color;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? context.cc.card) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(Radii.card),
        boxShadow: dark ? null : const [BoxShadow(color: Color(0x165B50E0), blurRadius: 30, offset: Offset(0, 10))],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.card),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Image from a local file path or a URL.
class AppImage extends StatelessWidget {
  const AppImage(this.source, {super.key, this.fit = BoxFit.cover});

  final String? source;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final s = source;
    final placeholder = ColoredBox(color: context.cs.surfaceContainer);
    if (s == null || s.isEmpty) return placeholder;
    if (s.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: s,
        fit: fit,
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => placeholder,
      );
    }
    return Image.file(File(s), fit: fit, gaplessPlayback: true, errorBuilder: (_, _, _) => placeholder);
  }
}

class Avatar extends StatelessWidget {
  const Avatar({required this.name, super.key, this.photo, this.size = 48, this.ring});

  final String name;
  final String? photo;
  final double size;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(ring == null ? 0 : 2.5),
      decoration: BoxDecoration(shape: BoxShape.circle, color: ring),
      child: ClipOval(
        child: photo != null && photo!.isNotEmpty
            ? AppImage(photo)
            : DecoratedBox(
                decoration: BoxDecoration(gradient: LinearGradient(colors: context.cc.gradient)),
                child: Center(
                  child: Text(
                    initial,
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.42),
                  ),
                ),
              ),
      ),
    );
  }
}

/// Two overlapping avatars with a heart.
class AvatarPair extends StatelessWidget {
  const AvatarPair({
    required this.me,
    required this.partner,
    super.key,
    this.mePhoto,
    this.partnerPhoto,
    this.size = 56,
  });

  final String me;
  final String partner;
  final String? mePhoto;
  final String? partnerPhoto;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return SizedBox(
      width: size * 1.75,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Avatar(name: me, photo: mePhoto, size: size, ring: bg),
          Positioned(
            left: size * 0.75,
            child: Avatar(name: partner, photo: partnerPhoto, size: size, ring: bg),
          ),
          Positioned(
            left: size * 0.62,
            bottom: -4,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(Icons.favorite, size: size * 0.32, color: context.cc.accent),
            ),
          ),
        ],
      ),
    );
  }
}

/// Blurred content with a lock + call to action (Plus walls, unrevealed
/// answers).
class LockedCard extends StatelessWidget {
  const LockedCard({
    required this.child,
    required this.label,
    super.key,
    this.onTap,
    this.icon = Icons.lock_rounded,
    this.locked = true,
    this.sigma = 8,
  });

  final Widget child;
  final String label;
  final VoidCallback? onTap;
  final IconData icon;
  final bool locked;
  final double sigma;

  @override
  Widget build(BuildContext context) {
    if (!locked) return child;
    return Semantics(
      button: onTap != null,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ExcludeSemantics(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                child: child,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: context.cs.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16),
                  const SizedBox(width: 6),
                  Text(label, style: context.tt.labelMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CounterChip extends StatelessWidget {
  const CounterChip({required this.label, super.key, this.icon, this.color});

  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.cc.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(100)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 16, color: c), const SizedBox(width: 4)],
          Text(label, style: context.tt.labelSmall?.copyWith(color: c)),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.l, bottom: Space.s),
      child: Row(
        children: [
          Expanded(child: Text(title, style: context.tt.titleMedium)),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({required this.emoji, required this.title, super.key, this.body, this.action, this.onAction});

  final String emoji;
  final String title;
  final String? body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 56)),
            const SizedBox(height: Space.m),
            Text(title, style: context.tt.titleLarge, textAlign: TextAlign.center),
            if (body != null) ...[
              const SizedBox(height: Space.s),
              Text(
                body!,
                style: context.tt.bodyMedium?.copyWith(color: context.cc.muted),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: Space.l),
              CloserButton(label: action!, onPressed: onAction, expand: false),
            ],
          ],
        ),
      ),
    );
  }
}

/// Round icon button with a semantics label (TalkBack).
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
    this.color,
    this.background,
    this.size = 48,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final Color? background;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: background ?? context.cs.surfaceContainer,
        shape: const CircleBorder(),
        elevation: onPressed == null ? 0 : 3,
        shadowColor: context.cs.primary.withValues(alpha: 0.6),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Gloss(
            circle: true,
            enabled: onPressed != null,
            strength: 0.6,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: color, size: size * 0.48),
            ),
          ),
        ),
      ),
    );
  }
}

void showToast(BuildContext context, String message, {IconData? icon}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[Icon(icon, color: Colors.white, size: 20), const SizedBox(width: 10)],
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

void hapticSoft() => HapticFeedback.lightImpact();
void hapticMedium() => HapticFeedback.mediumImpact();

/// Relative time like "just now", "2m ago", "3h ago", "Yesterday".
String timeAgo(DateTime t, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final d = n.difference(t);
  if (d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays == 1) return 'Yesterday';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${t.day}/${t.month}/${t.year}';
}
