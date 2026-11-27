// End-to-end walk through every feature on a real device, with the
// on-device backend and its simulated partner (fast timers).
//
//   SHOT_DIR=build/screenshots flutter drive -d <device> \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/features_test.dart
//
// Every Flutter error (exceptions, layout overflows) and every
// "Something went wrong" toast is collected and reported at the end.

import 'dart:io';

import 'package:closer_app/app/app.dart';
import 'package:closer_app/app/providers.dart';
import 'package:closer_app/app/router.dart';
import 'package:closer_app/core/data/local/local_backend.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/note_renderer.dart';
import 'package:closer_app/core/services/notifications.dart';
import 'package:closer_app/core/ui/reactions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('walk through every feature', (tester) async {
    final errors = <String>[];
    // The app logs swallowed failures ("Action failed: …") with debugPrint.
    final originalPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null && RegExp('Action failed|failed:|Error:', caseSensitive: false).hasMatch(message)) {
        errors.add('[$_step] log: $message');
      }
      originalPrint(message, wrapWidth: wrapWidth);
    };

    // ------------------------------------------------------------- setup
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await prefs.setStringList('onboarding_flags', ['widget_tutorial', 'notifications', 'age_asked', 'review_asked']);
    final backend = LocalBackend(
      simulatorScale: const Duration(milliseconds: 40),
      dbFileName: 'it_${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await backend.init();
    await NotificationService.instance.init();
    await backend.signInWithGoogle();
    await backend.updateProfile(displayName: 'Tess');
    await backend.setPendingMode(PairMode.couple);
    await backend.acceptInvite('TEST01');
    final pairId = backend.myPairId!;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [backendProvider.overrideWithValue(backend), prefsProvider.overrideWithValue(prefs)],
        child: const CloserApp(),
      ),
    );
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
    final container = ProviderScope.containerOf(tester.element(find.byType(CloserApp)));
    final router = container.read(routerProvider);

    // Widget errors and uncaught async errors land in takeException().
    void collect() {
      final e = tester.takeException();
      if (e != null) errors.add('[$_step] $e');
    }

    Future<void> wait([int ms = 1200]) async {
      for (var i = 0; i < ms ~/ 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        collect();
      }
    }

    void checkToasts() {
      for (final bad in ['Something went wrong', 'Couldn’t', 'failed']) {
        if (find.textContaining(bad).evaluate().isNotEmpty) {
          errors.add('[$_step] error toast: ${(find.textContaining(bad).evaluate().first.widget as Text).data}');
        }
      }
    }

    var shotN = 0;
    Future<void> shot(String name) async {
      await wait(600);
      checkToasts();
      shotN++;
      await binding.takeScreenshot('${shotN.toString().padLeft(2, '0')}_$name');
    }

    Future<void> go(String route) async {
      _step = route;
      router.push(route).ignore();
      await wait(1500);
    }

    Future<void> back() async {
      router.pop();
      await wait(700);
    }

    Future<void> tap(Finder f, {String? what}) async {
      // Lazily built lists: scroll down until the target exists.
      final vertical = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
      if (f.evaluate().isEmpty && vertical.evaluate().isNotEmpty) {
        try {
          await tester.scrollUntilVisible(f, 300, scrollable: vertical.first, maxScrolls: 15);
        } on Object {
          // Reported as "not found" below.
        }
      }
      if (f.evaluate().isEmpty) {
        errors.add('[$_step] not found: ${what ?? f.describeMatch(Plurality.zero)}');
        return;
      }
      await tester.ensureVisible(f.first);
      await wait(300);
      await tester.tap(f.first, warnIfMissed: false);
      await wait();
    }

    Future<void> type(Finder f, String text) async {
      if (f.evaluate().isEmpty) {
        errors.add('[$_step] text field not found for "$text"');
        return;
      }
      await tester.ensureVisible(f.first);
      await tester.enterText(f.first, text);
      await wait(400);
    }

    Future<String> notePng(String text) async {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/it_${DateTime.now().microsecondsSinceEpoch}.png';
      await NoteRenderer.renderToFile(text: text, style: const NoteStyle(bg: 'blush', font: 'rounded'), path: path);
      return path;
    }

    // Let the simulated partner pair up and seed its data.
    _step = 'home';
    await wait(4000);
    await shot('home');

    // ------------------------------------------------ Phase 1: quick wins
    _step = 'one-tap message';
    await tap(find.textContaining('Miss you'), what: 'Miss you chip');
    await wait(1500);
    await shot('home_after_tap');

    _step = 'secret admirer';
    final secret = await backend.sendItem(
      SendRequest(
        type: ItemType.note,
        imagePath: await notePng('From your secret admirer 👀'),
        text: 'From your secret admirer 👀',
        noteStyle: const NoteStyle(bg: 'blush', font: 'rounded'),
        secret: true,
      ),
    );
    await go('/item/${secret.id}');
    await tap(find.descendant(of: find.byType(ReactionBar), matching: find.text('❤️')), what: 'reaction ❤️');
    await tap(find.textContaining('Reveal it was you'), what: 'reveal button');
    await tap(find.text('Reveal'), what: 'confirm reveal');
    await shot('item_viewer_reactions_reveal');
    await back();

    await go('/send?tab=note&secret=1');
    await shot('send_secret_toggle');
    await back();

    await go('/miss-meter');
    await shot('miss_meter_picker');
    await tap(find.text('Lock in my answer'));
    await wait(2500);
    await shot('miss_meter_reveal');
    await back();

    await go('/always');
    await tap(find.textContaining('together right now'), what: 'we met button');
    await shot('always_with_me');
    await back();

    // ------------------------------------------------ Together tab
    _step = 'together';
    router.go('/together');
    await wait(1500);
    await shot('together_play');
    await tap(find.text('Love'));
    await shot('together_love');
    await tap(find.text('Plan'));
    await shot('together_plan');

    // ------------------------------------------------ Phase 2: love
    await go('/reasons');
    await shot('reasons_for_me');
    await tap(find.textContaining('Tap to open it'), what: 'open reason');
    await wait();
    await shot('reasons_opened');
    await tap(find.text('Written by you'));
    await tap(find.text('Add a reason'), what: 'add reason');
    await type(find.byType(TextField), 'You make every day brighter');
    await tap(find.text('Add reason'));
    await shot('reasons_by_me');
    await back();

    // Partner's letter unlocks ~7 s after pairing (180 × 40 ms).
    await wait(3000);
    await go('/letters');
    await shot('letters');
    await tap(find.text('Open when you miss me'), what: 'partner letter');
    await tap(find.text('Open the letter'), what: 'open letter button');
    await wait(1500);
    await shot('letter_open');
    await back();
    await go('/letters/write');
    await type(find.byType(TextField).at(1), 'Dear Sam,\n\nSee you soon!');
    await tap(find.text('In a week'));
    await tap(find.text('Seal the letter'));
    await wait(1000);
    await shot('letters_after_write');
    await back();

    await go('/surprises');
    await shot('surprises');
    await tap(find.text('Tap to unwrap'), what: 'surprise card');
    await tap(find.text('Tap to unwrap'), what: 'gift box');
    await wait(1500);
    await shot('surprise_unwrapped');
    // Held on screen so a host-side `adb screencap` can compare the real frame.
    await wait(6000);
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await wait(700);
    await back();
    await go('/surprises/new?type=compliment');
    await tap(find.textContaining('Your laugh is my favourite sound'));
    await tap(find.text('Send the surprise'));
    await wait(1000);

    await go('/timeline/edit');
    await tap(find.textContaining('Our first date'));
    await tap(find.text('Add to our timeline'));
    await go('/timeline');
    await shot('timeline');
    await back();

    await go('/shrine');
    await shot('shrine_from_partner');
    await backend.saveShrine(
      const Shrine(
        ownerUid: '',
        title: 'For Sam, with love',
        theme: 'sunset',
        favorites: [ShrineFavorite('Song', 'Our song'), ShrineFavorite('Food', 'Ramen')],
        messages: ['You are my favourite person'],
      ),
    );
    await tap(find.textContaining('For '), what: 'my shrine tab');
    await shot('shrine_mine');
    await back();

    // ------------------------------------------------ Phase 3: planning
    await go('/calendar');
    await shot('calendar');
    await go('/calendar/edit');
    await tap(find.text('Date'));
    await type(find.byType(TextField).first, 'Dinner at Luigi’s');
    await tap(find.text('Add to our calendar'));
    await wait(1000);
    await shot('calendar_after_add');
    await back();

    final now = DateTime.now();
    await backend.saveCountdown(
      Countdown(
        id: '',
        title: 'Picnic',
        date: now.subtract(const Duration(days: 1)),
        category: EventCategory.date,
        showAsCountdown: false,
        createdBy: '',
      ),
    );
    await go('/dates');
    await tap(find.text('Set a date-night goal'), what: 'goal card');
    await tap(find.text('Save goal'));
    await tap(find.byIcon(Icons.favorite_border_rounded), what: 'rate heart');
    await shot('date_planner');
    await back();

    await go('/todos');
    await tap(find.byType(Checkbox), what: 'todo checkbox');
    await tap(find.text('Add a task'));
    await type(find.byType(TextField).last, 'Buy flowers');
    await tap(find.text('Add task'));
    await shot('todos');
    await back();

    await go('/wishlist');
    await shot('wishlist_together');
    await tap(find.text('Gifts'));
    await tap(find.textContaining('get this'), what: 'claim gift');
    await shot('wishlist_gifts');
    await back();
    await go('/wishlist/edit?category=restaurant');
    await type(find.byType(TextField).first, 'Sushi place downtown');
    await tap(find.text('Add to wishlist'));
    await back();

    // ------------------------------------------------ Phase 4: chat & goodnight
    await go('/chat');
    await type(find.byType(TextField), 'Hello from the test 👋');
    await tap(find.byTooltip('Send'));
    await backend.sendMessage(ChatDraft(type: MessageType.photo, localPath: await notePng('A photo!'), text: 'Look!'));
    await wait(2500);
    await shot('chat');
    await tester.longPress(find.text('Hello from the test 👋'));
    await wait(800);
    await tap(find.text('😂'), what: 'chat reaction');
    await shot('chat_reacted');
    await back();

    await go('/goodnight');
    await type(find.byType(TextField).first, 'Sweet dreams!');
    await type(find.byType(TextField).at(1), 'Our walk in the park');
    await tap(find.text('Add a goodnight kiss'));
    await tap(find.text('Say goodnight'));
    await wait(2000);
    await shot('goodnight');
    await back();

    // ------------------------------------------------ Phase 5: pet & insights
    _step = 'pet';
    backend.pairDoc(pairId)!['plant'] = {'stage': 5, 'health': 'healthy', 'species': 'sprout'};
    backend.commit();
    await go('/pet');
    await shot('pet_egg');
    await tap(find.text('Hatch the egg'));
    await tap(find.text('Fox'));
    await type(find.byType(TextField).last, 'Ziggy');
    await tap(find.text('Hatch!'));
    await wait(2000);
    await tap(find.text('Feed'));
    await shot('pet_home');
    await tap(find.text('Decorate the home'));
    await tap(find.text('Cozy rug'), what: 'buy rug');
    await tap(find.text('Heart box'), what: 'reward decor');
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await wait(800);
    await shot('pet_decorated');
    await back();

    await backend.updateMood(Mood(emoji: '🥰', label: 'Loved', updatedAt: DateTime.now()));
    await go('/insights');
    await shot('insights_top');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
    await wait(800);
    await shot('insights_middle');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -1200));
    await wait(800);
    await shot('insights_bottom');
    await back();

    await go('/settings');
    await shot('settings');
    await back();
    await go('/widgets');
    await shot('widgets');
    await back();

    // ------------------------------------------------ report
    _step = 'done';
    collect();
    debugPrint = originalPrint;
    backend.dispose();
    if (errors.isNotEmpty) {
      // Printed so the problem list shows up in the test log.
      // ignore: avoid_print
      print('==== ${errors.length} problem(s) ====\n${errors.join('\n\n')}');
    }
    expect(errors, isEmpty);
  });
}

String _step = 'setup';
