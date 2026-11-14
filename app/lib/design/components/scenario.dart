import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app/strings.dart';
import '../../data/models/farmer_input.dart';
import '../../data/models/field_analysis.dart';
import '../tokens.dart';
import 'grouped.dart';
import 'status.dart';

const monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const monthShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Per-crop icon used in questions and season plans.
IconData cropIcon(String id) => switch (id) {
  'rice' => Icons.grass_rounded,
  'mung_bean' || 'black_gram' || 'chickpea' => Icons.spa_outlined,
  'groundnut' || 'sesame' => Icons.grain_rounded,
  'maize' => Icons.agriculture_outlined,
  'vegetables' => Icons.eco_outlined,
  'fallow' => Icons.landscape_outlined,
  _ => Icons.grass_rounded,
};

const _monthLetters = [
  'J',
  'F',
  'M',
  'A',
  'M',
  'J',
  'J',
  'A',
  'S',
  'O',
  'N',
  'D',
];

/// "Your current practice" / "Option 1" … in the engine's order.
List<(RotationScenario, String)> labelledScenarios(
  List<RotationScenario> list,
) {
  var alt = 0;
  return [
    for (final s in list) (s, s.isBaseline ? S.yourPractice : S.option(++alt)),
  ];
}

/// Month runs for a window, split when it wraps the year: Nov–Feb → [10..11], [0..1].
List<(int, int)> _runs(int start, int end) =>
    start <= end ? [(start - 1, end - 1)] : [(start - 1, 11), (0, end - 1)];

String stepWindowText(RotationStep s) {
  if (s.startMonth == null || s.endMonth == null) return S.windowUnknown;
  return '${monthShort[s.startMonth! - 1]} – ${monthShort[s.endMonth! - 1]}';
}

/// Gantt-style season plan: one row per crop step on a 12-month track.
/// Handles overlapping and year-wrapping windows.
class FsTimeline extends StatelessWidget {
  const FsTimeline(this.steps, {super.key});
  final List<RotationStep> steps;

  static const _labelWidth = 96.0;
  static const _trackHeight = 22.0;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    final summary = steps
        .map((s) => '${Crops.label(s.cropId)}: ${stepWindowText(s)}')
        .join('. ');

    return Semantics(
      label: '${S.timeline}. $summary',
      excludeSemantics: true,
      child: Column(
        children: [
          for (final (i, s) in steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: FsSpace.sm),
              child: Row(
                children: [
                  SizedBox(
                    width: _labelWidth,
                    child: Text(
                      Crops.label(s.cropId),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.footnote.copyWith(
                        color: p.label,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (_, c) {
                        final w = c.maxWidth;
                        final color = p.cropColors[i % p.cropColors.length];
                        final fill = s.cropId == 'fallow'
                            ? color.withValues(alpha: 0.28)
                            : color;
                        return Container(
                          height: _trackHeight,
                          decoration: BoxDecoration(
                            color: p.fill,
                            borderRadius: BorderRadius.circular(FsRadius.xs),
                          ),
                          child: s.startMonth == null || s.endMonth == null
                              ? Center(
                                  child: Text(
                                    S.windowUnknown,
                                    style: t.caption.copyWith(
                                      color: p.tertiaryLabel,
                                    ),
                                  ),
                                )
                              : Stack(
                                  children: [
                                    for (final (a, b) in _runs(
                                      s.startMonth!,
                                      s.endMonth!,
                                    ))
                                      Positioned(
                                        left: a / 12 * w + 1,
                                        width: (b - a + 1) / 12 * w - 2,
                                        top: 0,
                                        bottom: 0,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: fill,
                                            borderRadius: BorderRadius.circular(
                                              FsRadius.xs,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              const SizedBox(width: _labelWidth),
              for (final l in _monthLetters)
                Expanded(
                  child: Text(
                    l,
                    textAlign: TextAlign.center,
                    style: t.caption.copyWith(color: p.tertiaryLabel),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Summary row for a scenario (Overview list, sidebars).
class FsScenarioRow extends StatelessWidget {
  const FsScenarioRow({
    super.key,
    required this.scenario,
    required this.label,
    required this.onTap,
  });

  final RotationScenario scenario;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final risk = scenario.risks.firstOrNull;
    return FsListRow(
      overline: label,
      title: scenario.title,
      titleStyle: context.type.headline,
      onTap: onTap,
      below: Wrap(
        spacing: FsSpace.sm,
        runSpacing: FsSpace.xs + 2,
        children: [
          FsFeasibilityLabel(scenario.eligibility),
          if (risk != null) FsRiskLabel(hazard: risk.hazard, level: risk.level),
        ],
      ),
    );
  }
}

/// Full scenario content — used by the detail screen and the Compare tab.
class ScenarioDetailBody extends StatelessWidget {
  const ScenarioDetailBody({
    super.key,
    required this.scenario,
    required this.label,
    required this.analysis,
    this.showHeader = true,
  });

  final RotationScenario scenario;
  final String label;
  final FieldAnalysis analysis;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    final s = scenario;
    final refs = [for (final id in s.evidenceIds) ?analysis.reference(id)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FsSpace.gutter + FsSpace.xs,
              FsSpace.lg,
              FsSpace.gutter,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: t.footnote),
                const SizedBox(height: FsSpace.xxs),
                Text(s.title, style: t.title2),
                const SizedBox(height: FsSpace.sm),
                FsFeasibilityLabel(s.eligibility),
              ],
            ),
          ),
        FsGroupedSection(
          header: S.timeline,
          padded: true,
          children: [FsTimeline(s.steps)],
        ),
        FsGroupedSection(
          separatorIndent: FsSpace.lg + 22 + FsSpace.md,
          children: [
            for (final step in s.steps)
              FsListRow(
                leading: Icon(
                  cropIcon(step.cropId),
                  color: p.secondaryLabel,
                  size: 22,
                ),
                title: Crops.label(step.cropId),
                subtitle: stepWindowText(step),
                below: FsFeasibilityLabel(step.feasibility),
              ),
          ],
        ),
        FsGroupedSection(
          header: S.benefits,
          separatorIndent: FsSpace.lg + 22 + FsSpace.md,
          footer: s.likelyBenefits.isEmpty ? S.noBenefits : null,
          children: [
            for (final b in s.likelyBenefits)
              FsListRow(
                leading: Icon(
                  CupertinoIcons.checkmark_circle,
                  color: p.positiveText,
                  size: 22,
                ),
                title: b,
              ),
          ],
        ),
        FsGroupedSection(
          header: S.risks,
          footer: s.risks.isEmpty ? S.noRisks : null,
          children: [
            for (final r in s.risks)
              FsListRow(
                title: hazardLabel(r.hazard),
                titleStyle: t.headline,
                subtitle: r.note.isEmpty ? null : r.note,
                below: r.level == null
                    ? null
                    : FsRiskLabel(hazard: r.hazard, level: r.level),
              ),
          ],
        ),
        if (s.limitations.isNotEmpty)
          FsGroupedSection(
            header: S.limitations,
            separatorIndent: FsSpace.lg + 22 + FsSpace.md,
            children: [
              for (final l in s.limitations)
                FsListRow(
                  leading: Icon(
                    CupertinoIcons.info_circle,
                    color: p.secondaryLabel,
                    size: 22,
                  ),
                  title: l,
                  titleStyle: t.callout,
                ),
            ],
          ),
        if (refs.isNotEmpty)
          FsGroupedSection(
            header: S.evidence,
            separatorIndent: FsSpace.lg + 22 + FsSpace.md,
            children: [for (final r in refs) FsEvidenceRow(r)],
          ),
      ],
    );
  }
}
