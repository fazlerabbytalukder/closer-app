import 'package:closer_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Bottom navigation with the Send button in the centre (plan 9.3).
class AppShell extends StatelessWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final cc = context.cc;
    // Branch indices: 0 home, 1 together, 2 memories, 3 me. Nav slot 2 is
    // the send button.
    final navIndex = shell.currentIndex >= 2 ? shell.currentIndex + 1 : shell.currentIndex;
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navIndex,
        onDestinationSelected: (i) {
          if (i == 2) {
            HapticFeedback.selectionClick();
            context.push('/send');
            return;
          }
          final branch = i > 2 ? i - 1 : i;
          shell.goBranch(branch, initialLocation: branch == shell.currentIndex);
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.favorite_border_rounded),
            selectedIcon: Icon(Icons.favorite_rounded),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.wb_sunny_outlined),
            selectedIcon: Icon(Icons.wb_sunny_rounded),
            label: 'Together',
          ),
          NavigationDestination(
            icon: Container(
              width: 52,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: cc.gradient),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
            ),
            label: 'Send',
            tooltip: 'Send to their widget',
          ),
          const NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library_rounded),
            label: 'Memories',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Me',
          ),
        ],
      ),
    );
  }
}
