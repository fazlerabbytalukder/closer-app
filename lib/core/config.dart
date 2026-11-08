/// App-wide feature switches.
abstract final class AppConfig {
  /// Closer Plus subscription, paywall, free-tier limits and ads.
  ///
  /// While false, everything is free and unlimited: no paywall, no ad slots,
  /// no locked themes/packs/stickers, no send or countdown limits. All the
  /// monetization code stays in place; flip this to true (and the matching
  /// `MONETIZATION_ENABLED` in functions/src/common.ts) when RevenueCat and
  /// AdMob are set up.
  static const monetizationEnabled = false;
}
