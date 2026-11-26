import 'dart:async';
import 'dart:math' as math;

import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/soft_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Soft gradient backdrop + a floating frosted-glass dock, with the raised
/// Send button in the centre (plan 9.3).
class AppShell extends StatelessWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    void go(int branch) {
      unawaited(HapticFeedback.selectionClick());
      shell.goBranch(branch, initialLocation: branch == shell.currentIndex);
    }

    // Branch indices: 0 home, 1 together, 2 memories, 3 me.
    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: SoftBackground(child: shell),
      bottomNavigationBar: _Dock(
        children: [
          _NavItem(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home_rounded,
            label: 'Home',
            selected: shell.currentIndex == 0,
            onTap: () => go(0),
          ),
          _NavItem(
            icon: Icons.favorite_border_rounded,
            selectedIcon: Icons.favorite_rounded,
            label: 'Together',
            selected: shell.currentIndex == 1,
            onTap: () => go(1),
          ),
          const _SendButton(),
          _NavItem(
            icon: Icons.image_outlined,
            selectedIcon: Icons.image_rounded,
            label: 'Memories',
            selected: shell.currentIndex == 2,
            onTap: () => go(2),
          ),
          _NavItem(
            icon: Icons.person_outline_rounded,
            selectedIcon: Icons.person_rounded,
            label: 'Me',
            selected: shell.currentIndex == 3,
            onTap: () => go(3),
          ),
        ],
      ),
    );
  }
}

/// Floating white dock (Figma: 358 × 68 pill with a violet glow); the Send
/// button rises 10 px above it.
class _Dock extends StatelessWidget {
  const _Dock({required this.children});

  final List<Widget> children;

  static const _height = 78.0;
  static const _dockHeight = 68.0;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final radius = BorderRadius.circular(_dockHeight / 2);
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.m, 0, Space.m, math.max(bottomInset, Space.m)),
      child: SizedBox(
        height: _height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              top: _height - _dockHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: dark ? Brand.darkSurface : Colors.white,
                  borderRadius: radius,
                  border: dark ? Border.all(color: Colors.white.withValues(alpha: 0.08)) : null,
                  boxShadow: [
                    BoxShadow(
                      color: dark ? Colors.black.withValues(alpha: 0.4) : const Color(0x386A3DF0),
                      blurRadius: 30,
                      offset: const Offset(0, 16),
                      spreadRadius: -10,
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [for (final c in children) Expanded(child: c)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tab: soft tinted pill behind a filled icon when selected.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = context.cs.primary;
    final fg = selected ? primary : Brand.grey700;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ExcludeSemantics(
          child: SizedBox(
            height: _Dock._dockHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  width: 48,
                  height: 28,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: selected ? Brand.purpleTint : Brand.purpleTint.withValues(alpha: 0),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                    child: Icon(selected ? selectedIcon : icon, key: ValueKey(selected), color: fg, size: 22),
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: context.tt.labelSmall?.copyWith(color: fg, fontSize: 12, fontWeight: FontWeight.w800),
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

/// Raised round gradient button in the middle of the dock.
class _SendButton extends StatefulWidget {
  const _SendButton();

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: 'Send to their widget',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () {
          unawaited(HapticFeedback.mediumImpact());
          unawaited(context.push('/send'));
        },
        child: ExcludeSemantics(
          child: Align(
            alignment: Alignment.topCenter,
            child: AnimatedScale(
              scale: _down ? 0.9 : 1,
              duration: const Duration(milliseconds: 120),
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Brand.royal,
                  border: Border.all(color: dark ? Brand.darkBg : Brand.cream, width: 2),
                  boxShadow: [
                    BoxShadow(color: Brand.royal.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 8)),
                  ],
                ),
                child: const Icon(Icons.add_rounded, color: Colors.white, size: 32),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
