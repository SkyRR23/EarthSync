import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/strings.dart';
import '../../data/models/field_note.dart';
import '../../data/photos/photo_store.dart';
import '../../design/components/buttons.dart';
import '../../design/components/earth.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';
import '../../state/today.dart';
import '../today/farm_tasks.dart';

/// The farm's tasks for [now] (shared by the home screen and its tests).
List<FarmTask> watchTasks(WidgetRef ref, DateTime now) => buildTasks(
  draft: ref.watch(farmerDraftProvider),
  recent: ref.watch(recentProvider).data,
  waterLog: ref.watch(waterLogProvider),
  notes: ref.watch(notesProvider),
  marks: ref.watch(taskMarksProvider),
  now: now,
  canTakePhotos: ref.watch(photoStoreProvider) != null,
  et0: ref.watch(et0Provider).value,
);

/// Short task name for "Next check".
String taskShortName(TaskKind k) => switch (k) {
  TaskKind.heavyRain => S.shortHeavy,
  TaskKind.water => S.shortWater,
  TaskKind.soil => S.shortSoil,
  TaskKind.photo => S.shortPhoto,
};

/// A task that needs the farmer's eyes soon (shown as "Needs a look").
bool isUrgent(FarmTask t) =>
    !t.done &&
    (t.kind == TaskKind.heavyRain || t.verdict == WaterVerdict.mayNeed);

/// Today's task cards, then a "Done" card. Ticking a task feeds the app:
/// watering log, soil check, photo notes, task marks.
class TaskSection extends ConsumerStatefulWidget {
  const TaskSection({super.key, required this.now, this.startIndex = 0});
  final DateTime now;

  /// Entrance-animation position of the first card on the page.
  final int startIndex;

  @override
  ConsumerState<TaskSection> createState() => _TaskSectionState();
}

