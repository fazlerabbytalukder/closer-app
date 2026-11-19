import 'dart:async';

import 'package:closer_app/app/providers.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/app_theme.dart';
import 'package:closer_app/core/ui/actions.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:closer_app/core/ui/plant_art.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The pet that grows from your plant, and its shared home (F16).
class PetScreen extends ConsumerStatefulWidget {
  const PetScreen({super.key});

  @override
  ConsumerState<PetScreen> createState() => _PetScreenState();
}

class _PetScreenState extends ConsumerState<PetScreen> {
  final _confetti = ConfettiController(duration: const Duration(seconds: 2));
  final _hearts = <int>[];
  bool _editing = false;

  /// Local positions while dragging, so the room doesn't wait for the server.
  List<PlacedDecor>? _draft;

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  void _burst() {
    hapticSoft();
    final id = DateTime.now().microsecondsSinceEpoch;
    setState(() => _hearts.add(id));
  }

  Future<void> _care(String action, String petName) async {
    hapticMedium();
    _burst();
    final ok = await runAction(context, () => ref.read(backendProvider).careForPet(action));
    if (ok && mounted) showToast(context, action == 'feed' ? '$petName munches happily 🍎' : '$petName loved that! 🎾');
  }

  Future<void> _hatch(Pair pair) async {
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const _HatchSheet(),
    );
    if (result == null || !mounted) return;
    final ok = await runAction(
      context,
      () => ref.read(backendProvider).savePet(Pet(species: result.$1, name: result.$2, hatchedAt: DateTime.now())),
    );
    if (ok && mounted) {
      hapticMedium();
      _confetti.play();
      showToast(context, 'Say hi to ${result.$2}! 🎉');
    }
  }

  Future<void> _rename(Pet pet) async {
    final ctrl = TextEditingController(text: pet.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename your pet'),
        content: TextField(controller: ctrl, autofocus: true, maxLength: Pet.maxName, textCapitalization: TextCapitalization.words),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    disposeAfterRoute(ctrl);
    if (name == null || name.isEmpty || !mounted) return;
    await runAction(context, () => ref.read(backendProvider).savePet(pet.copyWith(name: name)));
  }

  Future<void> _saveHome(PetHome home) => runAction(context, () => ref.read(backendProvider).saveHome(home));

  @override
  Widget build(BuildContext context) {
    final pair = ref.watch(pairProvider).value;
    final me = ref.watch(authUidProvider).value;
    final name = ref.watch(partnerNameProvider);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    if (pair == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final pet = pair.pet;
    final home = pair.home;
    final placed = _draft ?? home.placed;
    final partnerUid = me == null ? '' : pair.partnerOf(me);
    final mood = pet?.mood(now, plant: pair.plant.health, members: pair.memberIds);

    return Scaffold(
      appBar: AppBar(
        title: Text(pet == null ? 'Your plant’s secret' : '${pet.name}’s home'),
        actions: [
          if (pet != null) IconButton(tooltip: 'Rename', icon: const Icon(Icons.edit_rounded), onPressed: () => _rename(pet)),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(Space.m),
            children: [
              Row(
                children: [
                  CounterChip(label: '💗 ${pair.lovePoints} love points', color: context.cc.accent),
                  const Spacer(),
                  if (pet != null)
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _editing = !_editing;
                        if (!_editing) _draft = null;
                      }),
                      icon: Icon(_editing ? Icons.check_rounded : Icons.open_with_rounded),
                      label: Text(_editing ? 'Done' : 'Move things'),
                    ),
                ],
              ),
              const SizedBox(height: Space.s),
              _Room(
                pair: pair,
                placed: placed,
                editing: _editing,
                hearts: _hearts,
                onHeartDone: (id) => setState(() => _hearts.remove(id)),
                onPetTap: pet == null ? null : _burst,
                onMove: (i, x, y) => setState(() {
                  final list = [...placed];
                  list[i] = PlacedDecor(list[i].id, x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
                  _draft = list;
                }),
                onMoveEnd: () {
                  final d = _draft;
                  if (d != null) unawaited(_saveHome(home.copyWith(placed: d)));
                },
                onRemove: (i) {
                  final list = [...placed]..removeAt(i);
                  setState(() => _draft = list);
                  unawaited(_saveHome(home.copyWith(placed: list)));
                },
              ),
              const SizedBox(height: Space.m),
              if (pet == null)
                _EggCard(stage: pair.plant.stage, onHatch: () => _hatch(pair))
              else ...[
                CloserCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(pet.info.emoji, style: const TextStyle(fontSize: 28)),
                          const SizedBox(width: Space.s),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(pet.name, style: context.tt.titleLarge),
                                Text(
                                  '${Pet.lifeStageNames[Pet.lifeStage(pair.plant.stage)]} ${pet.info.name.toLowerCase()} · grows with your plant',
                                  style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.s),
                      Text('${mood!.emoji} ${pet.name} ${mood.text}', style: context.tt.bodyMedium),
                      const SizedBox(height: Space.m),
                      Row(
                        children: [
                          Expanded(
                            child: _CareButton(
                              emoji: '🍎',
                              label: 'Feed',
                              done: me != null && pet.fedBy(me, now),
                              partnerDone: pet.fedBy(partnerUid, now),
                              partnerName: name,
                              onTap: () => _care('feed', pet.name),
                            ),
                          ),
                          const SizedBox(width: Space.s),
                          Expanded(
                            child: _CareButton(
                              emoji: '🎾',
                              label: 'Play',
                              done: me != null && pet.playedBy(me, now),
                              partnerDone: pet.playedBy(partnerUid, now),
                              partnerName: name,
                              onTap: () => _care('play', pet.name),
                            ),
                          ),
                        ],
                      ),
                      if (pair.plant.health == PlantHealth.wilted) ...[
                        const SizedBox(height: Space.s),
                        TextButton.icon(
                          onPressed: () => context.push('/plant'),
                          icon: const Text('🥀'),
                          label: const Text('The plant needs you both today'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: Space.m),
                CloserButton(
                  label: 'Decorate the home',
                  icon: Icons.chair_rounded,
                  kind: CloserButtonKind.accent,
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const _ShopSheet(),
                  ),
                ),
              ],
              const SizedBox(height: Space.m),
              Text(
                'Love points come from everything you do together: photos, taps, daily questions, your best streak and your plant.',
                textAlign: TextAlign.center,
                style: context.tt.bodySmall?.copyWith(color: context.cc.muted),
              ),
            ],
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirectionality: BlastDirectionality.explosive,
              colors: const [Brand.pink, Brand.purple, Brand.amber, Brand.green],
            ),
          ),
        ],
      ),
    );
  }
}

