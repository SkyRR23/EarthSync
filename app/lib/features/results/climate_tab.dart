import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';

import '../../app/strings.dart';
import '../../data/models/field_analysis.dart';
import '../../design/components/feedback.dart';
import '../../design/components/grouped.dart';
import '../../design/components/page.dart';
import '../../design/components/scenario.dart' show monthNames, monthShort;
import '../../design/components/segmented.dart';
import '../../design/components/status.dart';
import '../../design/tokens.dart';
import 'overview_tab.dart' show SeasonMetrics;

enum _Metric { rain, temp }

/// Apple Health / Weather-style climate view: one chart at a time,
/// tap a month to read its value in the header.
class ClimateTab extends StatefulWidget {
  const ClimateTab({super.key, required this.analysis});
  final FieldAnalysis analysis;

  @override
  State<ClimateTab> createState() => _ClimateTabState();
}

class _ClimateTabState extends State<ClimateTab> {
  _Metric _metric = _Metric.rain;
  int? _selected;

  String _monthLabel(MonthlyClimate m, {bool long = false}) {
    final name = long ? monthNames[m.month - 1] : monthShort[m.month - 1];
    return m.year == null ? name : '$name ${m.year}';
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.analysis;
    final c = a.climateSummary;
    final p = context.fs;
    final t = context.type;
    final ref = a.reference(c.sourceId);
    final months = c.months;
    final rain = _metric == _Metric.rain;
    final color = rain ? p.rain : p.heat;

    // Header: selected month value, or the series summary.
    final sel = _selected != null && _selected! < months.length
        ? months[_selected!]
        : null;
    final v = sel == null ? null : (rain ? sel.rainMm : sel.tempMeanC);
    final (String big, String small) = sel != null
        ? (
            v == null
                ? S.noData
                : (rain ? '${v.round()} mm' : '${v.toStringAsFixed(1)} °C'),
            _monthLabel(sel, long: true),
          )
        : (
            rain
                ? (c.totalRainMm != null
                      ? '${c.totalRainMm!.round()} mm'
                      : S.rainfall)
                : (c.meanTempC != null
                      ? '${c.meanTempC!.toStringAsFixed(1)} °C'
                      : S.temperature),
            rain
                ? (c.totalRainMm != null ? 'Total · ${c.period}' : c.period)
                : (c.meanTempC != null ? 'Average · ${c.period}' : c.period),
          );

    return FsPage(
      title: S.tabClimate,
      subtitle: c.period.isEmpty ? null : c.period,
      children: [
        SeasonMetrics(c),
        if (c.dataKind != null && c.dataKind != 'observed') ...[
          const SizedBox(height: FsSpace.md),
          FsBanner(
            message: 'These values are ${c.dataKind}, not measured',
            tone: FsTone.caution,
            icon: CupertinoIcons.exclamationmark_circle_fill,
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FsSpace.gutter,
            FsSpace.xl,
            FsSpace.gutter,
            0,
          ),
          child: FsSegmented<_Metric>(
            value: _metric,
            onChanged: (m) => setState(() {
              _metric = m;
              _selected = null;
            }),
            segments: const {
              _Metric.rain: S.rainfall,
              _Metric.temp: S.temperature,
            },
          ),
        ),
        FsGroupedSection(
          padded: true,
          footer: rain ? '${S.tapBar} ${S.gapNote}' : S.tapBar,
          children: [
            Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    small.toUpperCase(),
                    style: t.caption.copyWith(
                      letterSpacing: 0.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: FsSpace.xxs),
                  Text(big, style: t.title1),
                ],
              ),
            ),
            const SizedBox(height: FsSpace.lg),
            SizedBox(
              height: 210,
              child: months.isEmpty
                  ? Center(child: Text(S.noData, style: t.footnote))
                  : (rain
                        ? _rainChart(months, color)
                        : _tempChart(months, color)),
            ),
          ],
        ),
        if (ref != null)
          FsGroupedSection(
            header: S.evidence,
            separatorIndent: FsSpace.lg + 22 + FsSpace.md,
            children: [FsEvidenceRow(ref)],
          ),
        if (c.limitations.isNotEmpty)
          FsGroupedSection(
            header: S.limitations,
            separatorIndent: FsSpace.lg + 22 + FsSpace.md,
            children: [
              for (final l in c.limitations)
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
      ],
    );
  }

  ({double max, double step}) _niceAxis(double maxValue) {
    final raw = maxValue <= 0 ? 1.0 : maxValue;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final step = raw / mag > 5 ? mag * 2 : (raw / mag > 2 ? mag : mag / 2);
    return (max: (raw * 1.08 / step).ceil() * step, step: step);
  }

  Widget _monthTitle(List<MonthlyClimate> months, double v, TitleMeta meta) {
    final i = v.round();
    if (i < 0 || i >= months.length || (v - i).abs() > 0.01) {
      return const SizedBox.shrink();
    }
    final m = months[i];
    final label = months.length > 6
        ? monthShort[m.month - 1][0]
        : monthShort[m.month - 1];
    return SideTitleWidget(
      meta: meta,
      child: Text(
        label,
        style: context.type.caption.copyWith(
          color: i == _selected ? context.fs.label : context.fs.secondaryLabel,
          fontWeight: i == _selected ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
  }

  Widget _rightAxis(double v, TitleMeta meta) => SideTitleWidget(
    meta: meta,
    child: Text(
      v.round().toString(),
      style: context.type.caption.copyWith(color: context.fs.tertiaryLabel),
    ),
  );

  FlTitlesData _titles(List<MonthlyClimate> months, double step) =>
      FlTitlesData(
        topTitles: const AxisTitles(),
        leftTitles: const AxisTitles(),
        rightTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 36,
            interval: step,
            getTitlesWidget: _rightAxis,
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 26,
            interval: 1,
            getTitlesWidget: (v, m) => _monthTitle(months, v, m),
          ),
        ),
      );

  FlGridData _grid(double step) => FlGridData(
    drawVerticalLine: false,
    horizontalInterval: step,
    getDrawingHorizontalLine: (_) => FlLine(
      color: context.fs.separator,
      strokeWidth: 0.5,
      dashArray: const [3, 3],
    ),
  );

  Widget _rainChart(List<MonthlyClimate> months, Color color) {
    final values = [for (final m in months) ?m.rainMm];
    final axis = _niceAxis(values.isEmpty ? 0 : values.reduce(math.max));
    final width = months.length > 6 ? 14.0 : 30.0;
    return Semantics(
      label:
          'Rain by month. ${[for (final m in months) '${_monthLabel(m, long: true)}: ${m.rainMm == null ? S.noData : '${m.rainMm!.round()} millimetres'}'].join(', ')}',
      child: BarChart(
        BarChartData(
          maxY: axis.max,
          gridData: _grid(axis.step),
          borderData: FlBorderData(show: false),
          titlesData: _titles(months, axis.step),
          barTouchData: BarTouchData(
            enabled: true,
            handleBuiltInTouches: false,
            touchCallback: (e, r) {
              if (e is FlTapUpEvent || e is FlPanUpdateEvent) {
                final i = r?.spot?.touchedBarGroupIndex;
                if (i != null) {
                  setState(
                    () => _selected = _selected == i && e is FlTapUpEvent
                        ? null
                        : i,
                  );
                }
              }
            },
          ),
          barGroups: [
            for (final (i, m) in months.indexed)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    // Missing month: faint stub so the gap is visible and tappable, never "zero rain".
                    toY: m.rainMm ?? axis.max * 0.015,
                    width: width,
                    color: m.rainMm == null
                        ? context.fs.fillStrong
                        : (_selected == null || _selected == i
                              ? color
                              : color.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(width / 2.6),
                  ),
                ],
              ),
          ],
        ),
        duration: FsMotion.of(context, FsMotion.normal),
      ),
    );
  }

  Widget _tempChart(List<MonthlyClimate> months, Color color) {
    final values = [for (final m in months) ?m.tempMeanC];
    final lo = values.isEmpty ? 0.0 : values.reduce(math.min);
    final hi = values.isEmpty ? 1.0 : values.reduce(math.max);
    final step = (hi - lo) > 12 ? 5.0 : ((hi - lo) > 5 ? 2.0 : 1.0);
    final minY = (lo / step).floor() * step - step;
    final maxY = (hi / step).ceil() * step + step;
    return Semantics(
      label:
          'Temperature by month. ${[for (final m in months) '${_monthLabel(m, long: true)}: ${m.tempMeanC == null ? S.noData : '${m.tempMeanC!.toStringAsFixed(1)} degrees'}'].join(', ')}',
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: math.max(1, months.length - 1).toDouble(),
          minY: minY,
          maxY: maxY,
          gridData: _grid(step),
          borderData: FlBorderData(show: false),
          titlesData: _titles(months, step),
          lineTouchData: LineTouchData(
            enabled: true,
            handleBuiltInTouches: false,
            touchCallback: (e, r) {
              if (e is FlTapUpEvent || e is FlPanUpdateEvent) {
                final x = r?.lineBarSpots?.firstOrNull?.x;
                if (x != null) setState(() => _selected = x.round());
              }
            },
          ),
          lineBarsData: [
            LineChartBarData(
              isCurved: true,
              curveSmoothness: 0.3,
              preventCurveOverShooting: true,
              color: color,
              barWidth: 3,
              spots: [
                for (final (i, m) in months.indexed)
                  m.tempMeanC == null
                      ? FlSpot.nullSpot
                      : FlSpot(i.toDouble(), m.tempMeanC!),
              ],
              belowBarData: BarAreaData(
                show: true,
                color: color.withValues(alpha: 0.08),
              ),
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, _, _, i) => FlDotCirclePainter(
                  radius: i == _selected ? 6 : 3,
                  color: i == _selected ? color : context.fs.surface,
                  strokeWidth: 2,
                  strokeColor: color,
                ),
              ),
            ),
          ],
        ),
        duration: FsMotion.of(context, FsMotion.normal),
      ),
    );
  }
}
