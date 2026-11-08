import 'dart:io';

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/config.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/services/notifications.dart';
import 'package:closer_app/core/services/widget_bridge.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Notifications per type, quiet hours, appearance (F13).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider).value;
    final themeMode = ref.watch(themeModeProvider);
    final prefs = me?.notificationPrefs ?? const NotificationPrefs();
    final backend = ref.read(backendProvider);
    void update(NotificationPrefs p) => runAction(context, () => backend.updateNotificationPrefs(p));
    final quiet = prefs.quietStart != null;

    String hour(int h) => '${h.toString().padLeft(2, '0')}:00';

    Future<int?> pickHour(int initial) async {
      final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: initial, minute: 0));
      return t?.hour;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          Text('Relationship', style: context.tt.titleMedium),
          ListTile(
            leading: const Icon(Icons.favorite_border_rounded),
            title: const Text('Relationship type, labels & anniversary'),
            subtitle: Text(
              [
                if (ref.watch(myLabelForPartnerProvider) case final l?) '${l.emoji} ${l.title}'
                else (ref.watch(pairModeProvider) == PairMode.couple ? '💑 Couple' : '👯 Best friends'),
                'Nickname, together since',
              ].join(' · '),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/relationship'),
          ),
          const Divider(height: Space.xl),
          Text('Notifications', style: context.tt.titleMedium),
          SwitchListTile(
            title: const Text('Thinking-of-you taps'),
            value: prefs.taps,
            onChanged: (v) => update(prefs.copyWith(taps: v)),
          ),
          SwitchListTile(
            title: const Text('Daily question'),
            value: prefs.questions,
            onChanged: (v) => update(prefs.copyWith(questions: v)),
          ),
          SwitchListTile(
            title: const Text('Plant & countdown reminders'),
            value: prefs.reminders,
            onChanged: (v) => update(prefs.copyWith(reminders: v)),
          ),
          const ListTile(
            title: Text('Photos, notes & doodles'),
            subtitle: Text('Always delivered to your widget. Change the sound in Android settings.'),
          ),
          SwitchListTile(
            title: const Text('Quiet hours'),
            subtitle: Text(quiet ? '${hour(prefs.quietStart!)} – ${hour(prefs.quietEnd!)} · widget still updates silently' : 'Pause notifications at night'),
            value: quiet,
            onChanged: (v) => update(prefs.copyWith(quietStart: () => v ? 22 : null, quietEnd: () => v ? 8 : null)),
          ),
          if (quiet)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final h = await pickHour(prefs.quietStart!);
                      if (h != null) update(prefs.copyWith(quietStart: () => h));
                    },
                    child: Text('From ${hour(prefs.quietStart!)}'),
                  ),
                ),
                const SizedBox(width: Space.s),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final h = await pickHour(prefs.quietEnd!);
                      if (h != null) update(prefs.copyWith(quietEnd: () => h));
                    },
                    child: Text('To ${hour(prefs.quietEnd!)}'),
                  ),
                ),
              ],
            ),
          ListTile(
            title: const Text('Allow notifications'),
            subtitle: const Text('Android permission'),
            trailing: const Icon(Icons.open_in_new_rounded, size: 18),
            onTap: () async {
              final granted = await NotificationService.instance.requestPermission();
              if (context.mounted) showToast(context, granted ? 'Notifications are on' : 'Enable notifications in Android settings');
            },
          ),
          const Divider(height: Space.xl),
          Text('Appearance', style: context.tt.titleMedium),
          const SizedBox(height: Space.s),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto_rounded)),
              ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_rounded)),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_rounded)),
            ],
            selected: {themeMode},
            onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
          ),
          const SizedBox(height: Space.s),
          Text(
            'Text size follows your Android font size setting.',
            style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
          ),
        ],
      ),
    );
  }
}

