import 'package:closer_app/app/providers.dart';
import 'package:closer_app/app/shell.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/features/chat/chat_screen.dart';
import 'package:closer_app/features/home/home_screen.dart';
import 'package:closer_app/features/insights/insights_screen.dart';
import 'package:closer_app/features/love/goodnight_screen.dart';
import 'package:closer_app/features/love/letters_screens.dart';
import 'package:closer_app/features/love/reasons_screen.dart';
import 'package:closer_app/features/love/shrine_screen.dart';
import 'package:closer_app/features/love/surprise_screens.dart';
import 'package:closer_app/features/love/timeline_screens.dart';
import 'package:closer_app/features/me/always_with_me_screen.dart';
import 'package:closer_app/features/me/me_screen.dart';
import 'package:closer_app/features/me/mood_screen.dart';
import 'package:closer_app/features/me/relationship_screen.dart';
import 'package:closer_app/features/me/settings_screens.dart';
import 'package:closer_app/features/me/widgets_screen.dart';
import 'package:closer_app/features/memories/memories_screen.dart';
import 'package:closer_app/features/onboarding/onboarding_screens.dart';
import 'package:closer_app/features/onboarding/pairing_screens.dart';
import 'package:closer_app/features/pet/pet_screen.dart';
import 'package:closer_app/features/plan/calendar_screens.dart';
import 'package:closer_app/features/plan/date_planner_screen.dart';
import 'package:closer_app/features/plan/todo_screen.dart';
import 'package:closer_app/features/plan/wishlist_screens.dart';
import 'package:closer_app/features/premium/paywall_screen.dart';
import 'package:closer_app/features/send/reply_screen.dart';
import 'package:closer_app/features/send/send_screen.dart';
import 'package:closer_app/features/together/game_screens.dart';
import 'package:closer_app/features/together/miss_meter_screen.dart';
import 'package:closer_app/features/together/plant_screen.dart';
import 'package:closer_app/features/together/question_screens.dart';
import 'package:closer_app/features/together/together_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Invite code received from a deep link before the user could accept it.
class PendingInvite extends Notifier<String?> {
  @override
  String? build() => null;

  // A setter would read oddly at call sites; keep it a method.
  // ignore: use_setters_to_change_properties
  void set(String? code) => state = code;
}

final pendingInviteProvider = NotifierProvider<PendingInvite, String?>(PendingInvite.new);

final _rootKey = GlobalKey<NavigatorState>();

