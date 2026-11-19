import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

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
            icon: Icons.photo_library_outlined,
            selectedIcon: Icons.photo_library_rounded,
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

/// Floating frosted-glass dock. Total height matches the old bar so the
/// screens' bottom padding still fits; the Send button rises above it.
class _Dock extends StatelessWidget {
  const _Dock({required this.children});

  final List<Widget> children;

  static const _height = 77.0;
  static const _dockHeight = 64.0;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final radius = BorderRadius.circular(26);
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.m, 0, Space.m, math.max(bottomInset, Space.m)),
      child: SizedBox(
        height: _height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Glass slab.
            Positioned.fill(
              top: _height - _dockHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  boxShadow: [
                    BoxShadow(
                      color: (dark ? Colors.black : Brand.royal).withValues(alpha: dark ? 0.4 : 0.14),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: radius,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: dark
                              ? [Brand.darkSurface.withValues(alpha: 0.82), Brand.darkSurface.withValues(alpha: 0.94)]
                              : [Colors.white.withValues(alpha: 0.8), Colors.white.withValues(alpha: 0.94)],
                        ),
                        border: Border.all(
                          color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ),
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
    final fg = selected ? primary : context.cc.muted;
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
                  width: selected ? 52 : 36,
                  height: 30,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    color: selected ? primary.withValues(alpha: 0.13) : primary.withValues(alpha: 0),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                    child: Icon(selected ? selectedIcon : icon, key: ValueKey(selected), color: fg, size: 23),
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: context.tt.labelSmall?.copyWith(
                      color: fg,
                      fontSize: 11.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
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
    final g = context.cc.gradient;
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
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Brand.royalLight, Brand.royal, g.last],
                    stops: const [0, 0.55, 1],
                  ),
                  border: Border.all(color: dark ? Brand.darkSurface : Colors.white, width: 4),
                  boxShadow: [
                    BoxShadow(color: Brand.royal.withValues(alpha: 0.4), blurRadius: 18, offset: const Offset(0, 8)),
                    BoxShadow(color: g.last.withValues(alpha: 0.3), blurRadius: 26, spreadRadius: -6),
                  ],
                ),
                child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
