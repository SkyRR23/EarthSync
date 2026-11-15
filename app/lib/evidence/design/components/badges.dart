import 'package:flutter/material.dart';

import '../../app/strings.dart';
import '../../data/models/field_analysis.dart';
import '../tokens.dart';

/// Icon + word + colour. Never colour alone.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.color,
    required this.icon,
    required this.label,
    this.semantic,
  });
  final Color color;
  final IconData icon;
  final String label;
  final String? semantic;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semantic ?? label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FsSpace.sm,
          vertical: FsSpace.xs,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          border: Border.all(color: color),
          borderRadius: const BorderRadius.all(FsRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: FsSpace.xs),
            Flexible(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: color, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FsFeasibilityBadge extends StatelessWidget {
  const FsFeasibilityBadge(this.value, {super.key});
  final Feasibility value;

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (value) {
      Feasibility.supported => (
        FsColors.supported,
        Icons.check_circle,
        S.supported,
      ),
      Feasibility.constrained => (
        FsColors.constrained,
        Icons.warning_amber,
        S.constrained,
      ),
      Feasibility.conflicts => (
        FsColors.riskHigh,
        Icons.cancel_outlined,
        S.conflicts,
      ),
      Feasibility.unknown => (FsColors.unknown, Icons.help_outline, S.unknown),
    };
    return _Pill(
      color: color,
      icon: icon,
      label: label,
      semantic: 'Status: $label',
    );
  }
}

String hazardLabel(String hazard) => switch (hazard) {
  'drought' => 'Drought',
  'heat' => 'Heat',
  'waterlogging' => 'Waterlogging',
  'flood' => 'Flood',
  'storm' => 'Storm',
  _ => _humanize(hazard),
};

/// Engine codes like "rotation_rules" -> "Rotation rules".
String _humanize(String code) {
  final s = code.replaceAll('_', ' ').trim();
  return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();
}

IconData hazardIcon(String hazard) => switch (hazard) {
  'drought' => Icons.wb_sunny_outlined,
  'heat' => Icons.thermostat,
  'waterlogging' || 'flood' => Icons.water,
  'storm' => Icons.thunderstorm_outlined,
  _ => Icons.report_outlined,
};

Color riskColor(RiskLevel l) => switch (l) {
  RiskLevel.high => FsColors.riskHigh,
  RiskLevel.medium => FsColors.riskMedium,
  RiskLevel.low => FsColors.riskLow,
  RiskLevel.unknown => FsColors.riskUnknown,
};

String riskLabel(RiskLevel l) => switch (l) {
  RiskLevel.high => S.riskHigh,
  RiskLevel.medium => S.riskMedium,
  RiskLevel.low => S.riskLow,
  RiskLevel.unknown => S.riskNoData,
};

class FsRiskBadge extends StatelessWidget {
  const FsRiskBadge({super.key, required this.hazard, required this.level});
  final String hazard;

  /// null = flagged by the engine without a level: shown as a warning only.
  final RiskLevel? level;

  @override
  Widget build(BuildContext context) {
    final level = this.level;
    if (level == null) {
      return _Pill(
        color: FsColors.constrained,
        icon: Icons.warning_amber,
        label: hazardLabel(hazard),
        semantic: 'Risk: ${hazardLabel(hazard)}',
      );
    }
    final label = '${hazardLabel(hazard)}: ${riskLabel(level)}';
    return _Pill(
      color: riskColor(level),
      icon: level == RiskLevel.unknown
          ? Icons.help_outline
          : hazardIcon(hazard),
      label: label,
      semantic: '${hazardLabel(hazard)} risk: ${riskLabel(level)}',
    );
  }
}

(Color, IconData) evidenceStyle(EvidenceType t) => switch (t) {
  EvidenceType.observation => (
    FsColors.evidenceObservation,
    Icons.satellite_alt,
  ),
  EvidenceType.model => (FsColors.evidenceModel, Icons.model_training),
  EvidenceType.imagery => (FsColors.evidenceImagery, Icons.image_outlined),
  EvidenceType.reference => (FsColors.evidenceReference, Icons.menu_book),
  EvidenceType.unverified => (
    FsColors.evidenceUnverified,
    Icons.report_outlined,
  ),
};

String evidenceTypeLabel(EvidenceType t) => switch (t) {
  EvidenceType.observation => 'NASA observation',
  EvidenceType.model => 'Model estimate',
  EvidenceType.imagery => 'Map imagery (visual only)',
  EvidenceType.reference => 'Crop reference',
  EvidenceType.unverified => 'Not verified',
};

/// Tap to see source, period and scale.
class FsEvidenceChip extends StatelessWidget {
  const FsEvidenceChip(this.reference, {super.key});
  final Reference reference;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = evidenceStyle(reference.type);
    return ActionChip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(reference.title),
      side: BorderSide(color: color),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      onPressed: () => showSourceSheet(context, reference),
    );
  }
}

void showSourceSheet(BuildContext context, Reference r) {
  final (color, icon) = evidenceStyle(r.type);
  final t = Theme.of(context).textTheme;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          FsSpace.gutter,
          0,
          FsSpace.gutter,
          FsSpace.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: FsSpace.sm),
                Expanded(child: Text(r.title, style: t.titleLarge)),
              ],
            ),
            const SizedBox(height: FsSpace.sm),
            Text(
              evidenceTypeLabel(r.type),
              style: t.labelLarge?.copyWith(color: color),
            ),
            if (r.period != null) _row(t, 'Period', r.period!),
            if (r.spatialScale != null) ...[
              _row(t, 'Scale', r.spatialScale!),
              Text(
                'Regional estimate — not a measurement of your exact field.',
                style: t.bodySmall,
              ),
            ],
            if (r.note != null) _row(t, 'Note', r.note!),
            if (r.url != null) _row(t, 'Link', r.url!),
          ],
        ),
      ),
    ),
  );
}

Widget _row(TextTheme t, String k, String v) => Padding(
  padding: const EdgeInsets.only(top: FsSpace.sm),
  child: Text.rich(
    TextSpan(
      children: [
        TextSpan(text: '$k: ', style: t.labelLarge),
        TextSpan(text: v, style: t.bodyMedium),
      ],
    ),
  ),
);
