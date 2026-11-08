import 'package:closer_app/core/config.dart';
import 'package:closer_app/core/data/closer_backend.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Overridden in main() with the configured backend.
final backendProvider = Provider<CloserBackend>(
  (ref) => throw UnimplementedError('backendProvider must be overridden'),
);

/// Overridden in main() with the loaded instance.
final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('prefsProvider must be overridden'),
);

final authUidProvider = StreamProvider<String?>(
  (ref) => ref.watch(backendProvider).authState(),
);

final meProvider = StreamProvider<AppUser?>((ref) {
  final uid = ref.watch(authUidProvider).value;
  if (uid == null) return Stream.value(null);
  return ref.watch(backendProvider).watchUser(uid);
});

final pairIdProvider = Provider<String?>(
  (ref) => ref.watch(meProvider).value?.pairId,
);

final pairProvider = StreamProvider<Pair?>((ref) {
  final id = ref.watch(pairIdProvider);
  if (id == null) return Stream.value(null);
  return ref.watch(backendProvider).watchPair(id);
});

final partnerUidProvider = Provider<String?>((ref) {
  final me = ref.watch(authUidProvider).value;
  final pair = ref.watch(pairProvider).value;
  if (me == null || pair == null) return null;
  final p = pair.partnerOf(me);
  return p.isEmpty ? null : p;
});

final partnerProvider = StreamProvider<AppUser?>((ref) {
  final uid = ref.watch(partnerUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(backendProvider).watchUser(uid);
});

/// How the partner is shown in the app: the nickname you gave them in
/// relationship settings, else their own name, else a friendly fallback.
final partnerNameProvider = Provider<String>((ref) {
  final me = ref.watch(authUidProvider).value;
  final nick = me == null ? null : ref.watch(pairProvider).value?.nicknames[me];
  if (nick != null && nick.isNotEmpty) return nick;
  final n = ref.watch(partnerProvider).value?.displayName ?? '';
  return n.isEmpty ? 'your person' : n;
});

/// What you call your partner ("Girlfriend", "Best friend"), if chosen.
final myLabelForPartnerProvider = Provider<RelationLabel?>((ref) {
  final me = ref.watch(authUidProvider).value;
  final pair = ref.watch(pairProvider).value;
  return me == null ? null : pair?.labelBy(me);
});

/// What your partner calls you, if they chose it.
final partnerLabelForMeProvider = Provider<RelationLabel?>((ref) {
  final partner = ref.watch(partnerUidProvider);
  final pair = ref.watch(pairProvider).value;
  return partner == null ? null : pair?.labelBy(partner);
});

final pairModeProvider = Provider<PairMode>((ref) {
  return ref.watch(pairProvider).value?.mode ??
      ref.watch(meProvider).value?.pendingMode ??
      PairMode.couple;
});

/// Plus is checked on the **pair** so one subscription covers both partners.
/// With monetization switched off everything counts as unlocked.
final isPlusProvider = Provider<bool>((ref) {
  if (!AppConfig.monetizationEnabled) return true;
  final premium = ref.watch(pairProvider).value?.premium;
  if (premium == null || !premium.active) return false;
  final exp = premium.expiresAt;
  return exp == null || exp.isAfter(DateTime.now());
});

final itemsProvider = StreamProvider<List<Item>>((ref) {
  final id = ref.watch(pairIdProvider);
  if (id == null) return Stream.value(const []);
  return ref.watch(backendProvider).watchItems(id);
});

final sendsTodayProvider = StreamProvider<int>(
  (ref) {
    ref.watch(authUidProvider);
    return ref.watch(backendProvider).watchSendsToday();
  },
);

final sendsLeftProvider = Provider<int?>((ref) {
  if (ref.watch(isPlusProvider)) return null; // unlimited
  final used = ref.watch(sendsTodayProvider).value ?? 0;
  return (FreeLimits.sendsPerDay - used).clamp(0, 999);
});

final latestTapProvider = StreamProvider<Tap?>((ref) {
  final id = ref.watch(pairIdProvider);
  if (id == null) return Stream.value(null);
  return ref.watch(backendProvider).watchLatestTap(id);
});

final todayQuestionProvider = StreamProvider<DailyQuestion?>((ref) {
  final id = ref.watch(pairIdProvider);
  if (id == null) return Stream.value(null);
  return ref.watch(backendProvider).watchTodayQuestion(id);
});

final pastQuestionsProvider = StreamProvider<List<DailyQuestion>>((ref) {
  final id = ref.watch(pairIdProvider);
  if (id == null) return Stream.value(const []);
  return ref.watch(backendProvider).watchPastQuestions(id);
});

final countdownsProvider = StreamProvider<List<Countdown>>((ref) {
  final id = ref.watch(pairIdProvider);
  if (id == null) return Stream.value(const []);
  return ref.watch(backendProvider).watchCountdowns(id);
});

final gamesProvider = StreamProvider<List<Game>>((ref) {
  final id = ref.watch(pairIdProvider);
  if (id == null) return Stream.value(const []);
  return ref.watch(backendProvider).watchGames(id);
});

/// Resolves an image reference (local path or storage path) for display.
final imageUrlProvider = FutureProvider.family<String?, String?>(
  (ref, refPath) => ref.watch(backendProvider).resolveImage(refPath),
);

// ------------------------------------------------------------- settings

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    final v = ref.watch(prefsProvider).getString(_key);
    return ThemeMode.values.firstWhere((m) => m.name == v, orElse: () => ThemeMode.system);
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(prefsProvider).setString(_key, mode.name);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// Small persisted onboarding flags.
class OnboardingFlags extends Notifier<Set<String>> {
  static const _key = 'onboarding_flags';
  static const widgetTutorial = 'widget_tutorial';
  static const notifications = 'notifications';
  static const ageAsked = 'age_asked';
  static const reviewAsked = 'review_asked';

  @override
  Set<String> build() =>
      (ref.watch(prefsProvider).getStringList(_key) ?? const []).toSet();

  Future<void> mark(String flag) async {
    state = {...state, flag};
    await ref.read(prefsProvider).setStringList(_key, state.toList());
  }

  Future<void> clear() async {
    state = {};
    await ref.read(prefsProvider).remove(_key);
  }
}

final onboardingFlagsProvider =
    NotifierProvider<OnboardingFlags, Set<String>>(OnboardingFlags.new);
