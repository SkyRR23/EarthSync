import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../app/strings.dart';
import 'climate_provenance.dart';
import '../../data/models/field_analysis.dart';
import '../../design/components/badges.dart';
import '../../design/components/feedback.dart';
import '../../design/components/scenario.dart' show monthNames;
import '../../design/tokens.dart';

const _m = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];

/// Round the axis up to a clean step so the top label never collides.
({double max, double step}) _niceAxis(double maxValue) {
  final step = maxValue > 600 ? 200.0 : 100.0;
  final top = ((maxValue * 1.05) / step).ceil() * step;
  return (max: top <= 0 ? step : top, step: step);
}

Widget _axisLabel(double v, TitleMeta meta) =>
    SideTitleWidget(meta: meta, child: Text(v.round().toString()));

/// Bottom labels by position in the series, so season windows that cross
/// the new year (e.g. Nov -> Feb) stay in order.
GetTitleWidgetFunction _monthTitles(List<MonthlyClimate> months) =>
    (double v, TitleMeta meta) {
      final i = v.round();
      if (i < 0 || i >= months.length || (v - i).abs() > 0.01) {
        return const SizedBox.shrink();
      }
      final label = months.length > 6
          ? _m[months[i].month - 1]
          : monthNames[months[i].month - 1].substring(0, 3);
      return SideTitleWidget(meta: meta, child: Text(label));
    };

class ClimateTab extends StatelessWidget {
  const ClimateTab({super.key, required this.analysis});
  final FieldAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final c = analysis.climateSummary;
    final t = Theme.of(context).textTheme;
    final ref = analysis.reference(c.sourceId);
    final missingRain = [
      for (final m in c.months)
        if (m.rainMm == null) monthNames[m.month - 1],
    ];
    final rainSummary = c.months
        .map(
          (m) =>
              '${monthNames[m.month - 1]}: ${m.rainMm == null ? S.noData : '${m.rainMm!.toStringAsFixed(2)} mm'}',
        )
        .join(', ');

    final rainValues = [for (final m in c.months) ?m.rainMm];
    final rainAxis = _niceAxis(
      rainValues.isEmpty ? 0 : rainValues.reduce((a, b) => a > b ? a : b),
    );
    final temps = [for (final m in c.months) ?m.tempMeanC];
    final tMin = temps.isEmpty
        ? 0.0
        : temps.reduce((a, b) => a < b ? a : b).floorToDouble() - 1;
    final tMax = temps.isEmpty
        ? 1.0
        : temps.reduce((a, b) => a > b ? a : b).ceilToDouble() + 1;

    return ListView(
      padding: const EdgeInsets.all(FsSpace.gutter),
      children: [
        ClimateProvenance(analysis: analysis),
        const SizedBox(height: FsSpace.md),
        if (c.totalRainMm != null || c.meanTempC != null) ...[
          Text(S.seasonSummary, style: t.titleLarge),
          const SizedBox(height: FsSpace.xs),
          Text(c.period, style: t.bodyMedium),
          const SizedBox(height: FsSpace.sm),
          Row(
            children: [
              if (c.totalRainMm != null)
                Expanded(
                  child: _Stat(
                    icon: Icons.water_drop_outlined,
                    color: FsColors.sky,
                    value: '${c.totalRainMm!.toStringAsFixed(2)} mm',
                    label: 'Total rain',
                  ),
                ),
              if (c.totalRainMm != null && c.meanTempC != null)
                const SizedBox(width: FsSpace.sm),
              if (c.meanTempC != null)
                Expanded(
                  child: _Stat(
                    icon: Icons.thermostat,
                    color: FsColors.riskHigh,
                    value: '${c.meanTempC!.toStringAsFixed(1)} °C',
                    label: 'Average temperature',
                  ),
                ),
            ],
          ),
          if (c.dataKind != null && c.dataKind != 'observed') ...[
            const SizedBox(height: FsSpace.sm),
            FsDataQualityBanner(
              message:
                  'These climate values are ${c.dataKind}, not observed measurements.',
              kind: FsBannerKind.warning,
            ),
          ],
          const SizedBox(height: FsSpace.xl),
        ],
        Text('${S.rainfall} (mm per month)', style: t.titleLarge),
        const SizedBox(height: FsSpace.md),
        Semantics(
          label: 'Rainfall chart. $rainSummary',
          excludeSemantics: true,
          child: SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                maxY: rainAxis.max,
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: rainAxis.step,
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      interval: rainAxis.step,
                      getTitlesWidget: _axisLabel,
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: _monthTitles(c.months),
                    ),
                  ),
                ),
                barGroups: [
                  for (final (i, m) in c.months.indexed)
                    BarChartGroupData(
                      x: i,
                      barRods: m.rainMm == null
                          ? []
                          : [
                              BarChartRodData(
                                toY: m.rainMm!,
                                color: FsColors.sky,
                                width: 14,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ],
                    ),
                ],
              ),
            ),
          ),
        ),
        if (missingRain.isNotEmpty) ...[
          const SizedBox(height: FsSpace.sm),
          Text(
            '${S.noData}: ${missingRain.join(', ')} (gap in chart, not zero rain)',
            style: t.bodyMedium?.copyWith(color: FsColors.unknown),
          ),
        ],
        const SizedBox(height: FsSpace.xl),
        Text('${S.temperature} (°C, monthly average)', style: t.titleLarge),
        const SizedBox(height: FsSpace.md),
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (c.months.length - 1).toDouble().clamp(1, 11),
              minY: tMin,
              maxY: tMax,
              gridData: const FlGridData(
                drawVerticalLine: false,
                horizontalInterval: 1,
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    interval: (tMax - tMin) > 8 ? 2 : 1,
                    getTitlesWidget: _axisLabel,
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: 1,
                    getTitlesWidget: _monthTitles(c.months),
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (final (i, m) in c.months.indexed)
                      m.tempMeanC == null
                          ? FlSpot.nullSpot
                          : FlSpot(i.toDouble(), m.tempMeanC!),
                  ],
                  color: FsColors.riskHigh,
                  barWidth: 3,
                  dotData: const FlDotData(show: true),
                ),
              ],
            ),
          ),
        ),
        const FsSectionTitle(S.evidence),
        Text('Period: ${c.period}', style: t.bodyMedium),
        if (c.gridResolution != null)
          Text(
            'Scale: ${c.gridResolution} (regional estimate, not your exact field)',
            style: t.bodyMedium,
          ),
        const SizedBox(height: FsSpace.sm),
        if (ref != null)
          Align(alignment: Alignment.centerLeft, child: FsEvidenceChip(ref)),
        if (c.limitations.isNotEmpty) ...[
          const FsSectionTitle(S.limitations),
          FsBulletList(
            c.limitations,
            icon: Icons.info_outline,
            color: FsColors.unknown,
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FsSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: FsSpace.xs),
            Text(value, style: t.titleLarge),
            Text(label, style: t.bodySmall),
          ],
        ),
      ),
    );
  }
}
