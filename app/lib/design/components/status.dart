import 'package:flutter/cupertino.dart';

import '../../app/strings.dart';
import '../../data/models/field_analysis.dart';
import '../tokens.dart';
import 'grouped.dart';
import 'sheet.dart';

/// Soft capsule label: icon + word + tone. Never colour alone.
class FsStatusLabel extends StatelessWidget {
  const FsStatusLabel({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
    this.semanticLabel,
  });

  final String label;
  final FsTone tone;
  final IconData? icon;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = context.fs.tone(tone);
    return Semantics(
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FsSpace.sm + 2,
          vertical: FsSpace.xs,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(FsRadius.capsule),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: FsSpace.xs),
            ],
            Flexible(
              child: Text(
                label,
                style: context.type.footnote.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Feasibility (engine eligibility) — wording kept honest.
// ---------------------------------------------------------------------------

(String, FsTone, IconData) feasibilityStyle(Feasibility f) => switch (f) {
  Feasibility.supported => (
    S.supported,
    FsTone.positive,
    CupertinoIcons.checkmark_circle_fill,
  ),
  Feasibility.constrained => (
    S.constrained,
    FsTone.caution,
    CupertinoIcons.exclamationmark_triangle_fill,
  ),
  Feasibility.conflicts => (
    S.conflicts,
    FsTone.negative,
    CupertinoIcons.xmark_circle_fill,
  ),
  Feasibility.unknown => (
    S.unknown,
    FsTone.neutral,
    CupertinoIcons.question_circle_fill,
  ),
};

class FsFeasibilityLabel extends StatelessWidget {
  const FsFeasibilityLabel(this.value, {super.key});
  final Feasibility value;

  @override
  Widget build(BuildContext context) {
    final (label, tone, icon) = feasibilityStyle(value);
    return FsStatusLabel(
      label: label,
      tone: tone,
      icon: icon,
      semanticLabel: 'Status: $label',
    );
  }
}

// ---------------------------------------------------------------------------
// Risks
// ---------------------------------------------------------------------------

/// Engine codes like "rotation_rules" -> "Rotation rules".
String humanize(String code) {
  final s = code.replaceAll('_', ' ').trim();
  return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();
}

String hazardLabel(String hazard) => switch (hazard) {
  'drought' => 'Drought',
  'heat' => 'Heat',
  'waterlogging' => 'Waterlogging',
  'flood' => 'Flood',
  'storm' => 'Storm',
  _ => humanize(hazard),
};

IconData hazardIcon(String hazard) => switch (hazard) {
  'drought' => CupertinoIcons.sun_max_fill,
  'heat' => CupertinoIcons.thermometer,
  'waterlogging' || 'flood' => CupertinoIcons.drop_fill,
  'storm' => CupertinoIcons.cloud_bolt_rain_fill,
  _ => CupertinoIcons.exclamationmark_triangle_fill,
};

String riskLevelLabel(RiskLevel l) => switch (l) {
  RiskLevel.high => S.riskHigh,
  RiskLevel.medium => S.riskMedium,
  RiskLevel.low => S.riskLow,
  RiskLevel.unknown => S.riskNoData,
};

FsTone riskTone(RiskLevel? l) => switch (l) {
  RiskLevel.high => FsTone.negative,
  RiskLevel.medium => FsTone.caution,
  RiskLevel.low => FsTone.positive,
  RiskLevel.unknown => FsTone.neutral,
  null => FsTone.caution,
};

class FsRiskLabel extends StatelessWidget {
  const FsRiskLabel({super.key, required this.hazard, required this.level});
  final String hazard;

  /// null = flagged by the engine without a level.
  final RiskLevel? level;

  @override
  Widget build(BuildContext context) {
    final l = level;
    final text = l == null
        ? hazardLabel(hazard)
        : '${hazardLabel(hazard)}: ${riskLevelLabel(l)}';
    return FsStatusLabel(
      label: text,
      tone: riskTone(l),
      icon: l == RiskLevel.unknown
          ? CupertinoIcons.question_circle_fill
          : hazardIcon(hazard),
      semanticLabel: 'Risk. $text',
    );
  }
}

// ---------------------------------------------------------------------------
// Evidence — distinct icons, one quiet colour.
// ---------------------------------------------------------------------------

(IconData, String) evidenceStyle(EvidenceType t) => switch (t) {
  EvidenceType.observation => (CupertinoIcons.globe, 'NASA observation'),
  EvidenceType.model => (CupertinoIcons.chart_bar_alt_fill, 'Model estimate'),
  EvidenceType.imagery => (
    CupertinoIcons.photo,
    'Satellite image (visual only)',
  ),
  EvidenceType.reference => (CupertinoIcons.book_fill, 'Crop reference'),
  EvidenceType.unverified => (
    CupertinoIcons.exclamationmark_circle_fill,
    'Not verified',
  ),
};

Color evidenceColor(BuildContext context, EvidenceType t) =>
    t == EvidenceType.unverified ? context.fs.cautionText : context.fs.tint;

/// Row that opens the source sheet.
class FsEvidenceRow extends StatelessWidget {
  const FsEvidenceRow(this.reference, {super.key});
  final Reference reference;

  @override
  Widget build(BuildContext context) {
    final (icon, typeLabel) = evidenceStyle(reference.type);
    return FsListRow(
      leading: Icon(icon, color: evidenceColor(context, reference.type)),
      title: reference.title,
      subtitle: typeLabel,
      onTap: () => showSourceSheet(context, reference),
    );
  }
}

void showSourceSheet(BuildContext context, Reference r) {
  final (icon, typeLabel) = evidenceStyle(r.type);
  showFsSheet<void>(
    context,
    title: S.evidence,
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FsGroupedSection(
          children: [
            FsListRow(
              leading: Icon(icon, color: evidenceColor(ctx, r.type)),
              title: r.title,
              subtitle: typeLabel,
            ),
            if (r.period != null && r.period!.isNotEmpty)
              FsListRow(title: 'Period', value: r.period),
            if (r.spatialScale != null)
              FsListRow(title: 'Scale', value: r.spatialScale),
            if (r.note != null && r.note!.isNotEmpty)
              FsListRow(title: 'Note', subtitle: r.note),
            if (r.url != null) FsListRow(title: 'Link', subtitle: r.url),
          ],
        ),
        if (r.spatialScale != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FsSpace.gutter + FsSpace.lg,
              FsSpace.sm,
              FsSpace.gutter + FsSpace.lg,
              0,
            ),
            child: Text(S.regionalNote, style: ctx.type.footnote),
          ),
      ],
    ),
  );
}