class _TaskSectionState extends ConsumerState<TaskSection> {
  bool _photoBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(recentProvider.notifier).ensureFresh();
    });
  }

  Future<void> _takePhoto() async {
    final store = ref.read(photoStoreProvider);
    if (store == null) return;
    setState(() => _photoBusy = true);
    try {
      final picked = await pickPhoto(ImageSource.camera);
      if (picked != null) {
        final id = 'crop-${DateTime.now().millisecondsSinceEpoch}';
        final name = await store.save(picked, id);
        ref
            .read(notesProvider.notifier)
            .add(NoteKind.growth, S.cropPhotoNote, photo: name, id: id);
      }
    } catch (_) {
      // Camera unavailable or permission refused: nothing is saved.
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  List<Widget> _actions(FarmTask t) {
    final now = widget.now;
    return switch (t.kind) {
      TaskKind.water => [
        FsButton(
          S.iWatered,
          icon: CupertinoIcons.drop_fill,
          onPressed: () => ref.read(waterLogProvider.notifier).logToday(now),
        ),
        const SizedBox(height: FsSpace.sm),
        FsButton(
          S.stillWet,
          kind: FsButtonKind.tinted,
          onPressed: () => ref
              .read(taskMarksProvider.notifier)
              .mark('water_ok', dayKey(dayOf(now))),
        ),
      ],
      TaskKind.heavyRain => [
        FsButton(
          S.checked,
          icon: CupertinoIcons.checkmark_alt,
          onPressed: () {
            final day = ref.read(recentProvider).data?.heaviestDay;
            if (day != null) {
              ref
                  .read(taskMarksProvider.notifier)
                  .mark('heavy_checked', dayKey(day));
            }
          },
        ),
      ],
      TaskKind.soil => [
        FsButton(
          S.startSoilCheck,
          kind: FsButtonKind.tinted,
          icon: CupertinoIcons.hand_raised_fill,
          onPressed: () => context.push('/soil-test'),
        ),
      ],
      TaskKind.photo => [
        FsButton(
          S.takePhoto,
          kind: FsButtonKind.tinted,
          icon: CupertinoIcons.camera_fill,
          loading: _photoBusy,
          onPressed: _photoBusy ? null : _takePhoto,
        ),
      ],
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    final recent = ref.watch(recentProvider);
    final tasks = watchTasks(ref, widget.now);
    final todo = [
      for (final x in tasks)
        if (!x.done) x,
    ];
    final done = [
      for (final x in tasks)
        if (x.done) x,
    ];
    final status = recent.loading && recent.data == null
        ? S.recentLoading
        : recent.failed && recent.data != null
        ? S.recentOld(shortDate(recent.data!.fetchedAt))
        : recent.failed
        ? S.recentFailed
        : null;
    var i = widget.startIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FsSpace.gutter + FsSpace.xxs,
              FsSpace.xs,
              FsSpace.gutter,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    status,
                    style: t.subhead.copyWith(color: p.secondaryLabel),
                  ),
                ),
                if (recent.failed)
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: FsSpace.sm),
                    minimumSize: const Size.square(FsSpace.minTouch),
                    onPressed: () =>
                        ref.read(recentProvider.notifier).refresh(),
                    child: Text(
                      S.retry,
                      style: t.subhead.copyWith(color: p.tint),
                    ),
                  ),
              ],
            ),
          ),
        if (todo.isEmpty)
          FsEntrance(
            index: i++,
            child: FsCard(
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.checkmark_seal_fill,
                    color: p.positiveText,
                    size: 28,
                  ),
                  const SizedBox(width: FsSpace.md),
                  Expanded(child: Text(S.todayEmpty, style: t.headline)),
                ],
              ),
            ),
          ),
        for (final task in todo)
          FsEntrance(
            index: i++,
            child: TaskCard(task: task, actions: _actions(task)),
          ),
        if (done.isNotEmpty)
          FsEntrance(
            index: i++,
            child: FsCard(
              padding: const EdgeInsets.symmetric(
                horizontal: FsSpace.lg,
                vertical: FsSpace.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: FsSpace.sm),
                    child: Text(
                      S.doneHeader,
                      style: t.footnote.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  for (final task in done)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: FsSpace.sm),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.checkmark_circle_fill,
                            color: p.positiveText,
                            size: 22,
                          ),
                          const SizedBox(width: FsSpace.md),
                          Expanded(child: Text(task.title, style: t.body)),
                          if (task.kind == TaskKind.water &&
                              task.title == S.wateredToday)
                            CupertinoButton(
                              padding: const EdgeInsets.symmetric(
                                horizontal: FsSpace.sm,
                              ),
                              minimumSize: const Size(0, FsSpace.minTouch - 10),
                              onPressed: () => ref
                                  .read(waterLogProvider.notifier)
                                  .undoToday(widget.now),
                              child: Text(
                                S.undo,
                                style: t.subhead.copyWith(color: p.tint),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One task in the design's card style.
class TaskCard extends StatelessWidget {
  const TaskCard({super.key, required this.task, required this.actions});
  final FarmTask task;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    final (IconData icon, Color fg, Color bg) = switch (task.kind) {
      TaskKind.heavyRain => (
        CupertinoIcons.cloud_heavyrain_fill,
        p.cautionText,
        p.cautionBg,
      ),
      TaskKind.water => (CupertinoIcons.drop_fill, p.rain, p.infoBg),
      TaskKind.soil => (CupertinoIcons.hand_raised_fill, p.crop2, p.neutralBg),
      TaskKind.photo => (
        CupertinoIcons.camera_fill,
        p.positiveText,
        p.positiveBg,
      ),
    };
    final titleColor = switch (task.verdict) {
      WaterVerdict.mayNeed => p.cautionText,
      WaterVerdict.canWait => p.positiveText,
      _ => p.label,
    };
    return FsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                child: Icon(icon, color: fg, size: 24),
              ),
              const SizedBox(width: FsSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        task.title,
                        style: t.title3.copyWith(
                          color: titleColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    for (final f in task.facts)
                      Padding(
                        padding: const EdgeInsets.only(top: FsSpace.xs),
                        child: Text(
                          f,
                          style: t.callout.copyWith(color: p.secondaryLabel),
                        ),
                      ),
                    if (task.source != null)
                      Padding(
                        padding: const EdgeInsets.only(top: FsSpace.sm),
                        child: Text(task.source!, style: t.footnote),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: FsSpace.lg),
          ...actions,
        ],
      ),
    );
  }
}
