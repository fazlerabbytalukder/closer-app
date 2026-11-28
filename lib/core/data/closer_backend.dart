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
///   plan. The default; `--dart-define=CLOSER_BACKEND=local` picks the demo.
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

  /// "We met today": when the two last saw each other (not in the future).
  Future<void> setLastMet(DateTime when);

  // --------------------------------------------------------------- items
  /// Throws [LimitReachedException] ('sends') when the free limit is hit, and
  /// [SendQueuedException] when it was saved to send once back online.
  Future<Item> sendItem(SendRequest request);

  /// Sends waiting for a connection (see [SendQueuedException]).
  Stream<int> watchQueuedSends();
  Stream<List<Item>> watchItems(String pairId, {int limit = 200});
  Stream<int> watchSendsToday();

  /// Grants +3 sends today after a rewarded ad (server-verified in prod).
  Future<void> grantRewardedSends();

  /// Resolves an item image reference (storage path / local path) to
  /// something an image widget can show: an absolute file path or a URL.
  Future<String?> resolveImage(String? ref);

  /// Sets (or with null, removes) the caller's reaction on an item.
  Future<void> reactToItem(String itemId, String? emoji);

  /// Reveals the sender of the caller's own secret-admirer item.
  Future<void> revealSecret(String itemId);

  // ---------------------------------------------------------------- taps
  /// Rate limited to one per [FreeLimits.tapCooldown]. [kind] is a
  /// [TapKind] id.
  Future<void> sendTap({String kind = 'heart'});
  Stream<Tap?> watchLatestTap(String pairId);

  // -------------------------------------------------------- miss meter
  /// Recent days, newest first, with the caller's private value merged in.
  Stream<List<MissMeter>> watchMissMeters(String pairId);

  /// Saves today's 0..[MissMeter.max] value; reveals when both answered.
  Future<void> submitMissMeter(int value);

  // ----------------------------------------------------- daily question
  Stream<DailyQuestion?> watchTodayQuestion(String pairId);
  Stream<List<DailyQuestion>> watchPastQuestions(String pairId);
  Future<void> submitAnswer(String text);
  Future<void> setQuestionPack(String packId);

  // ------------------------------------------------- calendar / countdowns
  /// Every calendar event, past and future, sorted by date. Countdowns are
  /// events with `showAsCountdown`.
  Stream<List<Countdown>> watchCountdowns(String pairId);

  /// Creates or updates a calendar event. Throws [LimitReachedException]
  /// ('countdowns') when a free pair adds a 4th countdown.
  Future<void> saveCountdown(Countdown countdown);
  Future<void> deleteCountdown(String id);

  /// Date planner: rate a date 1..5 (marks it done for both).
  Future<void> rateDate(String eventId, int hearts);

  /// Shared date goal; null removes it.
  Future<void> setDateGoal(DateGoal? goal);

  // --------------------------------------------------------------- to-dos
  Stream<List<TodoList>> watchTodoLists(String pairId);

  /// Returns the list id.
  Future<String> saveTodoList(TodoList list);

  /// Deletes the list and its tasks.
  Future<void> deleteTodoList(String id);
  Stream<List<Todo>> watchTodos(String pairId);
  Future<void> saveTodo(Todo todo);
  Future<void> setTodoDone(String id, {required bool done});
  Future<void> deleteTodo(String id);

  // ------------------------------------------------------------- wishlist
  Stream<List<Wish>> watchWishes(String pairId);
  Future<void> saveWish(Wish wish);
  Future<void> deleteWish(String id);
  Future<void> setWishDone(String id, {required bool done});

  /// Ids of the partner's gift wishes the caller has secretly claimed.
  Stream<Set<String>> watchMyWishClaims(String pairId);
  Future<void> claimWish(String wishId, {required bool claim});

  // -------------------------------------------------------------- media
  /// Compresses and stores a picked photo for capsules, the timeline or the
  /// shrine. Returns a reference for [resolveImage].
  Future<String> uploadPhoto(String localPath);

  // ------------------------------------------------- capsules (sealed love)
  /// Every envelope in the pair (reasons, letters, surprises), newest first.
  Stream<List<Capsule>> watchCapsules(String pairId);

  /// Writes the envelope and its locked content. The envelope's id may be empty.
  Future<void> sendCapsule(Capsule envelope, CapsuleContent content);

  /// Reads the content. Throws [CloserException] while it is still locked.
  Future<CapsuleContent> openCapsule(Capsule capsule);

  /// Receiver only: marks an unlocked capsule as opened.
  Future<void> markCapsuleOpened(String capsuleId);

  /// Author only.
  Future<void> deleteCapsule(String capsuleId);

  // ------------------------------------------------------------ timeline
  /// Stored moments, oldest first (auto moments are added by the UI).
  Stream<List<TimelineEntry>> watchTimeline(String pairId);
  Future<void> saveTimelineEntry(TimelineEntry entry);
  Future<void> deleteTimelineEntry(String id);

  // -------------------------------------------------------------- shrine
  /// ownerUid → shrine (at most one per member).
  Stream<Map<String, Shrine>> watchShrines(String pairId);

  /// Saves the caller's own shrine.
  Future<void> saveShrine(Shrine shrine);

  // ----------------------------------------------------------------- chat
  /// Newest last, at most [limit] of the most recent messages.
  Stream<List<ChatMessage>> watchMessages(String pairId, {int limit = 300});

  /// Uploads the photo / voice file (if any) and sends the message.
  Future<void> sendMessage(ChatDraft draft);
  Future<void> reactToMessage(String messageId, String? emoji);

  /// Sender only: replaces the message with "Deleted message".
  Future<void> deleteMessage(String messageId);

  /// Partner only: counts one opening of a snap. When it's used up the
  /// photo is deleted (by a function on Firebase).
  Future<void> openSnap(String messageId);

  /// Posts a system line: "📸 took a screenshot" / "⬇️ saved a photo".
  Future<void> sendChatEvent(ChatEvent event, {ReplyRef? about, ChatTtl? ttl});

  /// Disappearing messages for new messages; posts a line in the chat.
  Future<void> setChatTtl(ChatTtl ttl);

  /// "After viewing" messages: call when leaving the chat. Deletes the
  /// partner's "after viewing" messages sent before now (you've seen them).
  Future<void> clearViewedMessages();

  /// uid → read / typing state.
  Stream<Map<String, ChatState>> watchChatState(String pairId);
  Future<void> markChatRead();

  /// Call while typing (throttled by the caller); false clears it.
  Future<void> setTyping({required bool typing});

  /// Stores a recorded voice file; returns a ref for [resolveImage]
  /// (which resolves any media ref, audio included).
  Future<String> uploadAudio(String localPath);

  // ------------------------------------------------------------ goodnight
  /// Recent nights, newest first.
  Stream<List<Goodnight>> watchGoodnights(String pairId);

  /// Saves the caller's entry for tonight (see [Goodnight.keyFor]).
  /// Media paths in [entry] are local files; the backend uploads them.
  Future<void> sendGoodnight(GoodnightEntry entry);

  // ------------------------------------------------------------ pet & home
  /// Hatches the pet from the plant (plant stage ≥ [Pet.hatchStage]) or
  /// renames it.
  Future<void> savePet(Pet pet);

  /// 'feed' or 'play' — records that the caller cared for the pet today.
  Future<void> careForPet(String action);

  /// Buys (adds to owned and to spent), places or moves decorations and
  /// sets the wallpaper.
  Future<void> saveHome(PetHome home);

  // -------------------------------------------------------------- insights
  /// Daily moods of both members (from `updateMood`), newest first.
  Stream<List<MoodEntry>> watchMoodLog(String pairId);

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

