import 'package:flutter/cupertino.dart';

import '../../app/strings.dart';
import '../../data/models/farmer_input.dart';
import '../../data/models/field_analysis.dart';
import '../tokens.dart';
import 'grouped.dart';
import 'pressable.dart';
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

/// Picture for each crop — easier to recognise than words.
String cropEmoji(String? id) => switch (id) {
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
String cropSequence(RotationScenario s) => s.steps
    .map((st) => '${cropEmoji(st.cropId)} ${Crops.label(st.cropId)}')
    .join('  →  ');

/// "What you grow now" / "Other plan 1" … in the engine's order.
List<(RotationScenario, String, String)> labelledScenarios(
  List<RotationScenario> list,
) {
  var alt = 0;
  return [
    for (final s in list)
      s.isBaseline
          ? (s, S.whatYouGrowNow, 'Now')
          : () {
              alt++;
              return (s, S.planLong(alt), 'Plan $alt');
            }(),
  ];
}

int _fitRank(Feasibility f) => switch (f) {
  Feasibility.supported => 0,
  Feasibility.constrained => 1,
  Feasibility.unknown => 2,
  Feasibility.conflicts => 3,
};

/// Best fit first (Good fit, Careful, Not sure, Poor fit). Only re-orders the
/// engine's own verdicts — nothing is scored in Flutter.
List<(RotationScenario, String, String)> sortedByFit(
  List<RotationScenario> list,
) {
  final items = labelledScenarios(list).indexed.toList()
    ..sort((a, b) {
      final r = _fitRank(
        a.$2.$1.eligibility,
      ).compareTo(_fitRank(b.$2.$1.eligibility));
      return r != 0 ? r : a.$1.compareTo(b.$1);
    });
  return [for (final (_, e) in items) e];
}

/// "Rice, then Mung bean".
String cropNames(RotationScenario s) =>
    s.steps.map((st) => Crops.label(st.cropId)).join(', ${S.then} ');

/// "🌾 → 🫘".
String cropPictures(RotationScenario s) =>
    s.steps.map((st) => cropEmoji(st.cropId)).join(' → ');

/// Month runs for a window, split when it wraps the year: Nov–Feb → [10..11], [0..1].
List<(int, int)> _runs(int start, int end) =>
    start <= end ? [(start - 1, end - 1)] : [(start - 1, 11), (0, end - 1)];

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

/// One crop plan as a big card: pictures, names, traffic-light fit word.
class FsCropCard extends StatelessWidget {
  const FsCropCard({
    super.key,
    required this.scenario,
    required this.onTap,
    this.highlight = false,
  });

  final RotationScenario scenario;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    final s = scenario;
    final (fit, _, _) = feasibilityStyle(s.eligibility);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FsSpace.gutter,
        0,
        FsSpace.gutter,
        FsSpace.md,
      ),
      child: Semantics(
        button: true,
        label:
            '${s.isBaseline ? '${S.whatYouGrowNow}. ' : ''}${cropNames(s)}. $fit',
        excludeSemantics: true,
        child: FsPressable(
          onTap: onTap,
          scale: 0.98,
          child: Container(
            padding: const EdgeInsets.all(FsSpace.lg),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(FsRadius.lg),
              border: Border.all(
                color: highlight ? p.positiveText : p.separator,
                width: highlight ? 2.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (s.isBaseline) ...[
                        Text(S.whatYouGrowNow, style: t.footnote),
                        const SizedBox(height: FsSpace.xxs),
                      ],
                      Text(
                        cropPictures(s),
                        style: const TextStyle(fontSize: 34, height: 1.15),
                      ),
                      const SizedBox(height: FsSpace.xs),
                      Text(cropNames(s), style: t.title3),
                      const SizedBox(height: FsSpace.md),
                      Transform.scale(
                        scale: 1.2,
                        alignment: Alignment.centerLeft,
                        child: FsFeasibilityLabel(s.eligibility),
                      ),
                    ],
                  ),
                ),
                Icon(
                  CupertinoIcons.chevron_forward,
                  color: p.tertiaryLabel,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Everything about one plan, in plain sections.
/// [compact] = bottom-sheet version: at most 3 lines per section, no sources.
class ScenarioDetailBody extends StatelessWidget {
  const ScenarioDetailBody({
    super.key,
    required this.scenario,
    required this.label,
    required this.analysis,
    this.compact = false,
  });

  final RotationScenario scenario;
  final String label;
  final FieldAnalysis analysis;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    final s = scenario;
    final refs = compact
        ? const <Reference>[]
        : [for (final id in s.evidenceIds) ?analysis.reference(id)];
    final max = compact ? 3 : 99;
    final benefits = s.likelyBenefits.take(max).toList();
    final risks = s.risks.take(max).toList();
    final unknowns = s.limitations.take(compact ? 2 : 99).toList();
    const iconIndent = FsSpace.lg + 22 + FsSpace.md;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            FsSpace.gutter + FsSpace.xs,
            compact ? FsSpace.xs : FsSpace.xl,
            FsSpace.gutter,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!compact) ...[
                Text(label, style: t.footnote),
                const SizedBox(height: FsSpace.xs),
              ],
              Text(
                cropPictures(s),
                style: const TextStyle(fontSize: 40, height: 1.15),
              ),
              const SizedBox(height: FsSpace.xs),
              Text(cropNames(s), style: t.title2),
              const SizedBox(height: FsSpace.md),
              Transform.scale(
                scale: 1.2,
                alignment: Alignment.centerLeft,
                child: FsFeasibilityLabel(s.eligibility),
              ),
              const SizedBox(height: FsSpace.sm),
              Text(S.fitNote, style: t.footnote),
            ],
          ),
        ),
        FsGroupedSection(
          header: S.when,
          separatorIndent: iconIndent,
          children: [
            for (final st in s.steps)
              FsListRow(
                leading: Text(
                  cropEmoji(st.cropId),
                  style: const TextStyle(fontSize: 22),
                ),
                title: Crops.label(st.cropId),
                value: stepWindowText(st),
              ),
          ],
        ),
        FsGroupedSection(
          header: S.whyGood,
          separatorIndent: iconIndent,
          footer: benefits.isEmpty ? S.noneYet : null,
          children: [
            for (final b in benefits)
              FsListRow(
                leading: Icon(
                  CupertinoIcons.hand_thumbsup_fill,
                  color: p.positiveText,
                  size: 22,
                ),
                title: b,
              ),
          ],
        ),
        if (risks.isNotEmpty)
          FsGroupedSection(
            header: S.watchOut,
            separatorIndent: iconIndent,
            children: [
              for (final r in risks)
                FsListRow(
                  leading: Icon(
                    hazardIcon(r.hazard),
                    color: p.tone(riskTone(r.level)).$1,
                    size: 22,
                  ),
                  title: hazardLabel(r.hazard),
                  titleStyle: t.headline,
                  subtitle: r.note.isEmpty ? null : r.note,
                ),
            ],
          ),
        if (unknowns.isNotEmpty)
          FsGroupedSection(
            header: S.dontKnowYet,
            separatorIndent: iconIndent,
            children: [
              for (final l in unknowns)
                FsListRow(
                  leading: Icon(
                    CupertinoIcons.question_circle,
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
            header: S.whereFrom,
            separatorIndent: iconIndent,
            children: [for (final r in refs) FsEvidenceRow(r)],
          ),
      ],
    );
  }
}
