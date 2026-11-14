import 'package:flutter/material.dart';

import '../../app/strings.dart';
import '../../data/models/farmer_input.dart';
import '../../data/models/field_analysis.dart';
import '../tokens.dart';
import 'badges.dart';
import 'feedback.dart';

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

const _stepColors = [
  FsColors.primary,
  FsColors.earth,
  FsColors.sky,
  FsColors.evidenceModel,
];

/// Fallow is a pale tint so "empty field" reads differently from a crop.
Color _cellColor(RotationStep s, int i) {
  final c = _stepColors[i % _stepColors.length];
  return s.cropId == 'fallow' ? c.withValues(alpha: 0.25) : c;
}

bool _covers(RotationStep s, int m) {
  final a = s.startMonth, b = s.endMonth;
  if (a == null || b == null) return false;
  return a <= b ? (m >= a && m <= b) : (m >= a || m <= b);
}

/// 12-month strip showing when each crop is in the field.
class FsRotationTimeline extends StatelessWidget {
  const FsRotationTimeline(this.steps, {super.key});
  final List<RotationStep> steps;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final summary = steps
        .map(
          (s) => s.startMonth == null
              ? '${Crops.label(s.cropId)}: planting window unknown'
              : '${Crops.label(s.cropId)}: ${monthNames[s.startMonth! - 1]} to ${monthNames[s.endMonth! - 1]}',
        )
        .join('. ');

    return Semantics(
      label: summary,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var m = 1; m <= 12; m++)
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        height: 28,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: _colorFor(m),
                          borderRadius: const BorderRadius.all(
                            Radius.circular(4),
                          ),
                          border: Border.all(color: FsColors.border),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(_monthLetters[m - 1], style: t.bodySmall),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: FsSpace.sm),
          Wrap(
            spacing: FsSpace.md,
            runSpacing: FsSpace.xs,
            children: [
              for (var i = 0; i < steps.length; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: steps[i].startMonth == null
                            ? null
                            : _cellColor(steps[i], i),
                        border: Border.all(
                          color: steps[i].startMonth == null
                              ? FsColors.unknown
                              : Colors.transparent,
                        ),
                        borderRadius: const BorderRadius.all(
                          Radius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(width: FsSpace.xs),
                    Text(
                      steps[i].startMonth == null
                          ? '${Crops.label(steps[i].cropId)} (${S.unknown.toLowerCase()} window)'
                          : Crops.label(steps[i].cropId),
                      style: t.bodyMedium,
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color _colorFor(int m) {
    for (var i = 0; i < steps.length; i++) {
      if (_covers(steps[i], m)) {
        return _cellColor(steps[i], i);
      }
    }
    return FsColors.surface;
  }
}

/// One rotation strategy. Deliberately has no slot for yields or percentages.
class FsScenarioCard extends StatelessWidget {
  const FsScenarioCard({
    super.key,
    required this.scenario,
    required this.optionNumber,
    this.onOpenDetail,
  });

  final RotationScenario scenario;

  /// 0 for baseline, 1..n for alternatives.
  final int optionNumber;
  final VoidCallback? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final eyebrow = scenario.isBaseline
        ? S.yourPractice
        : '${S.option} $optionNumber';
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(FsRadius.lg),
        side: BorderSide(
          color: scenario.isBaseline ? FsColors.textSecondary : FsColors.border,
          width: scenario.isBaseline ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: const BorderRadius.all(FsRadius.lg),
        onTap: onOpenDetail,
        child: Padding(
          padding: const EdgeInsets.all(FsSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: t.bodySmall?.copyWith(
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: FsSpace.xs),
              Text(scenario.title, style: t.titleLarge),
              const SizedBox(height: FsSpace.sm),
              FsFeasibilityBadge(scenario.eligibility),
              const SizedBox(height: FsSpace.md),
              FsRotationTimeline(scenario.steps),
              if (scenario.likelyBenefits.isNotEmpty) ...[
                const SizedBox(height: FsSpace.md),
                Text(S.benefits, style: t.labelLarge),
                const SizedBox(height: FsSpace.xs),
                FsBulletList(
                  scenario.likelyBenefits,
                  icon: Icons.check,
                  color: FsColors.supported,
                ),
              ],
              if (scenario.risks.isNotEmpty) ...[
                const SizedBox(height: FsSpace.sm),
                Text(S.risks, style: t.labelLarge),
                const SizedBox(height: FsSpace.xs),
                Wrap(
                  spacing: FsSpace.sm,
                  runSpacing: FsSpace.sm,
                  children: [
                    for (final r in scenario.risks)
                      FsRiskBadge(hazard: r.hazard, level: r.level),
                  ],
                ),
              ],
              if (onOpenDetail != null) ...[
                const SizedBox(height: FsSpace.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: onOpenDetail,
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.chevron_right),
                    label: const Text(S.seeDetails),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
