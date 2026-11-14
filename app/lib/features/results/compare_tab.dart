import 'package:flutter/material.dart';

import '../../app/strings.dart';
import '../../data/models/field_analysis.dart';
import '../../design/components/page.dart';
import '../../design/components/scenario.dart';
import '../../design/components/segmented.dart';
import '../../design/tokens.dart';

/// One option at a time with a segmented switch (swipe also works),
/// instead of one long scroll of cards.
class CompareTab extends StatelessWidget {
  const CompareTab({
    super.key,
    required this.analysis,
    required this.index,
    required this.onIndexChanged,
  });

  final FieldAnalysis analysis;
  final int index;
  final ValueChanged<int> onIndexChanged;

  @override
  Widget build(BuildContext context) {
    final items = labelledScenarios(analysis.scenarios);
    if (items.isEmpty) return const SizedBox.shrink();
    final i = index.clamp(0, items.length - 1);
    final (scenario, label) = items[i];
    var alt = 0;

    return FsPage(
      title: S.tabCompare,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FsSpace.gutter,
            FsSpace.md,
            FsSpace.gutter,
            0,
          ),
          child: FsSegmented<int>(
            value: i,
            onChanged: onIndexChanged,
            segments: {
              for (final (k, (s, _)) in items.indexed)
                k: s.isBaseline ? S.current : S.option(++alt),
            },
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -300 && i < items.length - 1) onIndexChanged(i + 1);
            if (v > 300 && i > 0) onIndexChanged(i - 1);
          },
          child: AnimatedSwitcher(
            duration: FsMotion.of(context, FsMotion.normal),
            switchInCurve: FsMotion.curve,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.02),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: ScenarioDetailBody(
              key: ValueKey(scenario.id),
              scenario: scenario,
              label: label,
              analysis: analysis,
            ),
          ),
        ),
      ],
    );
  }
}