class _Room extends StatelessWidget {
  const _Room({
    required this.pair,
    required this.placed,
    required this.editing,
    required this.hearts,
    required this.onHeartDone,
    required this.onPetTap,
    required this.onMove,
    required this.onMoveEnd,
    required this.onRemove,
  });

  final Pair pair;
  final List<PlacedDecor> placed;
  final bool editing;
  final List<int> hearts;
  final ValueChanged<int> onHeartDone;
  final VoidCallback? onPetTap;
  final void Function(int index, double x, double y) onMove;
  final VoidCallback onMoveEnd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final wall = Wallpaper.byId(pair.home.wallpaper);
    final pet = pair.pet;
    final now = DateTime.now();
    final mood = pet?.mood(now, plant: pair.plant.health, members: pair.memberIds);
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.card),
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final h = c.maxHeight;
            return Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(wall.top), Color(wall.bottom)]),
                    ),
                  ),
                ),
                // Window
                Positioned(
                  left: w * 0.62,
                  top: h * 0.1,
                  child: Container(
                    width: w * 0.26,
                    height: h * 0.22,
                    decoration: BoxDecoration(
                      color: const Color(0xFFBFE3FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 4),
                    ),
                    child: Center(child: Text(Goodnight.isEvening(now) ? '🌙' : '☀️', style: TextStyle(fontSize: w * 0.07))),
                  ),
                ),
                // Floor
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: h * 0.32,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFD9B48F), Color(0xFFC49A72)]),
                    ),
                  ),
                ),
                // The plant the pet came from.
                Positioned(
                  left: w * 0.03,
                  bottom: h * 0.05,
                  child: PlantArt(stage: pair.plant.stage, health: pair.plant.health, size: w * 0.32),
                ),
                for (final (i, p) in placed.indexed)
                  if (Decor.byId(p.id) case final d?)
                    Positioned(
                      left: p.x * (w - w * 0.14),
                      top: p.y * (h - w * 0.14),
                      child: GestureDetector(
                        onPanUpdate: editing
                            ? (u) => onMove(
                                  i,
                                  ((p.x * (w - w * 0.14)) + u.delta.dx) / (w - w * 0.14),
                                  ((p.y * (h - w * 0.14)) + u.delta.dy) / (h - w * 0.14),
                                )
                            : null,
                        onPanEnd: editing ? (_) => onMoveEnd() : null,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: editing
                                  ? BoxDecoration(border: Border.all(color: Colors.white, width: 1.5), borderRadius: BorderRadius.circular(8))
                                  : null,
                              child: Text(d.emoji, style: TextStyle(fontSize: w * 0.1)),
                            ),
                            if (editing)
                              Positioned(
                                right: -8,
                                top: -8,
                                child: GestureDetector(
                                  onTap: () => onRemove(i),
                                  child: const CircleAvatar(radius: 10, backgroundColor: Colors.white, child: Icon(Icons.close_rounded, size: 14)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                // The pet (or its egg in the plant).
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: h * 0.08,
                  child: Center(
                    child: pet == null
                        ? _Egg(size: w * 0.16, ready: pair.plant.stage >= Pet.hatchStage)
                        : GestureDetector(
                            onTap: onPetTap,
                            child: Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.center,
                              children: [
                                PetArt(pet: pet, plantStage: pair.plant.stage, mood: mood!, size: w * 0.24),
                                for (final id in hearts)
                                  Text('💗', key: ValueKey(id), style: TextStyle(fontSize: w * 0.06))
                                      .animate(onComplete: (_) => onHeartDone(id))
                                      .moveY(begin: 0, end: -w * 0.25, duration: 900.ms, curve: Curves.easeOut)
                                      .moveX(begin: 0, end: (id % 5 - 2) * 10.0, duration: 900.ms)
                                      .fadeOut(delay: 400.ms, duration: 500.ms),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The pet: its species emoji, sized by life stage, with mood touches.
class PetArt extends StatelessWidget {
  const PetArt({required this.pet, required this.plantStage, required this.mood, super.key, this.size = 96});

  final Pet pet;
  final int plantStage;
  final PetMood mood;
  final double size;

  @override
  Widget build(BuildContext context) {
    final stage = Pet.lifeStage(plantStage);
    final scale = const [0.62, 0.78, 0.92, 1.0][stage];
    final sleepy = mood == PetMood.sleepy;
    Widget body = Text(pet.info.emoji, style: TextStyle(fontSize: size * scale));
    body = sleepy
        ? body.animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 1, end: 1.04, duration: 1800.ms)
        : body
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .moveY(begin: 0, end: -size * 0.06, duration: (mood == PetMood.overjoyed ? 400 : 900).ms, curve: Curves.easeInOut);
    return SizedBox(
      width: size * 1.4,
      height: size * 1.25,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // Shadow
          Positioned(
            bottom: 0,
            child: Container(
              width: size * scale * 0.8,
              height: size * 0.08,
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
            ),
          ),
          Positioned(bottom: size * 0.04, child: body),
          if (stage >= 3)
            Positioned(top: 0, child: Text('👑', style: TextStyle(fontSize: size * 0.22)))
          else if (stage == 2)
            Positioned(top: size * 0.1, right: size * 0.25, child: Text('🌸', style: TextStyle(fontSize: size * 0.18))),
          if (sleepy)
            Positioned(
              top: 0,
              right: 0,
              child: Text('💤', style: TextStyle(fontSize: size * 0.22))
                  .animate(onPlay: (c) => c.repeat())
                  .moveY(begin: 0, end: -10, duration: 1500.ms)
                  .fadeOut(duration: 1500.ms),
            )
          else if (mood == PetMood.hungry || mood == PetMood.bored)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: Text(mood.emoji, style: TextStyle(fontSize: size * 0.16)),
              ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 0.9, end: 1.1, duration: 700.ms),
            )
          else if (mood == PetMood.overjoyed)
            Positioned(top: 0, left: 0, child: Text('✨', style: TextStyle(fontSize: size * 0.2))),
        ],
      ),
    );
  }
}

class _Egg extends StatelessWidget {
  const _Egg({required this.size, required this.ready});

  final double size;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final egg = Text('🥚', style: TextStyle(fontSize: size));
    if (!ready) return Opacity(opacity: 0.55, child: egg);
    return egg
        .animate(onPlay: (c) => c.repeat())
        .rotate(begin: 0, end: 0.05, duration: 120.ms)
        .then()
        .rotate(begin: 0.05, end: -0.05, duration: 120.ms)
        .then()
        .rotate(begin: -0.05, end: 0, duration: 120.ms)
        .then(delay: 1200.ms);
  }
}

class _EggCard extends StatelessWidget {
  const _EggCard({required this.stage, required this.onHatch});

  final int stage;
  final VoidCallback onHatch;

  @override
  Widget build(BuildContext context) {
    final ready = stage >= Pet.hatchStage;
    final days = Plant.milestones[Pet.hatchStage - 1];
    return CloserCard(
      gradient: const LinearGradient(colors: [Color(0xFFFFF3D6), Color(0xFFFFE6EF)]),
      child: Column(
        children: [
          Text(ready ? 'Your plant grew an egg! 🥚' : 'Something is growing in your plant…', textAlign: TextAlign.center, style: context.tt.titleMedium?.copyWith(color: Brand.ink)),
          const SizedBox(height: Space.xs),
          Text(
            ready
                ? 'Hatch it together and pick who lives in it.'
                : 'Keep your streak going. At $days days ($stage of ${Pet.hatchStage} plant stages), an egg appears.',
            textAlign: TextAlign.center,
            style: context.tt.bodyMedium?.copyWith(color: Brand.grey700),
          ),
          if (!ready) ...[
            const SizedBox(height: Space.s),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(value: stage / Pet.hatchStage, minHeight: 8, backgroundColor: Colors.white, color: Brand.pink),
            ),
          ] else ...[
            const SizedBox(height: Space.m),
            CloserButton(label: 'Hatch the egg', icon: Icons.egg_rounded, kind: CloserButtonKind.accent, onPressed: onHatch),
          ],
        ],
      ),
    );
  }
}

