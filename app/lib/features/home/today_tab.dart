import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/strings.dart';
import '../../data/models/farm_boundary.dart';
import '../../data/models/field_note.dart';
import '../../data/photos/photo_store.dart';
import '../../design/components/buttons.dart';
import '../../design/components/grouped.dart';
import '../../design/components/page.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';
import '../../state/today.dart';
import '../today/farm_tasks.dart';
import 'home_shell.dart' show NoFarmView;

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Today tab: what to do on the farm now. Each task says why (data + the
/// farmer's own records), and ticking it feeds the rest of the app.
class TodayTab extends ConsumerStatefulWidget {
  const TodayTab({super.key, this.now});

  /// Fixed clock for tests.
  final DateTime? now;

  @override
  ConsumerState<TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends ConsumerState<TodayTab> {
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

  List<Widget> _actions(FarmTask t, DateTime now) => switch (t.kind) {
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
        kind: FsButtonKind.tinted,
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
        onPressed: () => context.push('/soil-test'),
      ),
    ],
    TaskKind.photo => [
      FsButton(
        S.takePhoto,
        kind: FsButtonKind.tinted,
        icon: CupertinoIcons.camera,
        loading: _photoBusy,
        onPressed: _photoBusy ? null : _takePhoto,
      ),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(farmerDraftProvider);
    if (d.fieldLatitude == null) return const NoFarmView();
    final p = context.fs;
    final t = context.type;
    final now = widget.now ?? DateTime.now();
    final recent = ref.watch(recentProvider);
    final tasks = buildTasks(
      draft: d,
      recent: recent.data,
      waterLog: ref.watch(waterLogProvider),
      notes: ref.watch(notesProvider),
      marks: ref.watch(taskMarksProvider),
      now: now,
      canTakePhotos: ref.watch(photoStoreProvider) != null,
    );
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

    return FsPage(
      title: S.tabToday,
      showBack: false,
      subtitle: [
        '${_weekdays[now.weekday - 1]} ${shortDate(now)}',
        if (d.hasFarm) farmSizeLabel(d.farm!),
      ].join(' · '),
      children: [
        if (status != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FsSpace.gutter,
              FsSpace.md,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FsSpace.gutter,
              FsSpace.xl,
              FsSpace.gutter,
              0,
            ),
            child: Text(S.todayEmpty, style: t.body),
          ),
        for (final task in todo)
          _TaskCard(task: task, actions: _actions(task, now)),
        if (done.isNotEmpty) ...[
          const SizedBox(height: FsSpace.xl),
          FsGroupedSection(
            header: S.doneHeader,
            children: [
              for (final task in done)
                FsListRow(
                  leading: Icon(
                    CupertinoIcons.checkmark_circle_fill,
                    color: p.positiveText,
                  ),
                  title: task.title,
                  titleMaxLines: 2,
                  trailing:
                      task.kind == TaskKind.water &&
                          task.title == S.wateredToday
                      ? CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size.square(FsSpace.minTouch),
                          onPressed: () => ref
                              .read(waterLogProvider.notifier)
                              .undoToday(now),
                          child: Text(
                            S.undo,
                            style: t.subhead.copyWith(color: p.tint),
                          ),
                        )
                      : null,
                ),
            ],
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FsSpace.gutter,
            FsSpace.lg,
            FsSpace.gutter,
            0,
          ),
          child: Text(
            S.todayFooter,
            style: t.footnote.copyWith(color: p.secondaryLabel),
          ),
        ),
      ],
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.actions});
  final FarmTask task;
  final List<Widget> actions;

  static String _emoji(TaskKind k) => switch (k) {
    TaskKind.heavyRain => '🌧️',
    TaskKind.water => '💧',
    TaskKind.soil => '🤲',
    TaskKind.photo => '📷',
  };

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    final accent = switch (task.verdict) {
      WaterVerdict.mayNeed => p.cautionText,
      WaterVerdict.canWait => p.positiveText,
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FsSpace.gutter,
        FsSpace.lg,
        FsSpace.gutter,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(FsSpace.lg),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(FsRadius.lg),
          border: Border.all(color: p.separator),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(_emoji(task.kind), style: const TextStyle(fontSize: 30)),
                const SizedBox(width: FsSpace.md),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      task.title,
                      style: t.title3.copyWith(color: accent),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: FsSpace.sm),
            for (final f in task.facts)
              Padding(
                padding: const EdgeInsets.only(top: FsSpace.xs),
                child: Text(f, style: t.body),
              ),
            if (task.source != null) ...[
              const SizedBox(height: FsSpace.sm),
              Text(
                task.source!,
                style: t.footnote.copyWith(color: p.secondaryLabel),
              ),
            ],
            const SizedBox(height: FsSpace.lg),
            ...actions,
          ],
        ),
      ),
    );
  }
}