/// Checks a capsule before it is written (both backends; Firestore rules
/// enforce the same limits). Throws [CloserException].
void checkCapsule(Capsule env, CapsuleContent content, {required int reasonsWritten}) {
  final text = content.text.trim();
  switch (env.kind) {
    case CapsuleKind.reason:
      if (text.isEmpty) throw const CloserException('Write your reason first');
      if (text.length > CapsuleContent.maxReason) {
        throw const CloserException('Keep it under ${CapsuleContent.maxReason} characters');
      }
      if (reasonsWritten >= Capsule.maxReasons) {
        throw const CloserException('You’ve written all 100 reasons 💗');
      }
    case CapsuleKind.letter:
      if (text.isEmpty) throw const CloserException('Write your letter first');
    case CapsuleKind.surprise:
      final type = env.surpriseType;
      if (type == null) throw const CloserException('Pick a kind of surprise');
      if (type == SurpriseType.gift && VirtualGift.byId(content.giftId) == null) {
        throw const CloserException('Pick a gift');
      }
      if (type == SurpriseType.photo && content.photoPath == null) throw const CloserException('Pick a photo');
      if ((type == SurpriseType.note || type == SurpriseType.compliment) && text.isEmpty) {
        throw const CloserException('Write something sweet first');
      }
  }
  if (text.length > CapsuleContent.maxText) throw const CloserException('That’s a bit too long');
  if (env.title.length > Capsule.maxTitle) throw const CloserException('Keep the title short');
}

void checkTimelineEntry(TimelineEntry e) {
  if (e.title.trim().isEmpty) throw const CloserException('Give this moment a title');
  if (e.title.length > TimelineEntry.maxTitle) throw const CloserException('Keep the title short');
  if (e.note.length > TimelineEntry.maxNote) throw const CloserException('That note is a bit long');
}

