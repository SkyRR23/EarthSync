import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../data/environment/area_climate.dart';
import '../../state/dashboard_provider.dart';
import '../../data/models/field_analysis.dart';

class ClimatePanel extends ConsumerWidget {
  const ClimatePanel({super.key, required this.query});
  final ClimateQuery query;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardClimateProvider(query));
    final climate = state.value;
    return Card(
      semanticContainer: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Historical climate',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'NASA POWER · modeled climate at a query point. This is not a calculated area average or a field measurement.',
            ),
            Text('Point: ${query.point.label}'),
            Text(
              '${DateFormat.yMMM().format(DateTime(query.window.startYear, query.window.startMonth))} – ${DateFormat.yMMM().format(DateTime(query.window.endYear, query.window.endMonth))} · LST',
            ),
            if (state.isLoading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const Text(
                'Loading climate records… NASA requests can take up to 90 seconds.',
              ),
            ],
            if (state.hasError) ...[
              const SizedBox(height: 12),
              const Text(
                'Climate data unavailable. Try again when the service is reachable. No example or synthetic climate was substituted. Missing data do not mean safe conditions.',
              ),
              if (state.error case final EngineError error) Text(error.message),
            ],
            if (climate != null) ...[
              if (state.hasError || state.isLoading)
                const Text(
                  'Last-known data for this same point and period · kept in this session.',
                ),
              ClimateReadings(climate: climate),
            ],
            TextButton.icon(
              onPressed: state.isLoading
                  ? null
                  : () => ref.invalidate(dashboardClimateProvider(query)),
              icon: const Icon(Icons.refresh),
              label: Text(
                state.hasError ? 'Try climate again' : 'Refresh climate',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ClimateReadings extends StatelessWidget {
  const ClimateReadings({super.key, required this.climate});
  final AreaClimate climate;
  @override
  Widget build(BuildContext context) {
    final rows = climate.readings;
    final hasRain = rows.any((r) => r.rainMm != null);
    final hasTemp = rows.any((r) => r.temperatureC != null);
    final maxRain = rows.fold(0.0, (v, r) => math.max(v, r.rainMm ?? 0));
    final rainStep = maxRain > 1000
        ? 500.0
        : maxRain > 100
        ? 100.0
        : maxRain > 10
        ? 20.0
        : 2.0;
    final rainTop = math.max(
      rainStep,
      ((maxRain * 1.05) / rainStep).ceil() * rainStep,
    );
    final temperatures = rows
        .map((r) => r.temperatureC)
        .whereType<double>()
        .toList();
    final tempMin = temperatures.isEmpty
        ? 0.0
        : temperatures.reduce(math.min).floorToDouble() - 1;
    final tempMax = temperatures.isEmpty
        ? 1.0
        : temperatures.reduce(math.max).ceilToDouble() + 1;
    final tempStep = math.max(1.0, ((tempMax - tempMin) / 4).ceilToDouble());
    final p = climate.evidence.provenance;
    final missing = rows.any((r) => r.rainMm == null || r.temperatureC == null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        if (missing)
          const Text(
            'Some climate data are missing or incomplete. Gaps are unknown, not zero. Conditions and crop safety cannot be inferred from these gaps.',
          ),
        const SizedBox(height: 12),
        if (hasRain) ...[
          const Text('Rainfall · mm per month'),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: ExcludeSemantics(
              child: BarChart(
                BarChartData(
                  minY: 0,
                  maxY: rainTop,
                  titlesData: _titles(rows, rainStep),
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(drawVerticalLine: false),
                  barGroups: [
                    for (final (i, row) in rows.indexed)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          if (row.rainMm != null)
                            BarChartRodData(
                              toY: row.rainMm!,
                              color: Colors.blue,
                              width: 12,
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ] else
          const Text('Rainfall unavailable for this period.'),
        const SizedBox(height: 20),
        if (hasTemp) ...[
          const Text('Temperature · monthly mean °C'),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: ExcludeSemantics(
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: (rows.length - 1).toDouble().clamp(1, 23),
                  minY: tempMin,
                  maxY: tempMax,
                  titlesData: _titles(rows, tempStep),
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(drawVerticalLine: false),
                  lineBarsData: [
                    LineChartBarData(
                      color: Colors.deepOrange,
                      isCurved: false,
                      spots: [
                        for (final (i, row) in rows.indexed)
                          row.temperatureC == null
                              ? FlSpot.nullSpot
                              : FlSpot(i.toDouble(), row.temperatureC!),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ] else
          const Text('Temperature unavailable for this period.'),
        const SizedBox(height: 16),
        // Readable values also serve screen readers and single-month windows.
        for (final row in rows)
          Text(
            '${DateFormat.yMMM().format(row.month)}: '
            '${row.rainMm?.toStringAsFixed(2) ?? "Unknown"} mm · '
            '${row.temperatureC?.toStringAsFixed(1) ?? "Unknown"} °C',
          ),
        const SizedBox(height: 12),
        Text('Source: ${p['provider']} / ${p['product']}'),
        Text(
          'Retrieved (UTC): ${(p['source_requests'] as List).map((r) => r['retrieved_at']).join(', ')}',
        ),
        Text(
          'Backend cache: ${climate.evidence.envelope['cache']['hit'] == true ? "cached response" : "fresh retrieval"}',
        ),
        const Text(
          'Daily coverage is not scientific accuracy. These records are historical, not a forecast. Local soils, water and crop conditions may differ.',
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Source details and data quality'),
          children: [
            Text('${p['spatial_support']}'),
            Text('${p['aggregation']}'),
            for (final limit in p['limitations'] as List) Text('• $limit'),
            for (final coverage in p['coverage'] as List)
              Text('Coverage: $coverage'),
            for (final doc in p['documentation'] as List)
              SelectableText('$doc'),
          ],
        ),
      ],
    );
  }

  FlTitlesData _titles(List<ClimateReading> rows, double interval) =>
      FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 48,
            interval: interval,
            minIncluded: false,
            maxIncluded: false,
            getTitlesWidget: (v, meta) => SideTitleWidget(
              meta: meta,
              child: Text(
                v.toStringAsFixed(0),
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: rows.length > 12 ? 3 : 1,
            getTitlesWidget: (v, meta) {
              final i = v.round();
              return SideTitleWidget(
                meta: meta,
                child: Text(
                  i < 0 || i >= rows.length || (v - i).abs() > .01
                      ? ''
                      : DateFormat.MMM().format(rows[i].month),
                  style: const TextStyle(fontSize: 10),
                ),
              );
            },
          ),
        ),
      );
}
