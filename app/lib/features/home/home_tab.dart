import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/strings.dart';
import '../../data/models/farmer_input.dart';
import '../../data/models/field_analysis.dart';
import '../../design/components/feedback.dart';
import '../../design/components/grouped.dart';
import '../../design/components/page.dart';
import '../../design/components/pressable.dart';
import '../../design/components/scenario.dart';
import '../../design/components/sheet.dart';
import '../../design/components/status.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';
import '../map/gibs_layer.dart';

/// "rain_mm.Jul 2026" -> "Rain, Jul 2026"; "drainage" -> "After rain".
String dataGapLabel(String field) {
  const names = {
    'rain_mm': 'Rain',
    'temp_mean_c': 'Heat',
    'drainage': S.drainage,
    'irrigation': S.water,
    'current_crop': S.growNow,
    'planting_month': 'Planting month',
    'soil': 'Soil',
  };
  return field.split('.').map((p) => names[p] ?? humanize(p)).join(', ');
}

void showAboutResults(BuildContext context, FieldAnalysis a) {
  const indent = FsSpace.lg + 22 + FsSpace.md;
  showFsSheet<void>(
    context,
    title: S.aboutResults,
    builder: (ctx) {
      final p = ctx.fs;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (a.notices.isNotEmpty)
            FsGroupedSection(
              header: S.notices,
              separatorIndent: indent,
              children: [
                for (final n in a.notices)
                  FsListRow(
                    leading: Icon(CupertinoIcons.info_circle_fill, color: p.infoText, size: 22),
                    title: n,
                    titleStyle: ctx.type.callout,
                  ),
              ],
            ),
          if (a.dataGaps.isNotEmpty)
            FsGroupedSection(
              header: S.dataGaps,
              separatorIndent: indent,
              children: [
                for (final g in a.dataGaps)
                  FsListRow(
                    leading: Icon(CupertinoIcons.question_circle, color: p.secondaryLabel, size: 22),
                    title: dataGapLabel(g.field),
                    subtitle: g.reason,
                  ),
              ],
            ),
          if (a.assumptions.isNotEmpty)
            FsGroupedSection(
              header: S.assumptions,
              separatorIndent: indent,
              children: [
                for (final s in a.assumptions)
                  FsListRow(
                    leading: Icon(CupertinoIcons.text_quote, color: p.secondaryLabel, size: 22),
                    title: s,
                    titleStyle: ctx.type.callout,
                  ),
              ],
            ),
        ],
      );
    },
  );
}

String _answer(String? crop) =>
    (crop == null || crop == kUnknown) ? S.dontKnow : '${cropEmoji(crop)} ${Crops.label(crop)}';

String _water(Irrigation? i) => switch (i) {
  Irrigation.full => 'All year',
  Irrigation.partial => 'Sometimes',
  Irrigation.none => 'Only rain',
  _ => S.dontKnow,
};

String _drain(Drainage? d) => switch (d) {
  Drainage.poor => 'Stays many days',
  Drainage.moderate => 'Stays 1–2 days',
  Drainage.good => 'Dries fast',
  _ => S.dontKnow,
};

/// Plain-text summary for sharing with an extension officer (OpenFarm "share" idea,
/// without accounts or links — just text the farmer chooses to send).
String shareSummary(FarmerDraft d, FieldAnalysis a) {
  final b = StringBuffer()
    ..writeln('${S.appName} — ${S.myField}')
    ..writeln(
      '${S.location}: ${d.latitude?.toStringAsFixed(4)}, ${d.longitude?.toStringAsFixed(4)}',
    )
    ..writeln('${S.growNow}: ${_answer(d.currentCrop)}')
    ..writeln('${S.water}: ${_water(d.irrigation)}')
    ..writeln('${S.drainage}: ${_drain(d.drainage)}')
    ..writeln();
  for (final (s, label, _) in labelledScenarios(a.scenarios)) {
    final (status, _, _) = feasibilityStyle(s.eligibility);
    b.writeln('$label: ${cropSequence(s)} — $status');
  }
  b.writeln();
  if (a.dataQuality.isDemo) b.writeln(S.demoData);
  b.writeln(S.welcomeDisclaimer);
  return b.toString();
}

class HomeTab extends ConsumerWidget {
  const HomeTab({
    super.key,
    required this.analysis,
    required this.fromCache,
    required this.onOpenPlan,
  });

  final FieldAnalysis analysis;
  final bool fromCache;
  final ValueChanged<int> onOpenPlan;

