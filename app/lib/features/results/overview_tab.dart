import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/strings.dart';
import '../../data/models/field_analysis.dart';
import '../../design/components/feedback.dart';
import '../../design/components/grouped.dart';
import '../../design/components/page.dart';
import '../../design/components/scenario.dart';
import '../../design/components/sheet.dart';
import '../../design/components/status.dart';
import '../../design/tokens.dart';

/// "rain_mm.Jul 2026" -> "Rain, Jul 2026"; "drainage" -> "Drainage".
String dataGapLabel(String field) {
  const names = {
    'rain_mm': 'Rain',
    'temp_mean_c': 'Temperature',
    'drainage': 'Drainage',
    'irrigation': 'Water for the field',
    'current_crop': 'Current crop',
    'planting_month': 'Planting month',
    'soil': 'Soil',
  };
  return field.split('.').map((p) => names[p] ?? humanize(p)).join(', ');
}

void showAboutResults(BuildContext context, FieldAnalysis a) {
  final indent = FsSpace.lg + 22 + FsSpace.md;
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
                    leading: Icon(
                      CupertinoIcons.info_circle_fill,
                      color: p.infoText,
                      size: 22,
                    ),
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
                    leading: Icon(
                      CupertinoIcons.question_circle,
                      color: p.secondaryLabel,
                      size: 22,
                    ),
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
                    leading: Icon(
                      CupertinoIcons.text_quote,
                      color: p.secondaryLabel,
                      size: 22,
                    ),
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

/// Season metrics from the engine (never computed in Flutter).
class SeasonMetrics extends StatelessWidget {
  const SeasonMetrics(this.climate, {super.key});
  final ClimateSummary climate;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final rain = climate.totalRainMm;
    final temp = climate.meanTempC;
    if (rain == null && temp == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FsSpace.gutter,
        FsSpace.lg,
        FsSpace.gutter,
        0,
      ),
      child: Row(
        children: [
          if (rain != null)
            Expanded(
              child: FsMetricTile(
                icon: CupertinoIcons.drop_fill,
                color: p.rain,
                label: S.seasonRain,
                value: '${rain.round()} mm',
              ),
            ),
          if (rain != null && temp != null) const SizedBox(width: FsSpace.sm),
          if (temp != null)
            Expanded(
              child: FsMetricTile(
                icon: CupertinoIcons.thermometer,
                color: p.heat,
                label: S.avgTemp,
                value: '${temp.toStringAsFixed(1)} °C',
              ),
            ),
        ],
      ),
    );
  }
}

class OverviewTab extends StatelessWidget {
  const OverviewTab({
    super.key,
    required this.analysis,
    required this.fromCache,
    required this.onCompare,
  });

  final FieldAnalysis analysis;
  final bool fromCache;
  final void Function([int index]) onCompare;

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    final p = context.fs;
    final period = a.climateSummary.period;
    final subtitle = [
      a.location.name ?? S.appName,
      if (period.isNotEmpty) period,
    ].join(' · ');
    final gaps = a.dataGaps.length;

    return FsPage(
      title: S.yourOptions,
      subtitle: subtitle,
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(FsSpace.minTouch),
        onPressed: () => context.push('/sources'),
        child: Icon(
          CupertinoIcons.book,
          color: p.tint,
          semanticLabel: S.sources,
        ),
      ),
      children: [
        const SizedBox(height: FsSpace.md),
        if (a.dataQuality.isDemo)
          FsBanner(
            message: S.demoData,
            detail: gaps > 0 ? S.missingCount(gaps) : null,
            tone: FsTone.caution,
            icon: CupertinoIcons.exclamationmark_circle_fill,
            onTap: () => showAboutResults(context, a),
          )
        else if (gaps > 0)
          FsBanner(
            message: S.missingCount(gaps),
            tone: FsTone.neutral,
            icon: CupertinoIcons.question_circle_fill,
            onTap: () => showAboutResults(context, a),
          ),
        if (fromCache && a.dataQuality.fetchedAt != null) ...[
          const SizedBox(height: FsSpace.sm),
          FsBanner(
            message: S.savedData(
              DateFormat.yMMMd().format(a.dataQuality.fetchedAt!),
            ),
            icon: CupertinoIcons.clock,
          ),
        ],
        SeasonMetrics(a.climateSummary),
        FsGroupedSection(
          header: S.rotations,
          children: [
            for (final (i, (s, label)) in labelledScenarios(
              a.scenarios,
            ).indexed)
              FsScenarioRow(
                scenario: s,
                label: label,
                onTap: () => onCompare(i),
              ),
            FsListRow(
              leading: Icon(
                CupertinoIcons.arrow_right_arrow_left,
                color: p.tint,
                size: 22,
              ),
              title: S.compareSideBySide,
              titleStyle: context.type.body.copyWith(color: p.tint),
              onTap: () => onCompare(0),
            ),
          ],
        ),
        if (a.alerts.isNotEmpty)
          FsGroupedSection(
            header: S.warnings,
            children: [
              for (final al in a.alerts)
                FsListRow(
                  leading: Icon(
                    hazardIcon(al.hazard),
                    color: p.tone(riskTone(al.level)).$1,
                    size: 22,
                  ),
                  title: al.message,
                  below: FsRiskLabel(hazard: al.hazard, level: al.level),
                ),
            ],
          ),
        FsGroupedSection(
          children: [
            FsListRow(
              leading: FsIconBadge(
                CupertinoIcons.info,
                color: p.secondaryLabel,
              ),
              title: S.aboutResults,
              subtitle: S.aboutResultsSub,
              onTap: () => showAboutResults(context, a),
            ),
          ],
        ),
      ],
    );
  }
}
