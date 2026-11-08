import 'dart:async';

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/notifications.dart';
import 'package:closer_app/core/services/widget_bridge.dart';
import 'package:closer_app/core/services/widget_contract.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/features/me/widget_previews.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Icon(Icons.favorite_rounded, size: 64, color: context.cc.accent)
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scaleXY(begin: 0.9, end: 1.08, duration: 700.ms, curve: Curves.easeInOut),
      ),
    );
  }
}

/// Welcome + Google sign-in.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final backend = ref.watch(backendProvider);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.l),
          child: Column(
            children: [
              const Spacer(),
              const _WelcomeHero()
                  .animate()
                  .fadeIn(duration: 500.ms)
                  .slideY(begin: 0.1, curve: Curves.easeOutCubic),
              const SizedBox(height: Space.xl),
              Text(
                'Your favourite person,\nright on your home screen',
                textAlign: TextAlign.center,
                style: context.tt.headlineMedium,
              ).animate().fadeIn(delay: 150.ms, duration: 500.ms),
              const SizedBox(height: Space.m),
              Text(
                'Send photos, notes and doodles that appear on their widget in seconds. For couples and best friends.',
                textAlign: TextAlign.center,
                style: context.tt.bodyLarge?.copyWith(color: context.cc.muted),
              ).animate().fadeIn(delay: 300.ms, duration: 500.ms),
              const Spacer(),
              CloserButton(
                label: 'Continue with Google',
                icon: Icons.account_circle_rounded,
                loading: _busy,
                onPressed: () async {
                  setState(() => _busy = true);
                  await runAction(context, () => backend.signInWithGoogle());
                  if (mounted) setState(() => _busy = false);
                },
              ),
              const SizedBox(height: Space.m),
              Text(
                backend.isSimulated
                    ? 'Demo mode: your account stays on this device and a simulated partner joins you.'
                    : 'By continuing you agree to our Terms and Privacy Policy. 18+ only.',
                textAlign: TextAlign.center,
                style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero();

  @override
  Widget build(BuildContext context) {
    final cc = context.cc;
    return SizedBox(
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(color: cc.accentTint, shape: BoxShape.circle),
          ),
          Transform.rotate(
            angle: -0.08,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: cc.gradient),
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 30, offset: Offset(0, 12))],
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('💌', style: TextStyle(fontSize: 48)),
                  SizedBox(height: 8),
                  Text('Miss you!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                ],
              ),
            ),
          ),
          Positioned(
            right: 40,
            top: 20,
            child: const Text('💗', style: TextStyle(fontSize: 36))
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .moveY(begin: 0, end: -8, duration: 1200.ms, curve: Curves.easeInOut),
          ),
          Positioned(
            left: 36,
            bottom: 30,
            child: const Text('✨', style: TextStyle(fontSize: 30))
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .moveY(begin: 0, end: 6, duration: 1500.ms, curve: Curves.easeInOut),
          ),
        ],
      ),
    );
  }
}

/// Name + photo.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.editing = false});

  final bool editing;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _name = TextEditingController();
  String? _photo;
  bool _busy = false;
  bool _age = false;

  @override
  void initState() {
    super.initState();
    final me = ref.read(meProvider).value;
    _name.text = me?.displayName ?? '';
    _age = me?.ageConfirmed18 ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800);
    if (x != null) setState(() => _photo = x.path);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider).value;
    final valid = _name.text.trim().isNotEmpty && (_age || widget.editing);
    return Scaffold(
      appBar: AppBar(title: Text(widget.editing ? 'Edit profile' : '')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Space.l),
          children: [
            if (!widget.editing) ...[
              Text('What should your person call you?', style: context.tt.headlineSmall),
              const SizedBox(height: Space.s),
              Text('This shows on their widget.', style: context.tt.bodyLarge?.copyWith(color: context.cc.muted)),
              const SizedBox(height: Space.xl),
            ],
            Center(
              child: GestureDetector(
                onTap: _pick,
                child: Stack(
                  children: [
                    Avatar(
                      name: _name.text,
                      photo: _photo ?? me?.photoUrl,
                      size: 112,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: context.cs.primary,
                        child: const Icon(Icons.camera_alt_rounded, size: 18, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.xl),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              maxLength: 24,
              decoration: const InputDecoration(labelText: 'Your name', hintText: 'e.g. Jamie'),
              onChanged: (_) => setState(() {}),
            ),
            if (!widget.editing)
              CheckboxListTile(
                value: _age,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('I confirm I am 18 or older'),
                onChanged: (v) => setState(() => _age = v ?? false),
              ),
            const SizedBox(height: Space.l),
            CloserButton(
              label: widget.editing ? 'Save' : 'Continue',
              loading: _busy,
              onPressed: !valid
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      final backend = ref.read(backendProvider);
                      final ok = await runAction(context, () async {
                        await backend.updateProfile(displayName: _name.text.trim(), photoFilePath: _photo);
                        if (!widget.editing) await backend.setAgeConfirmed(confirmed: _age);
                      });
                      if (!mounted) return;
                      setState(() => _busy = false);
                      if (ok && widget.editing) context.pop();
                    },
            ),
          ],
        ),
      ),
    );
  }
}

/// Confetti celebration after pairing.
class PairedScreen extends ConsumerStatefulWidget {
  const PairedScreen({super.key});

