import 'dart:async';

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Ads facade (plan section 11).
///
/// Production wiring: `google_mobile_ads` RewardedAd + adaptive BannerAd,
/// after Google UMP consent, with server-side verification of rewards. Until
/// AdMob unit ids exist, this shows a simulated rewarded ad and a "house"
/// banner promoting Plus so the flows can be tested end to end.
abstract final class Ads {
  /// Returns true when the user earned the reward.
  static Future<bool> showRewarded(BuildContext context) async {
    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SimulatedRewardedAd(),
    );
    return res ?? false;
  }
}

class _SimulatedRewardedAd extends StatefulWidget {
  const _SimulatedRewardedAd();

  @override
  State<_SimulatedRewardedAd> createState() => _SimulatedRewardedAdState();
}

class _SimulatedRewardedAdState extends State<_SimulatedRewardedAd> {
  int _left = 5;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_left <= 1) {
        t.cancel();
        if (mounted) Navigator.pop(context, true);
      } else {
        setState(() => _left--);
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sponsored'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🎬', style: TextStyle(fontSize: 56)),
          const SizedBox(height: Space.m),
          Text('Test ad — your reward unlocks in $_left s'),
          const SizedBox(height: Space.m),
          LinearProgressIndicator(value: (5 - _left) / 5),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Skip (no reward)')),
      ],
    );
  }
}

/// Banner slot for non-core screens only. Hidden for Plus pairs.
class AdBanner extends ConsumerWidget {
  const AdBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(isPlusProvider)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s),
      child: Material(
        color: context.cs.surfaceContainer,
        borderRadius: BorderRadius.circular(Radii.small),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.small),
          onTap: () => context.push('/paywall?from=banner'),
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                const SizedBox(width: Space.m),
                Text('Ad', style: context.tt.labelSmall?.copyWith(color: context.cc.muted)),
                const SizedBox(width: Space.m),
                const Expanded(child: Text('Go ad-free with Closer Plus — for both of you ✨')),
                const Icon(Icons.chevron_right_rounded),
                const SizedBox(width: Space.s),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