class _CareButton extends StatelessWidget {
  const _CareButton({
    required this.emoji,
    required this.label,
    required this.done,
    required this.partnerDone,
    required this.partnerName,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final bool done;
  final bool partnerDone;
  final String partnerName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: done ? context.cc.plantTint : context.cc.accentTint,
      borderRadius: BorderRadius.circular(Radii.small + 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.small + 4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s + 4, horizontal: Space.s),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 26)),
              Text(done ? '$label again' : label, style: context.tt.titleSmall),
              Text(
                [if (done) 'You ✓', if (partnerDone) '$partnerName ✓'].join(' · ').ifEmpty('Not yet today'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.tt.labelSmall?.copyWith(color: context.cc.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

class _HatchSheet extends StatefulWidget {
  const _HatchSheet();

  @override
  State<_HatchSheet> createState() => _HatchSheetState();
}

class _HatchSheetState extends State<_HatchSheet> {
  final _name = TextEditingController();
  String _species = PetSpecies.all.first.id;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, MediaQuery.viewInsetsOf(context).bottom + Space.m),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Who’s in the egg?', textAlign: TextAlign.center, style: context.tt.titleLarge),
          const SizedBox(height: Space.m),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (final s in PetSpecies.all)
                InkWell(
                  borderRadius: BorderRadius.circular(Radii.small + 4),
                  onTap: () => setState(() => _species = s.id),
                  child: AnimatedContainer(
                    duration: 200.ms,
                    decoration: BoxDecoration(
                      color: _species == s.id ? context.cc.accentTint : context.cc.card,
                      borderRadius: BorderRadius.circular(Radii.small + 4),
                      border: Border.all(color: _species == s.id ? context.cc.accent : Colors.transparent, width: 2),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(s.emoji, style: const TextStyle(fontSize: 32)),
                        Text(s.name, style: context.tt.labelSmall),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.m),
          TextField(
            controller: _name,
            maxLength: Pet.maxName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name your pet'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.s),
          CloserButton(
            label: 'Hatch!',
            kind: CloserButtonKind.accent,
            onPressed: _name.text.trim().isEmpty ? null : () => Navigator.pop(context, (_species, _name.text.trim())),
          ),
        ],
      ),
    );
  }
}

/// Buy and place decorations, pick a wallpaper.
class _ShopSheet extends ConsumerWidget {
  const _ShopSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pair = ref.watch(pairProvider).value;
    if (pair == null) return const SizedBox.shrink();
    final home = pair.home;
    final points = pair.lovePoints;
    final stage = pair.plant.stage;

    Future<void> save(PetHome next, String toast) async {
      final ok = await runAction(context, () => ref.read(backendProvider).saveHome(next));
      if (ok && context.mounted) showToast(context, toast);
    }

    Future<void> tapDecor(Decor d) async {
      if (home.placed.length >= PetHome.maxPlaced) {
        showToast(context, 'The room is full! Remove something first');
        return;
      }
      final spot = PlacedDecor(d.id, 0.3 + (home.placed.length % 5) * 0.12, 0.45 + (home.placed.length % 3) * 0.1);
      if (home.ownsDecor(d, stage)) {
        await save(home.copyWith(placed: [...home.placed, spot]), '${d.emoji} placed. Tap “Move things” to arrange');
        return;
      }
      if (d.isReward) {
        showToast(context, 'Unlocks when your plant is a ${Plant.stageNames[d.unlockStage].toLowerCase()}');
        return;
      }
      if (points < d.cost) {
        showToast(context, 'You need ${d.cost - points} more love points 💗');
        return;
      }
      await save(
        home.copyWith(owned: [...home.owned, d.id], placed: [...home.placed, spot], spent: home.spent + d.cost),
        '${d.name} bought and placed 🎉',
      );
    }

    Future<void> tapWallpaper(Wallpaper w) async {
      if (home.ownsWallpaper(w)) {
        await save(home.copyWith(wallpaper: w.id), 'Wallpaper changed');
        return;
      }
      if (points < w.cost) {
        showToast(context, 'You need ${w.cost - points} more love points 💗');
        return;
      }
      await save(home.copyWith(owned: [...home.owned, w.id], wallpaper: w.id, spent: home.spent + w.cost), '${w.name} it is 🎨');
    }

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: ListView(
          padding: const EdgeInsets.all(Space.m),
          children: [
            Row(
              children: [
                Expanded(child: Text('Decorate', style: context.tt.titleLarge)),
                CounterChip(label: '💗 $points', color: context.cc.accent),
              ],
            ),
            const SizedBox(height: Space.m),
            Text('Wallpaper', style: context.tt.titleSmall),
            const SizedBox(height: Space.s),
            SizedBox(
              height: 86,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final w in Wallpaper.all)
                    GestureDetector(
                      onTap: () => tapWallpaper(w),
                      child: Container(
                        width: 76,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(w.top), Color(w.bottom)]),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: home.wallpaper == w.id ? context.cc.accent : Colors.transparent, width: 3),
                        ),
                        alignment: Alignment.bottomCenter,
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          home.ownsWallpaper(w) ? w.name : '💗 ${w.cost}',
                          textAlign: TextAlign.center,
                          style: context.tt.labelSmall?.copyWith(color: w.id == 'night' ? Colors.white : Brand.ink),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.m),
            Text('Decorations', style: context.tt.titleSmall),
            const SizedBox(height: Space.s),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.85,
              children: [
                for (final d in Decor.all)
                  InkWell(
                    borderRadius: BorderRadius.circular(Radii.small + 4),
                    onTap: () => tapDecor(d),
                    child: Container(
                      decoration: BoxDecoration(color: context.cc.card, borderRadius: BorderRadius.circular(Radii.small + 4)),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Opacity(
                            opacity: home.ownsDecor(d, stage) || (!d.isReward && points >= d.cost) ? 1 : 0.45,
                            child: Text(d.emoji, style: const TextStyle(fontSize: 30)),
                          ),
                          Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.labelSmall),
                          Text(
                            home.ownsDecor(d, stage)
                                ? 'Place'
                                : d.isReward
                                    ? '🌱 ${Plant.stageNames[d.unlockStage]}'
                                    : '💗 ${d.cost}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.tt.labelSmall?.copyWith(color: context.cc.accent, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
