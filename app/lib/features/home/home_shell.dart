import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'farmer_start.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/strings.dart';
import '../../data/models/field_analysis.dart';
import '../../design/components/buttons.dart';
import '../../design/components/feedback.dart';
import '../../design/components/grouped.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';
import 'field_overview.dart';
import 'home_tab.dart';
import 'notes_tab.dart';
import 'weather_tab.dart';
import '../../submission/farm_bridge.dart';

/// The app after setup: Crops home, Weather, Field, Notes and local Tasks.
/// Phones get the team's bottom
/// bar; tablets a sidebar.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with SingleTickerProviderStateMixin {
  late int _tab = widget.initialTab.clamp(0, 4);

  static const _tabs = [
    (S.tabCrops, Icons.eco_outlined, Icons.eco),
    (S.tabWeather, CupertinoIcons.cloud_sun, CupertinoIcons.cloud_sun_fill),
    (S.tabField, CupertinoIcons.map, CupertinoIcons.map_fill),
    (S.tabNotes, CupertinoIcons.doc_text, CupertinoIcons.doc_text_fill),
    ('Tasks', Icons.checklist_outlined, Icons.checklist),
  ];

  void _go(int i) {
    if (i == _tab) return;
    setState(() => _tab = i);
    _fade.forward(from: 0);
  }

  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: FsMotion.normal,
    value: 1,
  );

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // App reopened with a saved field: check it again.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(analysisProvider.notifier)
          .ensureFor(ref.read(farmerDraftProvider));
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    const pages = [
      kIsWeb ? HomeTab() : FarmerStart(),
      WeatherTab(),
      FieldTab(),
      NotesTab(),
      FarmTasksTab(),
    ];
    final reduce = context.reduceMotion;
    final body = HomeTabs(
      current: _tab,
      go: _go,
      child: AnimatedBuilder(
        animation: _fade,
        builder: (_, child) {
          final v = reduce ? 1.0 : FsMotion.curve.transform(_fade.value);
          return Opacity(
            opacity: 0.4 + 0.6 * v,
            child: Transform.translate(
              offset: Offset(0, (1 - v) * 10),
              child: child,
            ),
          );
        },
        child: IndexedStack(
          index: _tab,
          children: [
            for (var i = 0; i < pages.length; i++)
              TickerMode(enabled: i == _tab, child: pages[i]),
          ],
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= FsSpace.wideBreakpoint) {
          return Scaffold(
            backgroundColor: p.background,
            body: Row(
              children: [
                SizedBox(
                  width: 260,
                  child: SafeArea(
                    right: false,
                    child: ListView(
                      padding: const EdgeInsets.only(top: FsSpace.xl),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            FsSpace.xxl,
                            0,
                            FsSpace.lg,
                            0,
                          ),
                          child: Text(
                            S.appName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.type.title2,
                          ),
                        ),
                        FsGroupedSection(
                          separatorIndent: FsSpace.lg + 30 + FsSpace.md,
                          children: [
                            for (final (i, (label, icon, active))
                                in _tabs.indexed)
                              Container(
                                color: i == _tab ? p.tintSoft : null,
                                child: FsListRow(
                                  leading: FsIconBadge(
                                    i == _tab ? active : icon,
                                    color: i == _tab
                                        ? p.tint
                                        : p.secondaryLabel,
                                  ),
                                  title: label,
                                  titleStyle: i == _tab
                                      ? context.type.headline.copyWith(
                                          color: p.tint,
                                        )
                                      : null,
                                  chevron: false,
                                  onTap: () => _go(i),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Container(width: 0.5, color: p.separator),
                Expanded(child: body),
              ],
            ),
          );
        }
        return Scaffold(
          backgroundColor: p.background,
          body: body,
          bottomNavigationBar: _EarthTabBar(
            tabs: kIsWeb ? _tabs : const [
              ('Home', Icons.home_outlined, Icons.home),
              (S.tabWeather, CupertinoIcons.cloud_sun, CupertinoIcons.cloud_sun_fill),
              (S.tabField, CupertinoIcons.map, CupertinoIcons.map_fill),
              ('Records', CupertinoIcons.doc_text, CupertinoIcons.doc_text_fill),
              ('Tasks', Icons.checklist_outlined, Icons.checklist),
            ],
            current: _tab,
            onTap: _go,
          ),
        );
      },
    );
  }
}

/// Shows "checking…" / error / content depending on the analysis state.
class AnalysisGate extends ConsumerWidget {
  const AnalysisGate({super.key, required this.builder});
  final Widget Function(FieldAnalysis analysis, bool fromCache) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(analysisProvider);
    final draft = ref.watch(farmerDraftProvider);
    if (state is AnalysisIdle) {
      // Nothing to check without a farm pin: say so instead of spinning.
      if (!draft.hasLocation) return const NoFarmView();
      // A farm but no check yet (e.g. after Start over): start one.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(analysisProvider.notifier).ensureFor(draft),
      );
    }
    return switch (state) {
      AnalysisReady(:final analysis, :final fromCache) => builder(
        analysis,
        fromCache,
      ),
      AnalysisFailed(:final error, :final lastGood) => _Failed(
        error: error,
        hasLast: lastGood != null,
      ),
      _ => const _Preparing(),
    };
  }
}

class _Preparing extends StatelessWidget {
  const _Preparing();

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: FsSpace.maxContent),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(FsSpace.xxl),
              children: [
                Text(S.preparing, style: context.type.title1),
                const SizedBox(height: FsSpace.lg),
                const FsProgressSteps(steps: [S.step1, S.step2, S.step3]),
                const SizedBox(height: FsSpace.xxxl),
                for (var i = 0; i < 3; i++)
                  Container(
                    margin: const EdgeInsets.only(bottom: FsSpace.sm),
                    padding: const EdgeInsets.all(FsSpace.lg),
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(FsRadius.md),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FsSkeleton(width: 90, height: 12),
                        SizedBox(height: FsSpace.sm),
                        FsSkeleton(width: 200, height: 18),
                        SizedBox(height: FsSpace.sm),
                        FsSkeleton(width: 110, height: 24, radius: 12),
                      ],
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

class _Failed extends ConsumerWidget {
  const _Failed({required this.error, required this.hasLast});
  final EngineError error;
  final bool hasLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(analysisProvider.notifier);
    return Scaffold(
      backgroundColor: context.fs.background,
      body: SafeArea(
        child: FsMessageView(
          icon: CupertinoIcons.exclamationmark_triangle_fill,
          tone: FsTone.caution,
          title: S.errorTitle,
          message: error.message,
          actions: [
            FsButton(
              S.retry,
              onPressed: () => n.run(ref.read(farmerDraftProvider).toInput()),
            ),
            FsButton(
              S.useDemo,
              kind: FsButtonKind.tinted,
              onPressed: n.runDemo,
            ),
            if (hasLast)
              FsButton(
                S.showLast,
                kind: FsButtonKind.plain,
                onPressed: n.showLastGood,
              ),
          ],
        ),
      ),
    );
  }
}

class NoFarmView extends StatelessWidget {
  const NoFarmView({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.fs.background,
    body: SafeArea(
      child: FsMessageView(
        icon: CupertinoIcons.map_pin_ellipse,
        title: S.noFarmTitle,
        message: S.noFarmBody,
        actions: [
          FsButton(S.pinMyFarm, onPressed: () => context.push('/location')),
        ],
      ),
    ),
  );
}

/// Lets a tab page switch tabs (the design's back arrow on Weather/Field
/// returns to the home tab).
class HomeTabs extends InheritedWidget {
  const HomeTabs({
    super.key,
    required this.current,
    required this.go,
    required super.child,
  });
  final int current;
  final void Function(int index) go;

  static HomeTabs? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HomeTabs>();

  @override
  bool updateShouldNotify(HomeTabs old) => old.current != current;
}

/// The team design's bottom bar: icon over label, the active tab green
/// with a short bar under it.
class _EarthTabBar extends StatelessWidget {
  const _EarthTabBar({
    required this.tabs,
    required this.current,
    required this.onTap,
  });
  final List<(String, IconData, IconData)> tabs;
  final int current;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final dur = FsMotion.of(context, FsMotion.normal);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.barBackground,
        boxShadow: [
          BoxShadow(
            color: p.shadow,
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              for (final (i, (label, icon, active)) in tabs.indexed)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == current,
                    label: label,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onTap(i),
                      child: ExcludeSemantics(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedScale(
                              scale: i == current ? 1.08 : 1,
                              duration: dur,
                              curve: FsMotion.spring,
                              child: Icon(
                                i == current ? active : icon,
                                size: 27,
                                color: i == current ? p.tint : p.secondaryLabel,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              label,
                              style: context.type.caption.copyWith(
                                fontSize: 12.5,
                                color: i == current ? p.tint : p.secondaryLabel,
                                fontWeight: i == current
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            AnimatedContainer(
                              duration: dur,
                              curve: FsMotion.curve,
                              height: 3,
                              width: i == current ? 30 : 0,
                              decoration: BoxDecoration(
                                color: p.tint,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