const _publicRoutes = {'/welcome'};
// Routes an unpaired user with a profile may stay on (not /profile itself,
// or saving the profile would never move on).
const _setupRoutes = {'/mode', '/invite', '/code'};
const _postPairRoutes = {'/paired', '/widget-tutorial', '/notifications-permission'};

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  void bump(Object? _, Object? _) => refresh.value++;
  ref
    ..listen(authUidProvider, bump)
    ..listen(meProvider, bump)
    ..listen(onboardingFlagsProvider, bump)
    ..onDispose(refresh.dispose);

  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final auth = ref.read(authUidProvider);
      final me = ref.read(meProvider);

      // Invite links are remembered, then handled after sign-in.
      if (loc.startsWith('/i/')) {
        final code = state.pathParameters['code'];
        if (code != null) ref.read(pendingInviteProvider.notifier).set(code);
      }

      if (auth.isLoading || (auth.value != null && me.isLoading && !me.hasValue)) {
        return loc == '/splash' ? null : '/splash';
      }
      final uid = auth.value;
      final user = me.value;
      if (uid == null || user == null) {
        return _publicRoutes.contains(loc) ? null : '/welcome';
      }
      if (!user.hasProfile) return loc == '/profile' ? null : '/profile';
      if (!user.isPaired) {
        if (_setupRoutes.contains(loc)) return null;
        if (ref.read(pendingInviteProvider) != null) return '/code';
        return '/mode';
      }
      // Paired.
      final flags = ref.read(onboardingFlagsProvider);
      if (!flags.contains(OnboardingFlags.widgetTutorial)) {
        return _postPairRoutes.contains(loc) ? null : '/paired';
      }
      if (loc == '/splash' ||
          loc.startsWith('/i/') ||
          _publicRoutes.contains(loc) ||
          _setupRoutes.contains(loc) ||
          loc == '/profile') {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
      GoRoute(path: '/mode', builder: (_, _) => const ModeScreen()),
      GoRoute(path: '/invite', builder: (_, _) => const InviteScreen()),
      GoRoute(path: '/code', builder: (_, _) => const CodeScreen()),
      GoRoute(path: '/i/:code', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/paired', builder: (_, _) => const PairedScreen()),
      GoRoute(path: '/widget-tutorial', builder: (_, _) => const WidgetTutorialScreen()),
      GoRoute(path: '/notifications-permission', builder: (_, _) => const NotificationsPermissionScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/together', builder: (_, _) => const TogetherScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/memories', builder: (_, _) => const MemoriesScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/me', builder: (_, _) => const MeScreen())],
          ),
        ],
      ),
      // Full-screen routes.
      GoRoute(
        path: '/send',
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, state) => MaterialPage(
          fullscreenDialog: true,
          child: SendScreen(
            initialTab: state.uri.queryParameters['tab'],
            secret: state.uri.queryParameters['secret'] == '1',
          ),
        ),
      ),
      GoRoute(path: '/reply', parentNavigatorKey: _rootKey, builder: (_, _) => const ReplyScreen()),
      GoRoute(
        path: '/item/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => ItemViewerScreen(itemId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/paywall',
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, state) => MaterialPage(
          fullscreenDialog: true,
          child: PaywallScreen(trigger: state.uri.queryParameters['from'] ?? 'me'),
        ),
      ),
      GoRoute(path: '/question', parentNavigatorKey: _rootKey, builder: (_, _) => const QuestionScreen()),
      GoRoute(
        path: '/question/history',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const QuestionHistoryScreen(),
      ),
      GoRoute(path: '/packs', parentNavigatorKey: _rootKey, builder: (_, _) => const QuestionPacksScreen()),
      GoRoute(path: '/games', parentNavigatorKey: _rootKey, builder: (_, _) => const GamesScreen()),
      GoRoute(
        path: '/games/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => GamePlayScreen(gameId: state.pathParameters['id']!),
      ),
      // Countdowns live in the calendar now; the old paths stay for the
      // countdown widget link and notifications from older servers.
      for (final path in ['/calendar', '/countdowns'])
        GoRoute(path: path, parentNavigatorKey: _rootKey, builder: (_, _) => const CalendarScreen()),
      for (final path in ['/calendar/edit', '/countdowns/edit'])
        GoRoute(
          path: path,
          parentNavigatorKey: _rootKey,
          builder: (_, state) {
            final q = state.uri.queryParameters;
            return EventEditScreen(
              eventId: q['id'],
              initialDate: DateTime.tryParse(q['date'] ?? ''),
              category: q['category'] == null ? null : EventCategory.parse(q['category']),
              title: q['title'],
              emoji: q['emoji'],
              isVirtual: q['virtual'] == null ? null : q['virtual'] == '1',
            );
          },
        ),
      GoRoute(path: '/dates', parentNavigatorKey: _rootKey, builder: (_, _) => const DatePlannerScreen()),
      GoRoute(path: '/chat', parentNavigatorKey: _rootKey, builder: (_, _) => const ChatScreen()),
      GoRoute(path: '/pet', parentNavigatorKey: _rootKey, builder: (_, _) => const PetScreen()),
      GoRoute(path: '/insights', parentNavigatorKey: _rootKey, builder: (_, _) => const InsightsScreen()),
      GoRoute(path: '/goodnight', parentNavigatorKey: _rootKey, builder: (_, _) => const GoodnightScreen()),
      GoRoute(path: '/todos', parentNavigatorKey: _rootKey, builder: (_, _) => const TodoScreen()),
      GoRoute(path: '/wishlist', parentNavigatorKey: _rootKey, builder: (_, _) => const WishlistScreen()),
      GoRoute(
        path: '/wishlist/edit',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => WishEditScreen(
          wishId: state.uri.queryParameters['id'],
          category: state.uri.queryParameters['category'] == null
              ? null
              : WishCategory.parse(state.uri.queryParameters['category']),
        ),
      ),
      GoRoute(path: '/plant', parentNavigatorKey: _rootKey, builder: (_, _) => const PlantScreen()),
      GoRoute(path: '/miss-meter', parentNavigatorKey: _rootKey, builder: (_, _) => const MissMeterScreen()),
      GoRoute(path: '/always', parentNavigatorKey: _rootKey, builder: (_, _) => const AlwaysWithMeScreen()),
      GoRoute(path: '/reasons', parentNavigatorKey: _rootKey, builder: (_, _) => const ReasonsScreen()),
      GoRoute(path: '/letters', parentNavigatorKey: _rootKey, builder: (_, _) => const LettersScreen()),
      GoRoute(path: '/letters/write', parentNavigatorKey: _rootKey, builder: (_, _) => const WriteLetterScreen()),
      GoRoute(
        path: '/letters/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => LetterScreen(capsuleId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/surprises', parentNavigatorKey: _rootKey, builder: (_, _) => const SurprisesScreen()),
      GoRoute(
        path: '/surprises/new',
        parentNavigatorKey: _rootKey,
        builder: (_, state) =>
            NewSurpriseScreen(type: SurpriseType.parse(state.uri.queryParameters['type']) ?? SurpriseType.note),
      ),
      GoRoute(path: '/timeline', parentNavigatorKey: _rootKey, builder: (_, _) => const TimelineScreen()),
      GoRoute(
        path: '/timeline/edit',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => TimelineEditScreen(entryId: state.uri.queryParameters['id']),
      ),
      GoRoute(path: '/shrine', parentNavigatorKey: _rootKey, builder: (_, _) => const ShrineScreen()),
      GoRoute(path: '/mood', parentNavigatorKey: _rootKey, builder: (_, _) => const MoodScreen()),
      GoRoute(path: '/widgets', parentNavigatorKey: _rootKey, builder: (_, _) => const WidgetsScreen()),
      GoRoute(path: '/widget-help', parentNavigatorKey: _rootKey, builder: (_, _) => const WidgetHelpScreen()),
      GoRoute(path: '/settings', parentNavigatorKey: _rootKey, builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/relationship', parentNavigatorKey: _rootKey, builder: (_, _) => const RelationshipScreen()),
      GoRoute(path: '/privacy', parentNavigatorKey: _rootKey, builder: (_, _) => const PrivacyScreen()),
      GoRoute(path: '/help', parentNavigatorKey: _rootKey, builder: (_, _) => const HelpScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Maps `closer://` widget links and notification payloads to routes.
String routeForLink(Uri uri) {
  if (uri.scheme == 'closer') {
    return switch (uri.host) {
      'reply' => '/reply',
      'countdowns' => '/calendar',
      'plant' => '/plant',
      'always' => '/always',
      'chat' => '/chat',
      _ => '/home',
    };
  }
  if (uri.pathSegments.length >= 2 && uri.pathSegments.first == 'i') {
    return '/i/${uri.pathSegments[1]}';
  }
  return '/home';
}
