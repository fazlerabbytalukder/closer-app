import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/data/content.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/soft_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final partnerMood = partner?.mood;
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          VioletPageHeader(
            title: 'Mood & status',
            child: partnerMood == null
                ? null
                : _PartnerMoodCard(
                    emoji: partnerMood.emoji,
                    title: '$name’s mood: ${partnerMood.label}',
                    status: partner!.status?.text ?? '',
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PageSectionTitle('How are you feeling?'),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.cc.card,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: dark ? null : softCardShadow,
                  ),
                  child: GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.05,
                    children: [
                      for (final m in moodOptions)
                        _MoodTile(
                          emoji: m.$1,
                          label: m.$2,
                          selected: _mood == m,
                          onTap: () => setState(() => _mood = m),
                        ),
                    ],
                  ),
                ),
                const PageSectionTitle('Status'),
                TextField(
                  controller: _status,
                  maxLength: 40,
                  decoration: softFieldDecoration(
                    context,
                    hint: 'What are you up to?',
                    max: 40,
                    length: _status.text.length,
                    clear: _status.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => setState(_status.clear),
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 10,
                  children: [
                    for (final s in statusPresets)
                      _StatusChip(label: s, selected: _status.text == s, onTap: () => setState(() => _status.text = s)),
                  ],
                ),
                const SizedBox(height: 28),
                PillButton(label: 'Share with $name', onPressed: _save),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pink card on the header edge with the partner's mood and the mascot.
class _PartnerMoodCard extends StatelessWidget {
  const _PartnerMoodCard({required this.emoji, required this.title, required this.status});

  final String emoji;
  final String title;
  final String status;

  @override
  Widget build(BuildContext context) {
    const ink = Brand.ink;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFF8CC6), Color(0xFFFFA9D3)]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: Color(0x66FF5C9E), blurRadius: 30, offset: Offset(0, 18), spreadRadius: -12),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -6,
            bottom: -26,
            child: Image.asset('assets/home/progress_mascot.png', width: 84, height: 92),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 84, 14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text(emoji, style: const TextStyle(fontSize: 26)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.tt.titleSmall?.copyWith(color: ink, fontWeight: FontWeight.w800),
                      ),
                      if (status.isNotEmpty)
                        Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.tt.bodySmall?.copyWith(color: ink.withValues(alpha: 0.8)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One mood in the grid: lavender tile, emoji and label; violet ring when picked.
class _MoodTile extends StatelessWidget {
  const _MoodTile({required this.emoji, required this.label, required this.selected, required this.onTap});

  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tint = dark ? SoftTone.violet.icon.withValues(alpha: 0.14) : const Color(0xFFF5F2FF);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: selected ? SoftTone.violet.fill(context) : tint,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? context.cs.primary : Colors.transparent, width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: selected ? 1.12 : 1,
                duration: const Duration(milliseconds: 150),
                child: Text(emoji, style: const TextStyle(fontSize: 30)),
              ),
              const SizedBox(height: 4),
              Text(label, style: context.tt.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

/// White status suggestion pill with a soft shadow.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: dark || selected ? null : softCardShadow,
      ),
      child: Material(
        color: selected ? SoftTone.violet.fill(context) : context.cc.card,
        shape: StadiumBorder(side: BorderSide(color: selected ? context.cs.primary : Colors.transparent, width: 1.6)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Text(label, style: context.tt.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}
