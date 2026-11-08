import 'package:closer_app/core/models/models.dart';

/// Free-tier limits (plan section 2). Plus removes them. Real enforcement is
/// on the server; the app mirrors them for counters and paywall triggers.
abstract final class FreeLimits {
  static const sendsPerDay = 10;
  static const rewardedExtraSends = 3;
  static const countdowns = 3;
  static const memoriesDays = 30;
  static const tapCooldown = Duration(seconds: 10);
}

/// The single seam between the Flutter app and its backend.
///
/// Two implementations exist:
/// * `LocalBackend` — everything on device (plus a simulated partner) so the
///   app runs without any cloud setup.
/// * `FirebaseBackend` — Firestore/Storage/Functions/FCM as described in the
///   plan. Enabled with `--dart-define=CLOSER_BACKEND=firebase`.
///
/// Every stream emits the current value on listen and then each change.
abstract class CloserBackend {
  /// Short id shown in debug screens ("local" / "firebase").
  String get name;

  /// Whether this backend simulates the partner on device.
  bool get isSimulated;

  Future<void> init();

  // ---------------------------------------------------------------- auth
  /// Current uid, or null when signed out.
  Stream<String?> authState();
  String? get currentUid;

  /// Google sign-in on Firebase; creates a local account on LocalBackend.
  Future<void> signInWithGoogle();
  Future<void> signOut();

  // --------------------------------------------------------------- users
  Stream<AppUser?> watchUser(String uid);
  Future<void> updateProfile({String? displayName, String? photoFilePath});
  /// Onboarding choice before pairing: couple / best friends and, optionally,
  /// what the other person is to you ([RelationLabel] id).
  Future<void> setPendingMode(PairMode mode, {String? label});
  Future<void> updateMood(Mood mood);
  Future<void> updateStatus(StatusText status);
  Future<void> setAgeConfirmed({required bool confirmed});
  Future<void> updateNotificationPrefs(NotificationPrefs prefs);

  // ------------------------------------------------------------- pairing
  Future<Invite> createInvite(PairMode mode);

  /// Throws [CloserException] for expired / used / own / unknown codes.
  Future<void> acceptInvite(String code);
  Future<void> unpair();
  Future<void> deleteAccount();

  /// Exports memories; returns a local file path or a download URL.
  Future<String> exportMemories();

  Stream<Pair?> watchPair(String pairId);

  /// Relationship settings. [mode] and [anniversary] are shared by both
  /// members; [label] (what you call your partner) and [nickname] are yours.
  /// Pass an empty [nickname] to clear it, [clearAnniversary] to remove the
  /// date. Changing [mode] drops labels that don't fit the new mode.
  Future<void> updateRelationship({
    PairMode? mode,
    DateTime? anniversary,
    bool clearAnniversary = false,
    String? label,
    String? nickname,
  });

  // --------------------------------------------------------------- items
  /// Throws [LimitReachedException] ('sends') when the free limit is hit.
  Future<Item> sendItem(SendRequest request);
  Stream<List<Item>> watchItems(String pairId, {int limit = 200});
  Stream<int> watchSendsToday();

  /// Grants +3 sends today after a rewarded ad (server-verified in prod).
  Future<void> grantRewardedSends();

  /// Resolves an item image reference (storage path / local path) to
  /// something an image widget can show: an absolute file path or a URL.
  Future<String?> resolveImage(String? ref);

  // ---------------------------------------------------------------- taps
  /// Rate limited to one per [FreeLimits.tapCooldown].
  Future<void> sendTap({String kind = 'heart'});
  Stream<Tap?> watchLatestTap(String pairId);

  // ----------------------------------------------------- daily question
  Stream<DailyQuestion?> watchTodayQuestion(String pairId);
  Stream<List<DailyQuestion>> watchPastQuestions(String pairId);
  Future<void> submitAnswer(String text);
  Future<void> setQuestionPack(String packId);

  // ----------------------------------------------------------- countdowns
  Stream<List<Countdown>> watchCountdowns(String pairId);

  /// Throws [LimitReachedException] ('countdowns') above the free limit.
  Future<void> saveCountdown(Countdown countdown);
  Future<void> deleteCountdown(String id);

  // ---------------------------------------------------------------- games
  Stream<List<Game>> watchGames(String pairId);
  Future<Game> startGame({String packId = 'starter'});
  Future<void> submitGameAnswers(String gameId, List<int> answers);

  // --------------------------------------------------- themes & premium
  Future<void> setWidgetTheme(String themeId);

  /// Local backend only: toggles Plus for the pair. In production premium is
  /// written by the RevenueCat webhook.
  Future<void> debugSetPremium({required bool active});

  /// FCM / device registration (no-op locally).
  Future<void> registerDevice();
}