  @override
  ConsumerState<PairedScreen> createState() => _PairedScreenState();
}

class _PairedScreenState extends ConsumerState<PairedScreen> {
  final _confetti = ConfettiController(duration: const Duration(seconds: 2));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _confetti.play();
      hapticMedium();
    });
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider).value;
    final partner = ref.watch(partnerProvider).value;
    final name = ref.watch(partnerNameProvider);
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Space.l),
              child: Column(
                children: [
                  const Spacer(),
                  AvatarPair(
                    me: me?.displayName ?? '',
                    partner: partner?.displayName ?? '',
                    mePhoto: me?.photoUrl,
                    partnerPhoto: partner?.photoUrl,
                    size: 88,
                  ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
                  const SizedBox(height: Space.xl),
                  Text('You and $name are connected!', textAlign: TextAlign.center, style: context.tt.headlineMedium),
                  const SizedBox(height: Space.m),
                  Text(
                    'Now add the Closer widget so their photos land right on your home screen.',
                    textAlign: TextAlign.center,
                    style: context.tt.bodyLarge?.copyWith(color: context.cc.muted),
                  ),
                  const Spacer(),
                  CloserButton(label: 'Set up my widget', onPressed: () => context.go('/widget-tutorial')),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles: 30,
              colors: const [Brand.pink, Brand.blue, Brand.amber, Brand.green],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Add widget to home screen" tutorial (plan 5.5).
class WidgetTutorialScreen extends ConsumerStatefulWidget {
  const WidgetTutorialScreen({super.key});

  @override
  ConsumerState<WidgetTutorialScreen> createState() => _WidgetTutorialScreenState();
}

class _WidgetTutorialScreenState extends ConsumerState<WidgetTutorialScreen> {
  bool? _canPin;

  @override
  void initState() {
    super.initState();
    unawaited(WidgetBridge.canPin().then((v) {
      if (mounted) setState(() => _canPin = v);
    }));
  }

  Future<void> _finish() async {
    await ref.read(onboardingFlagsProvider.notifier).mark(OnboardingFlags.widgetTutorial);
    if (mounted) context.go('/notifications-permission');
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(partnerNameProvider);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Space.l),
          children: [
            Text('Put $name on your home screen', style: context.tt.headlineSmall),
            const SizedBox(height: Space.s),
            Text(
              'The widget is the heart of Closer. Everything they send shows up here instantly.',
              style: context.tt.bodyLarge?.copyWith(color: context.cc.muted),
            ),
            const SizedBox(height: Space.l),
            const FakeHomeScreen(themeId: WidgetThemes.classic),
            const SizedBox(height: Space.l),
            if (_canPin ?? false) ...[
              CloserButton(
                label: 'Add widget to home screen',
                icon: Icons.add_to_home_screen_rounded,
                onPressed: () async {
                  await WidgetBridge.requestPin(WidgetReceivers.partnerPhoto);
                },
              ),
              const SizedBox(height: Space.m),
            ],
            const _Step(n: 1, text: 'Long-press an empty spot on your home screen'),
            const _Step(n: 2, text: 'Tap “Widgets” and search for “Closer”'),
            const _Step(n: 3, text: 'Drag the photo widget onto your home screen'),
            const SizedBox(height: Space.l),
            CloserButton(
              label: 'Done',
              kind: (_canPin ?? false) ? CloserButtonKind.secondary : CloserButtonKind.primary,
              onPressed: _finish,
            ),
            CloserButton(label: 'I’ll do it later', kind: CloserButtonKind.ghost, onPressed: _finish),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});

  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: context.cc.accentTint,
            child: Text('$n', style: context.tt.labelMedium?.copyWith(color: context.cc.accent)),
          ),
          const SizedBox(width: Space.m),
          Expanded(child: Text(text, style: context.tt.bodyLarge)),
        ],
      ),
    );
  }
}

/// Explanation before asking for POST_NOTIFICATIONS (plan section 13).
class NotificationsPermissionScreen extends ConsumerWidget {
  const NotificationsPermissionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(partnerNameProvider);
    Future<void> done() async {
      await ref.read(onboardingFlagsProvider.notifier).mark(OnboardingFlags.notifications);
      if (context.mounted) context.go('/home');
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.l),
          child: Column(
            children: [
              const Spacer(),
              const Text('🔔', style: TextStyle(fontSize: 72)).animate().shake(delay: 300.ms, hz: 4),
              const SizedBox(height: Space.l),
              Text('Know when $name is thinking of you', textAlign: TextAlign.center, style: context.tt.headlineSmall),
              const SizedBox(height: Space.m),
              Text(
                'We only notify you for things from $name: new photos, heart taps, question reveals and your plant. You can fine-tune this anytime.',
                textAlign: TextAlign.center,
                style: context.tt.bodyLarge?.copyWith(color: context.cc.muted),
              ),
              const Spacer(),
              CloserButton(
                label: 'Turn on notifications',
                onPressed: () async {
                  await NotificationService.instance.requestPermission();
                  await runAction(context, () => ref.read(backendProvider).registerDevice());
                  await done();
                },
              ),
              CloserButton(label: 'Not now', kind: CloserButtonKind.ghost, onPressed: done),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared label for the pair mode.
String modeLabel(PairMode m) => m == PairMode.couple ? 'Couple' : 'Best friends';
