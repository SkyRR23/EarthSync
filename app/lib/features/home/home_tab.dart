import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../app/strings.dart';
import '../../data/models/farm_boundary.dart';
import '../../data/models/farmer_input.dart';
import '../../design/components/buttons.dart';
import '../../design/components/earth.dart';
import '../../design/components/grouped.dart';
import '../../design/tokens.dart';
import '../../state/account.dart';
import '../../state/providers.dart';
import '../map/gibs_layer.dart' show satelliteCredit;
import '../today/farm_tasks.dart';
import 'home_shell.dart';
import '../../evidence/state/local_farm_provider.dart';
import 'task_cards.dart';

/// Crop name the farmer gave, or null when not answered / not sure.
String? cropName(FarmerDraft d) {
  final c = d.currentCrop;
  if (c == null || c == kUnknown || c == 'fallow') return null;
  return Crops.label(c);
}

String greeting(DateTime now) => now.hour < 12
    ? S.goodMorning
    : now.hour < 17
    ? S.goodAfternoon
    : S.goodEvening;

/// Field status shown on pills: honest about what is known (tasks), never a
/// crop-health claim the app cannot measure.
(String, FsPillTone) fieldStatus(List<FarmTask> tasks) {
  final todo = tasks.where((t) => !t.done).toList();
  if (todo.any(isUrgent)) return (S.needsALook, FsPillTone.look);
  if (todo.isEmpty) return (S.allDone, FsPillTone.good);
  return (S.nToDo(todo.length), FsPillTone.info);
}

