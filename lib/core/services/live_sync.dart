import 'dart:async';

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/always_with_me.dart';
import 'package:closer_app/core/services/notifications.dart';
import 'package:closer_app/core/services/widget_bridge.dart';
import 'package:closer_app/core/services/widget_contract.dart';
import 'package:closer_app/features/chat/chat_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keeps the home-screen widgets and notifications in step with the
/// partner's activity while the app process is alive. (When the app is
/// closed, the FCM background handler does the same job in production.)
///
/// Watch [liveSyncProvider] once from the app root to activate it.
final liveSyncProvider = Provider<LiveSync>((ref) {
  final sync = LiveSync(ref);
  ref
    ..listen(pairProvider, (_, _) => sync.onChange(), fireImmediately: true)
    ..listen(partnerProvider, (_, _) => sync.onChange())
    ..listen(latestTapProvider, (_, _) => sync.onChange())
    ..listen(countdownsProvider, (_, _) => sync.onChange())
    ..listen(todayQuestionProvider, (_, _) => sync.onChange())
    ..listen(gamesProvider, (_, _) => sync.onChange())
    ..listen(itemsProvider, (_, _) => sync.onChange())
    ..listen(missMetersProvider, (_, _) => sync.onChange())
    ..listen(capsulesProvider, (_, _) => sync.onChange())
    ..listen(messagesProvider, (_, _) => sync.onChange())
    ..listen(goodnightsProvider, (_, _) => sync.onChange())
    ..listen(authUidProvider, (prev, next) {
      if (prev?.value != null && next.value == null) {
        unawaited(WidgetBridge.clear());
      }
    });
  // Heart badge expiry needs a redraw even without data changes.
  final timer = Timer.periodic(const Duration(minutes: 5), (_) => sync.onChange());
  ref.onDispose(timer.cancel);
  return sync;
});

class LiveSync {
  LiveSync(this._ref);

  final Ref _ref;
  Timer? _debounce;
  bool _primed = false;

  static const _kItem = 'notified_item';
  static const _kTap = 'notified_tap';
  static const _kReveal = 'notified_reveal';
  static const _kGames = 'notified_games';
  static const _kMiss = 'notified_miss';
  static const _kCapsules = 'notified_capsules';
  static const _kChat = 'notified_chat';
  static const _kGoodnight = 'notified_goodnight';

