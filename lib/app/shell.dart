import 'dart:async';

import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/soft_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Soft gradient backdrop + floating pill navigation with the Send button in
/// the centre (plan 9.3).
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
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m - 4),
        child: _PillNav(
          children: [
            _NavItem(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home_rounded,
              label: 'Home',
              selected: shell.currentIndex == 0,
              onTap: () => go(0),
            ),
            _NavItem(
              icon: Icons.wb_sunny_outlined,
              selectedIcon: Icons.wb_sunny_rounded,
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
      ),
    );
  }
}

class _PillNav extends StatelessWidget {
  const _PillNav({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: dark ? Brand.darkSurfaceHigh.withValues(alpha: 0.96) : Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: Colors.white.withValues(alpha: dark ? 0.06 : 1)),
        boxShadow: const [BoxShadow(color: Color(0x225B50E0), blurRadius: 30, offset: Offset(0, 12))],
      ),
      child: Row(children: [for (final c in children) Expanded(child: c)]),
    );
  }
}

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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = selected ? context.cs.onSurface : context.cc.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? (dark ? Colors.white.withValues(alpha: 0.08) : Brand.purpleTint) : Colors.transparent,
            borderRadius: BorderRadius.circular(30),
          ),
          child: ExcludeSemantics(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(selected ? selectedIcon : icon, color: fg, size: 24),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, style: context.tt.labelSmall?.copyWith(color: fg, fontSize: 11)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton();

  @override
  Widget build(BuildContext context) {
    final cc = context.cc;
    return Center(
      child: Semantics(
        button: true,
        label: 'Send to their widget',
        child: GestureDetector(
          onTap: () {
            unawaited(HapticFeedback.selectionClick());
            unawaited(context.push('/send'));
          },
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: cc.gradient),
              boxShadow: [
                BoxShadow(color: cc.accent.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6)),
              ],
            ),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
          ),
        ),
      ),
    );
  }
}