  Future<void> _startOver(BuildContext context, WidgetRef ref) async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text(S.startOver),
        content: const Text(S.startOverConfirm),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(S.cancel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(S.startOver),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      ref.read(farmerDraftProvider.notifier).reset();
      ref.invalidate(analysisProvider);
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = analysis;
    final d = ref.watch(farmerDraftProvider);
    final p = context.fs;
    const iconIndent = FsSpace.lg + 30 + FsSpace.md;
    final fieldPt = LatLng(
      d.latitude ?? a.location.latitude,
      d.longitude ?? a.location.longitude,
    );

    return FsPage(
      title: S.myField,
      showBack: false,
      subtitle: a.location.name,
      children: [
        const SizedBox(height: FsSpace.md),
        if (a.dataQuality.isDemo)
          FsBanner(
            message: S.demoData,
            tone: FsTone.caution,
            icon: CupertinoIcons.exclamationmark_circle_fill,
            onTap: () => showAboutResults(context, a),
          ),
        if (fromCache && a.dataQuality.fetchedAt != null) ...[
          const SizedBox(height: FsSpace.sm),
          FsBanner(message: S.showLast, icon: CupertinoIcons.clock),
        ],
        _FieldMapCard(point: fieldPt),
        FsGroupedSection(
          header: S.cropPlans,
          children: [
            for (final (i, (s, label, _)) in labelledScenarios(a.scenarios).indexed)
              FsPlanRow(scenario: s, label: label, onTap: () => onOpenPlan(i)),
          ],
        ),
        if (a.alerts.isNotEmpty)
          FsGroupedSection(
            header: S.warnings,
            separatorIndent: FsSpace.lg + 22 + FsSpace.md,
            children: [
              for (final al in a.alerts)
                FsListRow(
                  leading: Icon(hazardIcon(al.hazard), color: p.tone(riskTone(al.level)).$1, size: 22),
                  title: al.message,
                  below: FsRiskLabel(hazard: al.hazard, level: al.level),
                ),
            ],
          ),
        FsGroupedSection(
          header: S.yourAnswers,
          separatorIndent: iconIndent,
          children: [
            FsListRow(
              leading: FsIconBadge(CupertinoIcons.location_solid, color: p.crop3),
              title: S.location,
              value: d.hasLocation
                  ? '${d.latitude!.toStringAsFixed(3)}, ${d.longitude!.toStringAsFixed(3)}'
                  : S.dontKnow,
              onTap: () => context.push('/location?edit=1'),
            ),
            FsListRow(
              leading: FsIconBadge(Icons.grass_rounded, color: p.crop1),
              title: S.growNow,
              value: _answer(d.currentCrop),
              onTap: () => context.push('/question/1?edit=1'),
            ),
            FsListRow(
              leading: FsIconBadge(CupertinoIcons.drop_fill, color: p.rain),
              title: S.water,
              value: _water(d.irrigation),
              onTap: () => context.push('/question/2?edit=1'),
            ),
            FsListRow(
              leading: FsIconBadge(CupertinoIcons.cloud_rain_fill, color: p.crop3),
              title: S.drainage,
              value: _drain(d.drainage),
              onTap: () => context.push('/question/3?edit=1'),
            ),
          ],
        ),
        FsGroupedSection(
          separatorIndent: iconIndent,
          children: [
            FsListRow(
              leading: FsIconBadge(CupertinoIcons.share, color: p.tint),
              title: S.share,
              onTap: () => SharePlus.instance.share(
                ShareParams(text: shareSummary(d, a), subject: S.appName),
              ),
            ),
            FsListRow(
              leading: FsIconBadge(CupertinoIcons.info, color: p.secondaryLabel),
              title: S.aboutResults,
              onTap: () => showAboutResults(context, a),
            ),
            FsListRow(
              leading: FsIconBadge(CupertinoIcons.book_fill, color: p.secondaryLabel),
              title: S.sources,
              onTap: () => context.push('/sources'),
            ),
          ],
        ),
        FsGroupedSection(
          children: [
            FsListRow(
              title: S.startOver,
              titleStyle: context.type.body.copyWith(color: p.negativeText),
              chevron: false,
              onTap: () => _startOver(context, ref),
            ),
          ],
        ),
      ],
    );
  }
}

/// Small, still NASA satellite view of the field. Tap opens the full map.
class _FieldMapCard extends StatelessWidget {
  const _FieldMapCard({required this.point});
  final LatLng point;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    const cfg = GibsLayerConfig.provisional;
    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.gutter, FsSpace.lg, FsSpace.gutter, 0),
      child: FsPressable(
        onTap: () => context.push('/map'),
        semanticLabel: '${S.satellitePhoto}. ${S.openMap}',
        scale: 0.98,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(FsRadius.md),
          child: SizedBox(
            height: 190,
            child: Stack(
              children: [
                IgnorePointer(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: point,
                      initialZoom: 9,
                      interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                    ),
                    children: [
                      streetTileLayer(),
                      gibsTileLayer(cfg),
                      MarkerLayer(
                        markers: [
                          Marker(point: point, width: 44, height: 44, child: fieldMarker(context)),
                        ],
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    color: p.surface.withValues(alpha: 0.92),
                    padding: const EdgeInsets.symmetric(
                      horizontal: FsSpace.lg,
                      vertical: FsSpace.sm + 2,
                    ),
                    child: Row(
                      children: [
                        Icon(CupertinoIcons.photo, color: p.tint, size: 20),
                        const SizedBox(width: FsSpace.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(S.satellitePhoto, style: t.headline),
                              Text(cfg.dateLabel, style: t.footnote),
                            ],
                          ),
                        ),
                        Text(S.openMap, style: t.subhead.copyWith(color: p.tint)),
                        Icon(CupertinoIcons.chevron_forward, color: p.tint, size: 16),
                      ],
                    ),
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