  void onChange() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _run);
  }

  Future<void> _run() async {
    final me = _ref.read(authUidProvider).value;
    final user = _ref.read(meProvider).value;
    if (me == null || user == null) return;
    final pair = _ref.read(pairProvider).value;
    if (pair == null) {
      if (user.pairId == null) await WidgetBridge.clear();
      return;
    }
    final partner = _ref.read(partnerProvider).value;
    final partnerUid = pair.partnerOf(me);
    final latest = pair.latestItemByUser[partnerUid];
    final tap = _ref.read(latestTapProvider).value;
    final partnerTap = tap != null && tap.senderId == partnerUid ? tap : null;
    final countdowns = _ref.read(countdownsProvider).value ?? const [];
    final backend = _ref.read(backendProvider);

    String? image;
    if (latest?.thumbPath != null) {
      image = await backend.resolveImage(latest!.thumbPath);
    }
    final now = DateTime.now();
    final partnerName = (pair.nicknames[me]?.isNotEmpty ?? false) ? pair.nicknames[me]! : partner?.displayName ?? '';
    final memory = AlwaysWithMe.memoryOfTheDay(
      _ref.read(itemsProvider).value ?? const [],
      partnerUid: partnerUid,
      now: now,
    );
    final memoryImage = memory == null ? null : await backend.resolveImage(memory.thumbPath);
    final heartUntil = partnerTap?.createdAt.add(const Duration(hours: 1));
    await WidgetBridge.sync(
      WidgetSnapshot(
        paired: true,
        partnerName: latest != null && latest.secret ? 'Secret admirer 🕵️' : partnerName,
        mode: pair.mode,
        latestImage: image,
        latestItemId: latest?.itemId,
        latestType: latest?.type,
        latestCaption: latest?.caption ?? '',
        latestSentAt: latest?.sentAt,
        heartUntil: heartUntil != null && heartUntil.isAfter(DateTime.now()) ? heartUntil : null,
        partnerMood: partner?.mood == null ? '' : '${partner!.mood!.emoji} ${partner.mood!.label}',
        themeId: pair.widgetTheme[me] ?? WidgetThemes.classic,
        countdown: countdowns.isEmpty ? null : countdowns.first,
        streak: pair.streak.count,
        plantStage: pair.plant.stage,
        plantHealth: pair.plant.health,
        tapEmoji: partnerTap?.info.emoji ?? '',
        lastMetAt: pair.lastMetAt,
        memoryImage: memoryImage,
        memoryId: memory?.id,
        alwaysMessage: AlwaysWithMe.message(mode: pair.mode, now: now, partnerName: partnerName, partnerTap: partnerTap),
      ),
    );

    await _notify(me, pair, partner, latest, partnerTap, image);
  }

  Future<void> _notify(
    String me,
    Pair pair,
    AppUser? partner,
    LatestItem? latest,
    Tap? partnerTap,
    String? image,
  ) async {
    final prefs = _ref.read(prefsProvider);
    final nick = pair.nicknames[me];
    final name = (nick?.isNotEmpty ?? false)
        ? nick!
        : (partner?.displayName.isNotEmpty ?? false)
            ? partner!.displayName
            : 'Your person';
    final notif = NotificationService.instance;
    final question = _ref.read(todayQuestionProvider).value;
    final games = _ref.read(gamesProvider).value ?? const <Game>[];
    final prefsN = _ref.read(meProvider).value?.notificationPrefs ?? const NotificationPrefs();

    // First run after start: remember current state without notifying, so
    // old events don't pop up again.
    if (!_primed) {
      _primed = true;
      if (prefs.getString(_kItem) == null && latest != null) {
        await prefs.setString(_kItem, latest.itemId);
      }
      if (prefs.getString(_kTap) == null && partnerTap != null) {
        await prefs.setString(_kTap, partnerTap.id);
      }
    }

    final quiet = _inQuietHours(prefsN);

    if (latest != null && prefs.getString(_kItem) != latest.itemId) {
      await prefs.setString(_kItem, latest.itemId);
      if (!quiet) {
        final what = switch (latest.type) {
          ItemType.photo => 'a photo',
          ItemType.note => 'a note',
          ItemType.doodle => 'a doodle',
          ItemType.location => 'where they are',
        };
        await notif.show(
          channel: Channels.partnerItems,
          title: latest.secret ? 'A secret admirer sent you $what 🕵️' : '$name sent you $what 💌',
          body: latest.caption.isEmpty ? 'It’s on your home screen now' : latest.caption,
          imagePath: image != null && !image.startsWith('http') ? image : null,
          route: '/reply',
          id: 1001,
        );
      }
    }

    if (partnerTap != null && prefs.getString(_kTap) != partnerTap.id) {
      await prefs.setString(_kTap, partnerTap.id);
      if (prefsN.taps && !quiet) {
        await notif.show(
          channel: Channels.taps,
          title: '$name ${partnerTap.info.message} ${partnerTap.info.emoji}',
          body: 'Tap to send one back',
          route: '/home',
          id: 1002,
        );
      }
    }

    if (question != null && question.revealed && prefs.getString(_kReveal) != question.date) {
      await prefs.setString(_kReveal, question.date);
      if (prefsN.questions && !quiet) {
        await notif.show(
          channel: Channels.dailyQuestion,
          title: 'Answers revealed! 👀',
          body: 'See what $name said to “${question.text}”',
          route: '/question',
          id: 1003,
        );
      }
    }

    final miss = _ref.read(todayMissMeterProvider);
    if (miss != null) {
      final partnerAnswered = miss.answeredBy.contains(pair.partnerOf(me));
      final state = miss.revealed ? 'revealed' : (partnerAnswered ? 'partner' : 'none');
      final key = '${miss.date}:$state';
      final worthIt = miss.revealed || (partnerAnswered && miss.myValue == null);
      if (prefs.getString(_kMiss) != key && worthIt) {
        await prefs.setString(_kMiss, key);
        if (prefsN.questions && !quiet) {
          await notif.show(
            channel: Channels.dailyQuestion,
            title: miss.revealed ? 'Miss-o-meter revealed 🥺' : 'How much do you miss $name?',
            body: miss.revealed ? 'See who misses who more' : '$name already answered. Answer to see theirs 👀',
            route: '/miss-meter',
            id: 1005,
          );
        }
      }
    }

    // Reasons, letters and surprises that just unlocked for me.
    final now = DateTime.now();
    final capsules = _ref.read(capsulesProvider).value ?? const <Capsule>[];
    final ready = capsules.where((c) => c.isNewFor(me, now)).toList();
    final seenCapsules = prefs.getStringList(_kCapsules);
    if (seenCapsules == null) {
      // First run: don't announce what was already waiting.
      await prefs.setStringList(_kCapsules, ready.map((c) => c.id).toList());
    } else {
      final seen = seenCapsules.toSet();
      final unseen = ready.where((c) => !seen.contains(c.id)).toList();
      if (unseen.isNotEmpty) {
        seen.addAll(unseen.map((c) => c.id));
        // Keep the list from growing forever.
        final keep = capsules.map((c) => c.id).toSet();
        await prefs.setStringList(_kCapsules, seen.where(keep.contains).toList());
        if (!quiet) {
          final c = unseen.first;
          final (title, body, route) = switch (c.kind) {
            CapsuleKind.reason => ('A new reason from $name 💗', 'Today’s reason is ready. Tap to read it.', '/reasons'),
            CapsuleKind.letter => (
                'A letter from $name just opened 💌',
                c.title.isEmpty ? 'Tap to read it' : '“${c.title}”',
                '/letters/${c.id}',
              ),
            CapsuleKind.surprise => ('$name sent you a surprise 🎁', 'Tap to unwrap it', '/surprises'),
          };
          await notif.show(channel: Channels.partnerItems, title: title, body: body, route: route, id: 1006);
        }
      }
    }

    // New chat messages (not while the chat is open).
    final partnerUid = pair.partnerOf(me);
    final messages = _ref.read(messagesProvider).value ?? const <ChatMessage>[];
    final lastFromPartner = messages.lastWhere(
      (m) => m.senderId == partnerUid && !m.isDeleted,
      orElse: () => ChatMessage(id: '', senderId: '', createdAt: DateTime(0)),
    );
    if (lastFromPartner.id.isNotEmpty && prefs.getString(_kChat) != lastFromPartner.id) {
      final first = prefs.getString(_kChat) == null;
      await prefs.setString(_kChat, lastFromPartner.id);
      if (!first && !ChatScreen.isOpen && prefsN.chat && !quiet) {
        await notif.show(channel: Channels.chat, title: name, body: lastFromPartner.preview, route: '/chat', id: 1007);
      }
    }

    // The partner said goodnight.
    final tonight = _ref.read(tonightProvider);
    if (tonight != null && tonight.doneBy(partnerUid) && prefs.getString(_kGoodnight) != tonight.night) {
      await prefs.setString(_kGoodnight, tonight.night);
      if (prefsN.chat && !quiet) {
        await notif.show(
          channel: Channels.chat,
          title: '$name said goodnight 🌙',
          body: tonight.doneBy(me) ? 'Sweet dreams, you two 💫' : 'Say goodnight back',
          route: '/goodnight',
          id: 1008,
        );
      }
    }

    final seenGames = (prefs.getStringList(_kGames) ?? const []).toSet();
    for (final g in games) {
      final myTurn = (g.status == GameStatus.guesserTurn && g.guesserUid == me) ||
          (g.status == GameStatus.done && g.subjectUid == me);
      final key = '${g.id}:${g.status.name}';
      if (myTurn && !seenGames.contains(key)) {
        seenGames.add(key);
        if (!quiet) {
          await notif.show(
            channel: Channels.gameTurns,
            title: g.status == GameStatus.done ? '$name finished guessing 🎯' : '$name finished — your turn!',
            body: g.status == GameStatus.done ? 'They got ${g.score}/${g.questions.length}. See results' : 'How well do you know them?',
            route: '/games/${g.id}',
            id: 1004,
          );
        }
      }
    }
    await prefs.setStringList(_kGames, seenGames.toList());
  }

  bool _inQuietHours(NotificationPrefs p) {
    final s = p.quietStart;
    final e = p.quietEnd;
    if (s == null || e == null) return false;
    final h = DateTime.now().hour;
    return s <= e ? (h >= s && h < e) : (h >= s || h < e);
  }
}
