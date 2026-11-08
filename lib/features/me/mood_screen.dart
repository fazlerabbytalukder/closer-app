import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/data/content.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Mood + status (F6).
class MoodScreen extends ConsumerStatefulWidget {
  const MoodScreen({super.key});

  @override
  ConsumerState<MoodScreen> createState() => _MoodScreenState();
}

class _MoodScreenState extends ConsumerState<MoodScreen> {
  final _status = TextEditingController();
  (String, String)? _mood;

  @override
  void initState() {
    super.initState();
    final me = ref.read(meProvider).value;
    _status.text = me?.status?.text ?? '';
    if (me?.mood != null) _mood = (me!.mood!.emoji, me.mood!.label);
  }

  @override
  void dispose() {
    _status.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final b = ref.read(backendProvider);
    final ok = await runAction(context, () async {
      final m = _mood;
      if (m != null) await b.updateMood(Mood(emoji: m.$1, label: m.$2, updatedAt: DateTime.now()));
      await b.updateStatus(StatusText(text: _status.text.trim(), updatedAt: DateTime.now()));
    });
    if (ok && mounted) {
      hapticSoft();
      showToast(context, '${ref.read(partnerNameProvider)} can see it now');
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final partner = ref.watch(partnerProvider).value;
    final name = ref.watch(partnerNameProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mood & status')),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          if (partner?.mood != null)
            CloserCard(
              color: context.cc.accentTint,
              child: Row(
                children: [
                  Text(partner!.mood!.emoji, style: const TextStyle(fontSize: 32)),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$name’s mood: ${partner.mood!.label}', style: context.tt.titleSmall),
                        if (partner.status?.text.isNotEmpty ?? false)
                          Text(partner.status!.text, style: context.tt.bodySmall?.copyWith(color: context.cc.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (partner?.mood != null) const SizedBox(height: Space.l),
          Text('How are you feeling?', style: context.tt.titleMedium),
          const SizedBox(height: Space.s),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: Space.s,
            crossAxisSpacing: Space.s,
            children: [
              for (final m in moodOptions)
                Semantics(
                  button: true,
                  selected: _mood == m,
                  label: m.$2,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.tile),
                    onTap: () => setState(() => _mood = m),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: _mood == m ? context.cc.accentTint : context.cc.card,
                        borderRadius: BorderRadius.circular(Radii.tile),
                        border: Border.all(color: _mood == m ? context.cc.accent : context.cs.outlineVariant, width: 2),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(m.$1, style: const TextStyle(fontSize: 28)),
                          Text(m.$2, style: context.tt.labelSmall),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.l),
          Text('Status', style: context.tt.titleMedium),
          const SizedBox(height: Space.s),
          TextField(
            controller: _status,
            maxLength: 40,
            decoration: InputDecoration(
              hintText: 'What are you up to?',
              suffixIcon: _status.text.isEmpty
                  ? null
                  : IconButton(tooltip: 'Clear', icon: const Icon(Icons.close_rounded), onPressed: () => setState(_status.clear)),
            ),
            onChanged: (_) => setState(() {}),
          ),
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              for (final s in statusPresets)
                ActionChip(label: Text(s), onPressed: () => setState(() => _status.text = s)),
            ],
          ),
          const SizedBox(height: Space.l),
          CloserButton(label: 'Share with $name', onPressed: _save),
        ],
      ),
    );
  }
}