/// Privacy & data: export, unpair, delete account, sign out (F13, plan 12).
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = ref.read(backendProvider);
    final name = ref.watch(partnerNameProvider);
    final paired = ref.watch(pairProvider).value != null;

    Future<void> export() async {
      String? path;
      final ok = await runAction(context, () async => path = await backend.exportMemories());
      if (!ok || path == null || !context.mounted) return;
      if (path!.startsWith('http')) {
        await launchUrl(Uri.parse(path!), mode: LaunchMode.externalApplication);
        return;
      }
      final dir = Directory(path!);
      final files = dir.existsSync() ? dir.listSync().whereType<File>().map((f) => XFile(f.path)).toList() : <XFile>[];
      if (files.isEmpty) {
        showToast(context, 'Nothing to export yet');
        return;
      }
      await SharePlus.instance.share(ShareParams(files: files, text: 'Closer memories export'));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & data')),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          CloserCard(
            color: context.cc.secondaryTint,
            child: Text(
              'Closer is private by design: no public profiles, no search, no strangers. Only you and $name can see what you share. '
              'Photo location data is removed. Data is encrypted in transit and at rest (not end-to-end).',
              style: context.tt.bodyMedium,
            ),
          ),
          const SizedBox(height: Space.m),
          if (paired) ...[
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('Export our memories'),
              subtitle: const Text('Photos + a JSON file'),
              onTap: export,
            ),
            ListTile(
              leading: const Icon(Icons.link_off_rounded),
              title: Text('Unpair from $name'),
              subtitle: const Text('Both of you lose the shared memories'),
              onTap: () async {
                final yes = await confirm(
                  context,
                  title: 'Unpair from $name?',
                  body: 'Your shared memories, questions, countdowns and plant will be deleted. You can export your memories first. $name will be notified.',
                  ok: 'Unpair',
                  destructive: true,
                );
                if (!yes || !context.mounted) return;
                final ok = await runAction(context, backend.unpair);
                if (ok) await WidgetBridge.clear();
              },
            ),
          ],
          ListTile(
            leading: const Icon(Icons.logout_rounded),
            title: const Text('Sign out'),
            onTap: () async {
              final yes = await confirm(context, title: 'Sign out?', body: 'Your widgets will show “Open Closer to connect” until you sign in again.', ok: 'Sign out');
              if (!yes || !context.mounted) return;
              await WidgetBridge.clear();
              await ref.read(onboardingFlagsProvider.notifier).clear();
              await backend.signOut();
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_forever_rounded, color: context.cs.error),
            title: Text('Delete my account', style: TextStyle(color: context.cs.error)),
            subtitle: const Text('Also available at closer.app/delete-account'),
            onTap: () async {
              final yes = await confirm(
                context,
                title: 'Delete your account?',
                body: 'This permanently deletes your profile, everything you sent and your pairing. This cannot be undone.',
                ok: 'Delete forever',
                destructive: true,
              );
              if (!yes || !context.mounted) return;
              await WidgetBridge.clear();
              await ref.read(onboardingFlagsProvider.notifier).clear();
              if (context.mounted) await runAction(context, backend.deleteAccount);
            },
          ),
          const Divider(height: Space.xl),
          ListTile(
            leading: const Icon(Icons.policy_outlined),
            title: const Text('Privacy policy'),
            onTap: () => launchUrl(Uri.parse('https://closer.app/privacy.html')),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms of use'),
            onTap: () => launchUrl(Uri.parse('https://closer.app/terms.html')),
          ),
        ],
      ),
    );
  }
}

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & feedback')),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          const _Faq(q: 'How fast do photos arrive?', a: 'Usually within a few seconds. Some phones delay background work to save battery — see “Widget not updating?”.'),
          if (AppConfig.monetizationEnabled)
            const _Faq(q: 'Is Closer Plus shared?', a: 'Yes. One subscription covers both of you. If you unpair, Plus stays with whoever bought it.'),
          const _Faq(q: 'How do we connect?', a: 'One of you taps “Invite your person” and sends the 6-character code (or link). The other taps “I have a code” and enters it. You’re connected as soon as the code is accepted, as a couple or as best friends, whichever the inviter chose. You can change the relationship type later in Settings → Relationship.'),
          const _Faq(q: 'What counts for the streak?', a: 'Sending something, a heart tap, or answering the daily question. A day counts when you both do something.'),
          const _Faq(q: 'Can I change my person?', a: 'Unpair in Privacy & data, then invite someone new.'),
          const SizedBox(height: Space.m),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('Report a problem'),
            onTap: () => launchUrl(Uri.parse('https://closer.app/#contact')),
          ),
          ListTile(
            leading: const Icon(Icons.star_outline_rounded),
            title: const Text('Rate Closer'),
            onTap: () => launchUrl(
              Uri.parse('https://play.google.com/store/apps/details?id=app.closer.widget'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
    );
  }
}

class _Faq extends StatelessWidget {
  const _Faq({required this.q, required this.a});

  final String q;
  final String a;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      shape: const Border(),
      title: Text(q, style: context.tt.titleSmall),
      childrenPadding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
      children: [Align(alignment: Alignment.centerLeft, child: Text(a, style: context.tt.bodyMedium))],
    );
  }
}

/// "Widget not updating?" with device-specific battery steps (plan 5.4).
class WidgetHelpScreen extends StatelessWidget {
  const WidgetHelpScreen({super.key});

  static const _oems = <(String, List<String>)>[
    ('Samsung (One UI)', ['Settings → Apps → Closer → Battery → Unrestricted', 'Settings → Battery → Background usage limits → remove Closer from “Sleeping apps”']),
    ('Xiaomi / Redmi / POCO (HyperOS, MIUI)', ['Settings → Apps → Manage apps → Closer → Autostart: On', 'Battery saver → No restrictions', 'In Recents, long-press Closer → lock it']),
    ('Oppo / Realme / OnePlus (ColorOS)', ['Settings → Battery → Closer → Allow background activity', 'Settings → Apps → Closer → Auto launch: On']),
    ('Vivo (Funtouch / OriginOS)', ['Settings → Battery → Background power consumption → Closer: Allow', 'i Manager → App manager → Autostart → Closer: On']),
    ('Huawei / Honor (EMUI, MagicOS)', ['Settings → Battery → App launch → Closer → Manage manually, enable all three']),
    ('Google Pixel & others', ['Settings → Apps → Closer → App battery usage → Unrestricted']),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Widget not updating?')),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          Text(
            'Some phones pause apps in the background to save battery, which can delay your widget. These steps fix it on most devices:',
            style: context.tt.bodyLarge,
          ),
          const SizedBox(height: Space.m),
          CloserButton(
            label: 'Refresh my widgets now',
            icon: Icons.refresh_rounded,
            kind: CloserButtonKind.secondary,
            onPressed: () async {
              await WidgetBridge.updateAll();
              if (context.mounted) showToast(context, 'Widgets refreshed');
            },
          ),
          const SizedBox(height: Space.m),
          for (final (name, steps) in _oems)
            ExpansionTile(
              shape: const Border(),
              title: Text(name, style: context.tt.titleSmall),
              childrenPadding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
              children: [
                for (final s in steps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [const Text('•  '), Expanded(child: Text(s))],
                    ),
                  ),
              ],
            ),
          const SizedBox(height: Space.m),
          Text(
            'Still stuck? Remove the widget and add it again, or restart your phone. Opening Closer always refreshes the widget.',
            style: context.tt.bodyMedium?.copyWith(color: context.cc.muted),
          ),
        ],
      ),
    );
  }
}