/// Home (the "Crops" tab in the team design): greeting, the farm hero card,
/// today's tasks, your field, and "Check my crops".
class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key, this.now});

  /// Fixed clock for tests.
  final DateTime? now;

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  final _tasksKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(farmerDraftProvider);
    if (!d.hasLocation) return const NoFarmView();
    final p = context.fs;
    final t = context.type;
    final now = widget.now ?? DateTime.now();
    final tasks = watchTasks(ref, now);
    final unread = ref.watch(prefsProvider) == null
        ? 0
        : (ref.watch(localNotificationsProvider).value ?? [])
              .where((item) => item['read'] != true)
              .length;
    final signedIn = ref.watch(userProvider).value != null;
    final tabs = HomeTabs.of(context);
    final crop = cropName(d);
    final status = fieldStatus(tasks);

    return Scaffold(
      backgroundColor: p.background,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'ask',
        onPressed: () => context.push('/chat'),
        backgroundColor: p.tint,
        foregroundColor: p.onTint,
        icon: const Icon(CupertinoIcons.chat_bubble_2_fill),
        label: Text(S.chatAsk, style: t.headline.copyWith(color: p.onTint)),
      ),
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: FsSpace.maxContent),
            child: ListView(
              padding: EdgeInsets.only(
                bottom: FsSpace.xxxl + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                // Brand row
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    FsSpace.gutter + FsSpace.xxs,
                    FsSpace.md,
                    FsSpace.xs,
                    0,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.eco_rounded, color: p.tint, size: 30),
                      const SizedBox(width: FsSpace.sm),
                      Expanded(
                        child: Text(
                          S.appName,
                          style: t.title2.copyWith(color: p.heading),
                        ),
                      ),
                      _Bell(
                        count: unread,
                        onTap: () => context.push('/notifications'),
                      ),
                    ],
                  ),
                ),
                FsEntrance(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      FsSpace.gutter + FsSpace.xxs,
                      FsSpace.lg,
                      FsSpace.gutter,
                      0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(greeting(now), style: t.largeTitle),
                        const SizedBox(height: FsSpace.xxs),
                        Text(
                          S.homeSubtitle,
                          style: t.body.copyWith(color: p.secondaryLabel),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    FsSpace.gutter,
                    FsSpace.lg,
                    FsSpace.gutter,
                    FsSpace.xs,
                  ),
                  child: Row(
                    children: [
                      FsLocationChip(label: S.myFarm, onTap: () => tabs?.go(2)),
                      const SizedBox(width: FsSpace.md),
                      const Spacer(),
                      Flexible(
                        flex: 3,
                        child: FsSavedBadge(
                          signedIn ? S.savedGoogle : S.savedPhone,
                        ),
                      ),
                    ],
                  ),
                ),
                FsEntrance(
                  index: 1,
                  child: _HeroCard(draft: d, tasks: tasks, crop: crop),
                ),
                FsSectionTitle(S.todayTasks, key: _tasksKey),
                TaskSection(now: now, startIndex: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FsSpace.gutter,
                  ),
                  child: FsGroupedSection(
                    children: [
                      FsListRow(
                        leading: Icon(Icons.checklist, color: p.tint),
                        title: 'My farm tasks & reminders',
                        onTap: () => tabs?.go(4),
                      ),
                      FsListRow(
                        leading: Icon(Icons.compare_arrows, color: p.tint),
                        title: 'Crop rotation decisions',
                        onTap: () => context.push('/rotation-plans'),
                      ),
                      FsListRow(
                        leading: Icon(Icons.history, color: p.tint),
                        title: 'Historical timeline & field evidence',
                        onTap: () => context.push('/science'),
                      ),
                      FsListRow(
                        leading: Icon(Icons.layers_outlined, color: p.tint),
                        title: 'Soil properties & map layers',
                        onTap: () => context.push('/soil-map'),
                      ),
                      FsListRow(
                        leading: Icon(Icons.info_outline, color: p.tint),
                        title: 'Sources & data',
                        onTap: () => context.push('/sources'),
                      ),
                    ],
                  ),
                ),
                const FsSectionTitle(S.yourFields),
                FsEntrance(
                  index: 6,
                  child: _FieldRow(
                    draft: d,
                    crop: crop,
                    status: status,
                    onTap: () => tabs?.go(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    FsSpace.gutter,
                    FsSpace.xxl,
                    FsSpace.gutter,
                    0,
                  ),
                  child: FsButton(
                    S.checkMyCrops,
                    icon: Icons.spa_rounded,
                    onPressed: () => context.push('/crops'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bell extends StatelessWidget {
  const _Bell({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    return Semantics(
      button: true,
      label: '${S.notifications}: $count',
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(FsSpace.minTouch),
        onPressed: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(CupertinoIcons.bell, size: 28, color: p.label),
            if (count > 0)
              Positioned(
                right: -4,
                top: -4,
                child: AnimatedScale(
                  scale: 1,
                  duration: FsMotion.of(context, FsMotion.normal),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    decoration: BoxDecoration(
                      color: p.cautionText,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$count',
                      style: context.type.caption.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The big farm card: picture (latest crop photo, else satellite), today's
/// progress ring, and what is growing / the next check.
class _HeroCard extends ConsumerWidget {
  const _HeroCard({required this.draft, required this.tasks, this.crop});
  final FarmerDraft draft;
  final List<FarmTask> tasks;
  final String? crop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.fs;
    final t = context.type;
    final total = tasks.length;
    final done = tasks.where((x) => x.done).length;
    final todo = tasks.where((x) => !x.done).toList();
    final next = todo.isEmpty ? null : todo.first;

    // The farmer's newest crop photo is the most honest picture of the field.
    final store = ref.watch(photoStoreProvider);
    File? photo;
    if (store != null) {
      final notes = [...ref.watch(notesProvider)]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      for (final n in notes) {
        if (n.photo == null) continue;
        final f = store.file(n.photo!);
        if (f.existsSync()) {
          photo = f;
          break;
        }
      }
    }
    final center = LatLng(draft.fieldLatitude!, draft.fieldLongitude!);

    return FsCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 230,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (photo != null)
                  Image.file(photo, fit: BoxFit.cover)
                else
                  FarmPicture(
                    center: center,
                    corners: draft.hasFarm ? draft.farm!.corners : null,
                  ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x55000000),
                        Color(0x00000000),
                        Color(0x99000000),
                      ],
                      stops: [0, 0.45, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: FsSpace.lg,
                  right: FsSpace.lg,
                  top: FsSpace.lg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        crop == null ? S.yourFarm : S.cropField(crop!),
                        style: t.title1.copyWith(
                          color: Colors.white,
                          shadows: const [
                            Shadow(color: Color(0x66000000), blurRadius: 8),
                          ],
                        ),
                      ),
                      const SizedBox(height: FsSpace.sm),
                      _GlassChip(
                        icon: Icons.eco_rounded,
                        label: todo.isEmpty
                            ? S.allDoneToday
                            : S.toDoToday(todo.length),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: FsSpace.lg,
                  right: FsSpace.lg,
                  bottom: FsSpace.lg,
                  child: Row(
                    children: [
                      FsProgressRing(
                        value: total == 0 ? 0 : done / total,
                        size: 64,
                        child: Icon(
                          Icons.eco_rounded,
                          color: p.positiveText,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: FsSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              S.doneOf(done, total),
                              style: t.title3.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: FsSpace.sm),
                            FsProgressBar(
                              value: total == 0 ? 0 : done / total,
                              color: const Color(0xFF4CAF50),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (photo == null)
                  const Positioned(
                    right: FsSpace.sm,
                    top: FsSpace.xs,
                    child: Text(
                      satelliteCredit,
                      style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 9),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(FsSpace.lg),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _InfoItem(
                      icon: Icons.spa_outlined,
                      label: S.growingNow,
                      value: crop ?? S.notAnswered,
                    ),
                  ),
                  VerticalDivider(color: p.separator, width: FsSpace.xl),
                  Expanded(
                    child: _InfoItem(
                      icon: CupertinoIcons.calendar,
                      label: S.nextCheck,
                      value: next == null
                          ? S.nothingDue
                          : taskShortName(next.kind),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassChip extends StatelessWidget {
  const _GlassChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: FsSpace.md,
      vertical: FsSpace.xs + 2,
    ),
    decoration: BoxDecoration(
      color: const Color(0xCC2E7D32),
      borderRadius: BorderRadius.circular(FsRadius.capsule),
      border: Border.all(color: const Color(0x55FFFFFF)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(width: FsSpace.xs + 2),
        Text(
          label,
          style: context.type.subhead.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    return Row(
      children: [
        Icon(icon, color: p.secondaryLabel, size: 24),
        const SizedBox(width: FsSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: context.type.subhead.copyWith(color: p.secondaryLabel),
              ),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.type.headline.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One row of "Your fields": thumbnail, name, status pill.
class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.draft,
    required this.crop,
    required this.status,
    required this.onTap,
  });
  final FarmerDraft draft;
  final String? crop;
  final (String, FsPillTone) status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    return FsCard(
      onTap: onTap,
      semanticLabel: S.myFarm,
      padding: const EdgeInsets.all(FsSpace.md),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(FsRadius.md),
            child: SizedBox(
              width: 76,
              height: 58,
              child: FarmPicture(
                center: LatLng(draft.fieldLatitude!, draft.fieldLongitude!),
                corners: draft.hasFarm ? draft.farm!.corners : null,
                zoom: 15,
              ),
            ),
          ),
          const SizedBox(width: FsSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.myFarm,
                  style: t.headline.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  [
                    ?crop,
                    if (draft.hasFarm) farmSizeLabel(draft.farm!),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.subhead.copyWith(color: p.secondaryLabel),
                ),
              ],
            ),
          ),
          const SizedBox(width: FsSpace.sm),
          FsStatusPill(status.$1, tone: status.$2),
          const SizedBox(width: FsSpace.xs),
          Icon(CupertinoIcons.chevron_right, size: 18, color: p.tertiaryLabel),
        ],
      ),
    );
  }
}