/// Trims a shrine to its limits before saving.
Shrine clampShrine(Shrine s) {
  String clip(String v, int max) => v.length <= max ? v : v.substring(0, max);
  return Shrine(
    ownerUid: s.ownerUid,
    title: clip(s.title.trim(), Shrine.maxTitle),
    theme: Shrine.themes.contains(s.theme) ? s.theme : Shrine.themes.first,
    coverPath: s.coverPath,
    photos: s.photos.take(Shrine.maxPhotos).toList(),
    favorites: [
      for (final f in s.favorites.take(Shrine.maxFavorites))
        ShrineFavorite(clip(f.label.trim(), 40), clip(f.value.trim(), Shrine.maxText)),
    ],
    messages: [for (final m in s.messages.take(Shrine.maxMessages)) clip(m.trim(), Shrine.maxText)],
    pinnedItemIds: s.pinnedItemIds.take(Shrine.maxPinned).toList(),
  );
}

void checkEvent(Countdown e) {
  if (e.title.trim().isEmpty) throw const CloserException('Give it a name');
  if (e.title.length > Countdown.maxTitle) throw const CloserException('Keep the name short');
  if (e.note.length > Countdown.maxNote) throw const CloserException('That note is a bit long');
  if (e.place.length > Countdown.maxPlace) throw const CloserException('That place is a bit long');
  final end = e.endDate;
  if (end != null && DateTime(end.year, end.month, end.day).isBefore(DateTime(e.date.year, e.date.month, e.date.day))) {
    throw const CloserException('It can’t end before it starts');
  }
}

void checkTodo(Todo t) {
  if (t.text.trim().isEmpty) throw const CloserException('Write the task first');
  if (t.text.length > Todo.maxText) throw const CloserException('Keep the task short');
}

void checkWish(Wish w) {
  if (w.title.trim().isEmpty) throw const CloserException('What is it?');
  if (w.title.length > Wish.maxTitle) throw const CloserException('Keep the name short');
  if (w.note.length > Wish.maxNote) throw const CloserException('That note is a bit long');
  if (w.url.length > Wish.maxUrl) throw const CloserException('That link is too long');
  if (w.price.length > Wish.maxPrice) throw const CloserException('Keep the price short');
}

void checkMessage(ChatDraft d) {
  switch (d.type) {
    case MessageType.text:
      if (d.text.trim().isEmpty) throw const CloserException('Write a message first');
    case MessageType.photo:
      if (d.localPath == null) throw const CloserException('Pick a photo');
    case MessageType.snap:
      if (d.localPath == null) throw const CloserException('Take a snap first');
      if (d.viewLimit < 1 || d.viewLimit > ChatMessage.maxSnapViews) {
        throw const CloserException('A snap opens once or twice');
      }
    case MessageType.event:
      if (d.event == null) throw const CloserException('Unknown event');
      if (d.event == ChatEvent.ttl && ChatTtl.tryParse(d.text) == null) throw const CloserException('Unknown setting');
    case MessageType.voice:
      if (d.localPath == null || d.durationMs < 500) throw const CloserException('That voice message was too short');
      if (d.durationMs > ChatMessage.maxVoiceMs) throw const CloserException('Voice messages can be up to 5 minutes');
  }
  if (d.text.length > ChatMessage.maxText) throw const CloserException('That message is too long');
}

void checkGoodnight(GoodnightEntry e) {
  if (e.isEmpty) throw const CloserException('Say goodnight first 🌙');
  if (e.message.length > GoodnightEntry.maxText || e.moment.length > GoodnightEntry.maxText) {
    throw const CloserException('That’s a bit long for a goodnight');
  }
  if (e.voiceMs > ChatMessage.maxVoiceMs) throw const CloserException('Voice notes can be up to 5 minutes');
}

/// Checks a home update against the previous one: love points are only
/// spent (never refunded) and you can't spend more than you've earned.
void checkHome(PetHome before, PetHome after, Pair pair) {
  if (after.spent < before.spent) throw const CloserException('Love points can’t be refunded');
  if (after.spent > pair.lovePointsEarned) throw const CloserException('Not enough love points yet 💗');
  if (after.placed.length > PetHome.maxPlaced) throw const CloserException('The room is full!');
}

void checkPet(Pet pet, Pair pair) {
  if (pair.plant.stage < Pet.hatchStage && pair.pet == null) {
    throw const CloserException('Your plant hasn’t grown an egg yet');
  }
  if (pet.name.trim().isEmpty) throw const CloserException('Give your pet a name');
  if (pet.name.length > Pet.maxName) throw const CloserException('That name is a bit long');
}
