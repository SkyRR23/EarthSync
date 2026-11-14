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

enum _Metric { rain, heat }

/// Weather in plain words: big cards first, then one simple chart.
/// Cards follow OpenFarm's weather-cards idea; numbers come from the engine
/// data — Flutter only picks the highest/lowest month to show.
class WeatherTab extends StatefulWidget {
  const WeatherTab({super.key, required this.analysis});
  final FieldAnalysis analysis;

  @override
  State<WeatherTab> createState() => _WeatherTabState();
}

class _WeatherTabState extends State<WeatherTab> {
  _Metric _metric = _Metric.rain;
  int? _selected;

  String _month(MonthlyClimate m, {bool long = false}) =>
      long ? monthNames[m.month - 1] : monthShort[m.month - 1];

  MonthlyClimate? _pick(bool Function(double a, double b) better, double? Function(MonthlyClimate) v) {
    MonthlyClimate? best;
    for (final m in widget.analysis.climateSummary.months) {
      final x = v(m);
      if (x == null) continue;
      if (best == null || better(x, v(best)!)) best = m;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.analysis.climateSummary;
    final p = context.fs;
    final t = context.type;
    final ref = widget.analysis.reference(c.sourceId);
    final months = c.months;
    final rain = _metric == _Metric.rain;

    final wettest = _pick((a, b) => a > b, (m) => m.rainMm);
    final driest = _pick((a, b) => a < b, (m) => m.rainMm);
    final hottest = _pick((a, b) => a > b, (m) => m.tempMeanC);

    final cards = <Widget>[
      if (wettest != null)
        FsMetricTile(
          icon: CupertinoIcons.cloud_heavyrain_fill,
          color: p.rain,
          label: S.mostRain,
          value: '${_month(wettest)} · ${wettest.rainMm!.round()} mm',
        ),
      if (driest != null)
        FsMetricTile(
          icon: CupertinoIcons.sun_max_fill,
          color: p.cautionText,
          label: S.leastRain,
          value: '${_month(driest)} · ${driest.rainMm!.round()} mm',
        ),
      if (hottest != null)
        FsMetricTile(
          icon: CupertinoIcons.thermometer,
          color: p.heat,
          label: S.hottest,
          value: '${_month(hottest)} · ${hottest.tempMeanC!.toStringAsFixed(0)} °C',
        ),
      if (c.totalRainMm != null)
        FsMetricTile(
          icon: CupertinoIcons.drop_fill,
          color: p.rain,
          label: S.seasonRain,
          value: '${c.totalRainMm!.round()} mm',
        ),
      if (c.meanTempC != null)
        FsMetricTile(
          icon: CupertinoIcons.thermometer,
          color: p.heat,
          label: S.avgTemp,
          value: '${c.meanTempC!.toStringAsFixed(1)} °C',
        ),
    ];

    final sel = _selected != null && _selected! < months.length ? months[_selected!] : null;
    final v = sel == null ? null : (rain ? sel.rainMm : sel.tempMeanC);

    return FsPage(
      title: S.tabWeather,
      showBack: false,
      subtitle: c.period.isEmpty ? null : c.period,
      children: [
        if (c.dataKind != null && c.dataKind != 'observed') ...[
          const SizedBox(height: FsSpace.md),
          FsBanner(
            message: S.notMeasured(c.dataKind!),
            tone: FsTone.caution,
            icon: CupertinoIcons.exclamationmark_circle_fill,
          ),
        ],
        if (cards.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(FsSpace.gutter, FsSpace.lg, FsSpace.gutter, 0),
            child: LayoutBuilder(
              builder: (_, box) {
                final w = (box.maxWidth - FsSpace.sm) / 2;
                return Wrap(
                  spacing: FsSpace.sm,
                  runSpacing: FsSpace.sm,
                  children: [for (final c in cards) SizedBox(width: w, child: c)],
                );
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(FsSpace.gutter, FsSpace.xxl, FsSpace.gutter, 0),
          child: FsSegmented<_Metric>(
            value: _metric,
            onChanged: (m) => setState(() {
              _metric = m;
              _selected = null;
            }),
            segments: const {_Metric.rain: S.rain, _Metric.heat: S.heat},
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
                    (sel == null ? (rain ? S.rainEachMonth : S.heatEachMonth) : _month(sel, long: true))
                        .toUpperCase(),
                    style: t.caption.copyWith(letterSpacing: 0.4, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: FsSpace.xxs),
                  Text(
                    sel == null
                        ? ' '
                        : (v == null ? S.noData : (rain ? '${v.round()} mm' : '${v.toStringAsFixed(1)} °C')),
                    style: t.title1,
                  ),
                ],
              ),
            ),
            const SizedBox(height: FsSpace.md),
            SizedBox(
              height: 210,
              child: months.isEmpty
                  ? Center(child: Text(S.noData, style: t.footnote))
                  : (rain ? _rainChart(months, p.rain) : _heatChart(months, p.heat)),
            ),
          ],
        ),
        if (ref != null)
          FsGroupedSection(
            header: S.whereFrom,
            separatorIndent: FsSpace.lg + 22 + FsSpace.md,
            children: [FsEvidenceRow(ref)],
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
    if (i < 0 || i >= months.length || (v - i).abs() > 0.01) return const SizedBox.shrink();
    final m = months[i];
    final label = months.length > 6 ? monthShort[m.month - 1][0] : monthShort[m.month - 1];
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

  FlTitlesData _titles(List<MonthlyClimate> months, double step) => FlTitlesData(
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
    getDrawingHorizontalLine: (_) =>
        FlLine(color: context.fs.separator, strokeWidth: 0.5, dashArray: const [3, 3]),
  );

  void _tap(FlTouchEvent e, int? i) {
    if (i == null) return;
    if (e is FlTapUpEvent || e is FlPanUpdateEvent) setState(() => _selected = i);
  }

  Widget _rainChart(List<MonthlyClimate> months, Color color) {
    final values = [for (final m in months) ?m.rainMm];
    final axis = _niceAxis(values.isEmpty ? 0 : values.reduce(math.max));
    final width = months.length > 6 ? 14.0 : 30.0;
    return Semantics(
      label:
          '${S.rainEachMonth}. ${[for (final m in months) '${_month(m, long: true)}: ${m.rainMm == null ? S.noData : '${m.rainMm!.round()} millimetres'}'].join(', ')}',
      child: BarChart(
        BarChartData(
          maxY: axis.max,
          gridData: _grid(axis.step),
          borderData: FlBorderData(show: false),
          titlesData: _titles(months, axis.step),
          barTouchData: BarTouchData(
            enabled: true,
            handleBuiltInTouches: false,
            touchCallback: (e, r) => _tap(e, r?.spot?.touchedBarGroupIndex),
          ),
          barGroups: [
            for (final (i, m) in months.indexed)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    // Missing month: faint stub, never "zero rain".
                    toY: m.rainMm ?? axis.max * 0.015,
                    width: width,
                    color: m.rainMm == null
                        ? context.fs.fillStrong
                        : (_selected == null || _selected == i ? color : color.withValues(alpha: 0.3)),
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

  Widget _heatChart(List<MonthlyClimate> months, Color color) {
    final values = [for (final m in months) ?m.tempMeanC];
    final lo = values.isEmpty ? 0.0 : values.reduce(math.min);
    final hi = values.isEmpty ? 1.0 : values.reduce(math.max);
    final step = (hi - lo) > 12 ? 5.0 : ((hi - lo) > 5 ? 2.0 : 1.0);
    return Semantics(
      label:
          '${S.heatEachMonth}. ${[for (final m in months) '${_month(m, long: true)}: ${m.tempMeanC == null ? S.noData : '${m.tempMeanC!.toStringAsFixed(1)} degrees'}'].join(', ')}',
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: math.max(1, months.length - 1).toDouble(),
          minY: (lo / step).floor() * step - step,
          maxY: (hi / step).ceil() * step + step,
          gridData: _grid(step),
          borderData: FlBorderData(show: false),
          titlesData: _titles(months, step),
          lineTouchData: LineTouchData(
            enabled: true,
            handleBuiltInTouches: false,
            touchCallback: (e, r) => _tap(e, r?.lineBarSpots?.firstOrNull?.x.round()),
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
                  m.tempMeanC == null ? FlSpot.nullSpot : FlSpot(i.toDouble(), m.tempMeanC!),
              ],
              belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.08)),
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
