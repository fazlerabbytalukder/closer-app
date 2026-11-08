/// Contract between the Flutter app and the native Kotlin Glance widgets.
///
/// Flutter writes these keys with `HomeWidget.saveWidgetData` into the
/// `HomeWidgetPreferences` SharedPreferences file; the Kotlin widgets read
/// them (see `android/app/src/main/kotlin/app/closer/widget/widgets/
/// WidgetKeys.kt`, which must stay in sync with this file).
///
/// All values are stored as **String** (or Boolean where noted) so Kotlin
/// never has to guess between Int and Long. Timestamps are millis as String.
abstract final class WidgetKeys {
  /// Boolean. False → widgets show "Open Closer to connect".
  static const paired = 'paired';
  static const partnerName = 'partner_name';

  /// 'couple' | 'friends'
  static const mode = 'mode';

  /// Absolute path of the partner's latest item thumbnail (JPEG/PNG,
  /// max ~600px) inside the app's files directory. Empty = none yet.
  static const latestPath = 'latest_path';

  /// 'photo' | 'note' | 'doodle'
  static const latestType = 'latest_type';
  static const latestCaption = 'latest_caption';
  static const latestSentAt = 'latest_sent_at';

  /// Show the heart badge until this time (millis). Empty = no badge.
  static const heartUntil = 'heart_until';

  /// e.g. "😊 Happy" — optional line on medium/large widget.
  static const partnerMood = 'partner_mood';

  /// Widget theme id, see [WidgetThemes].
  static const themeId = 'theme_id';

  /// Next countdown. All empty when there is none. Date is yyyy-MM-dd; the
  /// widget computes "days left" itself so it stays right after midnight.
  static const countdownTitle = 'countdown_title';
  static const countdownEmoji = 'countdown_emoji';
  static const countdownDate = 'countdown_date';

  static const streakCount = 'streak_count';

  /// 0..8 (see Plant.milestones).
  static const plantStage = 'plant_stage';

  /// 'healthy' | 'wilted'
  static const plantHealth = 'plant_health';
}

/// Fully-qualified receiver class names of the Glance widgets.
abstract final class WidgetReceivers {
  static const partnerPhoto =
      'app.closer.widget.widgets.PartnerPhotoWidgetReceiver';
  static const countdown = 'app.closer.widget.widgets.CountdownWidgetReceiver';
  static const plant = 'app.closer.widget.widgets.PlantWidgetReceiver';

  static const all = [partnerPhoto, countdown, plant];
}

/// Deep links fired by widget taps (home_widget launch intents).
abstract final class WidgetLinks {
  static const reply = 'closer://reply';
  static const countdowns = 'closer://countdowns';
  static const plant = 'closer://plant';
}

/// Widget theme ids. Kotlin maps each to colours (WidgetTheme.kt).
abstract final class WidgetThemes {
  static const classic = 'classic';
  static const blush = 'blush';
  static const midnight = 'midnight';
  static const mint = 'mint';
  static const sunset = 'sunset';
  static const dynamic = 'dynamic';

  static const free = [classic, blush, dynamic];
  static const plus = [midnight, mint, sunset];
  static const all = [...free, ...plus];
}
