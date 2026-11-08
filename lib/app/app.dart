import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:closer_app/app/providers.dart';
import 'package:closer_app/app/router.dart';
import 'package:closer_app/core/services/live_sync.dart';
import 'package:closer_app/core/services/notifications.dart';
import 'package:closer_app/core/services/widget_bridge.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CloserApp extends ConsumerStatefulWidget {
  const CloserApp({super.key});

  @override
  ConsumerState<CloserApp> createState() => _CloserAppState();
}

class _CloserAppState extends ConsumerState<CloserApp> with WidgetsBindingObserver {
  final _subs = <StreamSubscription<Object?>>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_wireLinks());
  }

  /// Widget taps, notification taps and invite App Links all route through
  /// go_router (plan 5.3 step 7, section 13).
  Future<void> _wireLinks() async {
    final router = ref.read(routerProvider);
    void open(String route) {
      // Let the redirect settle first on cold start.
      Future<void>.delayed(const Duration(milliseconds: 400), () => router.push(route));
    }

    final widgetUri = await WidgetBridge.initialLaunchUri();
    if (widgetUri != null && widgetUri.scheme == 'closer') open(routeForLink(widgetUri));
    _subs.add(
      WidgetBridge.clicks.listen((uri) {
        if (uri != null && uri.scheme == 'closer') open(routeForLink(uri));
      }),
    );

    final launchRoute = NotificationService.instance.takeLaunchRoute();
    if (launchRoute != null) open(launchRoute);
    _subs.add(NotificationService.instance.taps.listen(open));

    try {
      final links = AppLinks();
      // Only invite App Links here; closer:// widget links arrive through
      // home_widget above.
      void handle(Uri uri) {
        if (uri.scheme == 'https' && uri.pathSegments.firstOrNull == 'i') {
          router.go(routeForLink(uri));
        }
      }

      final initial = await links.getInitialLink();
      if (initial != null) handle(initial);
      _subs.add(links.uriLinkStream.listen(handle));
    } on Object {
      // app_links unavailable (tests).
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Plan 5.4: on app open / resume, refresh all widgets.
    if (state == AppLifecycleState.resumed) {
      ref.read(liveSyncProvider).onChange();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(liveSyncProvider);
    final router = ref.watch(routerProvider);
    final mode = ref.watch(pairModeProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Closer',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.build(Brightness.light, mode),
      darkTheme: AppTheme.build(Brightness.dark, mode),
      themeMode: themeMode,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('de'), Locale('fr'), Locale('es')],
    );
  }
}
