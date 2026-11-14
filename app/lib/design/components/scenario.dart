import 'package:flutter/cupertino.dart';

import '../../app/strings.dart';
import '../../data/models/farmer_input.dart';
import '../../data/models/field_analysis.dart';
import '../tokens.dart';
import 'grouped.dart';
import 'status.dart';

const monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const monthShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _monthLetters = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];

/// Picture for each crop — easier to recognise than words.
String cropEmoji(String id) => switch (id) {
  'rice' => '🌾',
  'mung_bean' || 'black_gram' || 'chickpea' => '🫘',
  'groundnut' => '🥜',
  'sesame' => '🌻',
  'maize' => '🌽',
  'vegetables' => '🥬',
  'fallow' => '🟫',
  _ => '🌱',
};

/// Short crop sequence, e.g. "🌾 Rice → 🫘 Mung bean".
String cropSequence(RotationScenario s) =>
    s.steps.map((st) => '${cropEmoji(st.cropId)} ${Crops.label(st.cropId)}').join('  →  ');

/// "What you grow now" / "Other plan 1" … in the engine's order.
List<(RotationScenario, String, String)> labelledScenarios(List<RotationScenario> list) {
  var alt = 0;
  return [
    for (final s in list)
      s.isBaseline
          ? (s, S.whatYouGrowNow, S.now)
          : () {
              alt++;
              return (s, S.planLong(alt), S.plan(alt));
            }(),
  ];
}

/// Month runs for a window, split when it wraps the year: Nov–Feb → [10..11], [0..1].
List<(int, int)> _runs(int start, int end) => start <= end
    ? [(start - 1, end - 1)]
    : [(start - 1, 11), (0, end - 1)];

String stepWindowText(RotationStep s) {
  if (s.startMonth == null || s.endMonth == null) return S.windowUnknown;
  return '${monthShort[s.startMonth! - 1]} – ${monthShort[s.endMonth! - 1]}';
}

/// Year strip: one row per crop, coloured where it is in the field.
class FsTimeline extends StatelessWidget {
  const FsTimeline(this.steps, {super.key});
  final List<RotationStep> steps;

  static const _labelWidth = 110.0;
  static const _trackHeight = 26.0;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    final summary = steps
        .map((s) => '${Crops.label(s.cropId)}: ${stepWindowText(s)}')
        .join('. ');

    return Semantics(
      label: '${S.when}. $summary',
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
                      '${cropEmoji(s.cropId)} ${Crops.label(s.cropId)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.subhead.copyWith(fontWeight: FontWeight.w500),
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
                                    style: t.caption.copyWith(color: p.tertiaryLabel),
                                  ),
                                )
                              : Stack(
                                  children: [
                                    for (final (a, b) in _runs(s.startMonth!, s.endMonth!))
                                      Positioned(
                                        left: a / 12 * w + 1,
                                        width: (b - a + 1) / 12 * w - 2,
                                        top: 0,
                                        bottom: 0,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: fill,
                                            borderRadius: BorderRadius.circular(FsRadius.xs),
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

/// One plan as a big, simple row (Home).
class FsPlanRow extends StatelessWidget {
  const FsPlanRow({
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
      title: cropSequence(scenario),
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

/// Everything about one plan, in plain sections.
class ScenarioDetailBody extends StatelessWidget {
  const ScenarioDetailBody({
    super.key,
    required this.scenario,
    required this.label,
    required this.analysis,
  });

  final RotationScenario scenario;
  final String label;
  final FieldAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    final s = scenario;
    final refs = [
      for (final id in s.evidenceIds) ?analysis.reference(id),
    ];
    const iconIndent = FsSpace.lg + 22 + FsSpace.md;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FsSpace.gutter + FsSpace.xs,
            FsSpace.xl,
            FsSpace.gutter,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: t.footnote),
              const SizedBox(height: FsSpace.xs),
              Text(cropSequence(s), style: t.title2),
              const SizedBox(height: FsSpace.md),
              Transform.scale(
                scale: 1.15,
                alignment: Alignment.centerLeft,
                child: FsFeasibilityLabel(s.eligibility),
              ),
              const SizedBox(height: FsSpace.sm),
              Text(S.fitNote, style: t.footnote),
            ],
          ),
        ),
        FsGroupedSection(header: S.when, padded: true, children: [FsTimeline(s.steps)]),
        FsGroupedSection(
          header: S.good,
          separatorIndent: iconIndent,
          footer: s.likelyBenefits.isEmpty ? S.noneYet : null,
          children: [
            for (final b in s.likelyBenefits)
              FsListRow(
                leading: Icon(CupertinoIcons.hand_thumbsup_fill, color: p.positiveText, size: 22),
                title: b,
              ),
          ],
        ),
        FsGroupedSection(
          header: S.watchOut,
          separatorIndent: iconIndent,
          footer: s.risks.isEmpty ? S.noWarnings : null,
          children: [
            for (final r in s.risks)
              FsListRow(
                leading: Icon(hazardIcon(r.hazard), color: p.tone(riskTone(r.level)).$1, size: 22),
                title: hazardLabel(r.hazard),
                titleStyle: t.headline,
                subtitle: r.note.isEmpty ? null : r.note,
                below: r.level == null ? null : FsRiskLabel(hazard: r.hazard, level: r.level),
              ),
          ],
        ),
        if (s.limitations.isNotEmpty)
          FsGroupedSection(
            header: S.dontKnowYet,
            separatorIndent: iconIndent,
            children: [
              for (final l in s.limitations)
                FsListRow(
                  leading: Icon(CupertinoIcons.question_circle, color: p.secondaryLabel, size: 22),
                  title: l,
                  titleStyle: t.callout,
                ),
            ],
          ),
        if (refs.isNotEmpty)
          FsGroupedSection(
            header: S.whereFrom,
            separatorIndent: iconIndent,
            children: [for (final r in refs) FsEvidenceRow(r)],
          ),
      ],
    );
  }
}
