import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/strings.dart';
import '../../data/models/field_analysis.dart';
import '../../design/components/buttons.dart';
import '../../design/components/feedback.dart';
import '../../design/components/grouped.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';
import 'climate_tab.dart';
import 'compare_tab.dart';
import 'map_tab.dart';
import 'overview_tab.dart';

/// Analysis state machine: preparing -> results (tabs / sidebar) | error.
class ResultsScreen extends ConsumerStatefulWidget {
  const ResultsScreen({super.key});

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen> {
  int _tab = 0;
  int _compareIndex = 0;

  static const _tabs = [
    (
      S.tabOverview,
      CupertinoIcons.square_grid_2x2,
      CupertinoIcons.square_grid_2x2_fill,
    ),
    (S.tabMap, CupertinoIcons.map, CupertinoIcons.map_fill),
    (
      S.tabClimate,
      CupertinoIcons.cloud_sun_rain,
      CupertinoIcons.cloud_sun_rain_fill,
    ),
    (
      S.tabCompare,
      CupertinoIcons.arrow_right_arrow_left,
      CupertinoIcons.arrow_right_arrow_left,
    ),
  ];

  void _openCompare([int index = 0]) => setState(() {
    _compareIndex = index;
    _tab = 3;
  });

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(analysisProvider);
    return switch (state) {
      AnalysisIdle() || AnalysisRunning() => const _Preparing(),
      AnalysisFailed(:final error, :final lastGood) => _Failed(
        error: error,
        hasLast: lastGood != null,
      ),
      AnalysisReady(:final analysis, :final fromCache) => _ready(
        analysis,
        fromCache,
      ),
    };
  }

  Widget _ready(FieldAnalysis a, bool fromCache) {
    final pages = [
      OverviewTab(analysis: a, fromCache: fromCache, onCompare: _openCompare),
      MapTab(analysis: a),
      ClimateTab(analysis: a),
      CompareTab(
        analysis: a,
        index: _compareIndex,
        onIndexChanged: (i) => setState(() => _compareIndex = i),
      ),
    ];
    final p = context.fs;

    return LayoutBuilder(
      builder: (context, c) {
        final body = IndexedStack(index: _tab, children: pages);

        // Tablets / desktop: sidebar instead of a stretched tab bar.
        if (c.maxWidth >= FsSpace.wideBreakpoint) {
          return Scaffold(
            backgroundColor: p.background,
            body: Row(
              children: [
                SizedBox(
                  width: 280,
                  child: SafeArea(
                    right: false,
                    child: ListView(
                      padding: const EdgeInsets.only(top: FsSpace.lg),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            FsSpace.xl,
                            FsSpace.lg,
                            FsSpace.lg,
                            0,
                          ),
                          child: Row(
                            children: [
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size.square(
                                  FsSpace.minTouch,
                                ),
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                                child: Icon(
                                  CupertinoIcons.chevron_back,
                                  color: p.tint,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  S.appName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.type.title2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        FsGroupedSection(
                          separatorIndent: FsSpace.lg + 30 + FsSpace.md,
                          children: [
                            for (final (i, (label, icon, _)) in _tabs.indexed)
                              Container(
                                color: i == _tab ? p.tintSoft : null,
                                child: FsListRow(
                                  leading: FsIconBadge(
                                    icon,
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
                                  onTap: () => setState(() => _tab = i),
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
          bottomNavigationBar: CupertinoTabBar(
            currentIndex: _tab,
            onTap: (i) => setState(() => _tab = i),
            activeColor: p.tint,
            inactiveColor: p.secondaryLabel,
            backgroundColor: p.barBackground,
            border: Border(top: BorderSide(color: p.separator, width: 0.5)),
            height: 54,
            items: [
              for (final (label, icon, active) in _tabs)
                BottomNavigationBarItem(
                  icon: Icon(icon),
                  activeIcon: Icon(active),
                  label: label,
                ),
            ],
          ),
        );
      },
    );
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
                Text(S.analyzingTitle, style: context.type.title1),
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
                        FsSkeleton(width: 130, height: 22, radius: 11),
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
    final p = context.fs;
    final n = ref.read(analysisProvider.notifier);
    return Scaffold(
      backgroundColor: p.background,
      appBar: CupertinoNavigationBar(
        previousPageTitle: S.back,
        backgroundColor: p.barBackground,
        border: null,
        transitionBetweenRoutes: false,
      ),
      body: FsMessageView(
        icon: CupertinoIcons.exclamationmark_triangle_fill,
        tone: FsTone.caution,
        title: S.errorTitle,
        message: error.message,
        actions: [
          if (error.retryable)
            FsButton(
              S.retry,
              onPressed: () => n.run(ref.read(farmerDraftProvider).toInput()),
            ),
          FsButton(
            S.useDemo,
            kind: error.retryable ? FsButtonKind.tinted : FsButtonKind.filled,
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
    );
  }
}
