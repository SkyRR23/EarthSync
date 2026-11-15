import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../design/components/product.dart';
import 'historical_client.dart';

class HistoricalReplayControls extends StatelessWidget {
  const HistoricalReplayControls({
    super.key,
    required this.start,
    required this.end,
    required this.selected,
    required this.onChanged,
  });
  final DateTime start, end, selected;
  final ValueChanged<DateTime> onChanged;
  @override
  Widget build(BuildContext context) {
    final days = end.difference(start).inDays;
    final index = selected.difference(start).inDays.clamp(0, days);
    return Column(
      children: [
        Text(
          'Selected historical day: ${historicalDay(selected)} · NASA POWER LST',
        ),
        DropdownButtonFormField<int>(
          key: ValueKey('month:${selected.month}'),
          initialValue: selected.month,
          decoration: const InputDecoration(labelText: 'Historical month'),
          items: [
            for (var m = 1; m <= 12; m++)
              if (!DateTime(selected.year, m + 1, 0).isBefore(start) &&
                  !DateTime(selected.year, m).isAfter(end))
                DropdownMenuItem(value: m, child: Text('$m')),
          ],
          onChanged: (m) {
            if (m != null) {
              var d = DateTime.utc(selected.year, m);
              if (d.isBefore(start)) d = start;
              onChanged(d);
            }
          },
        ),
        Slider(
          value: index.toDouble(),
          min: 0,
          max: days == 0 ? 1 : days.toDouble(),
          divisions: days == 0 ? 1 : days,
          label: historicalDay(selected),
          semanticFormatterCallback: (v) =>
              historicalDay(start.add(Duration(days: v.round()))),
          onChanged: days == 0
              ? null
              : (v) => onChanged(start.add(Duration(days: v.round()))),
        ),
        TextButton(
          onPressed: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: selected,
              firstDate: start,
              lastDate: end,
            );
            if (d != null) onChanged(DateTime.utc(d.year, d.month, d.day));
          },
          child: const Text('Choose historical day'),
        ),
      ],
    );
  }
}

class HistoricalMetrics extends StatelessWidget {
  const HistoricalMetrics({super.key, required this.summary});
  final Map<String, dynamic> summary;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 8,
    children: [
      for (final e in (summary['metrics'] as Map).entries)
        SizedBox(
          width: 220,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.key as String,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    '${e.value['value'] is num ? (e.value['value'] as num).toStringAsFixed(2) : 'Unavailable'} ${e.value['unit']}',
                  ),
                  Text(
                    '${e.value['valid_days']}/${e.value['expected_days']} valid days · ${e.value['missing_days']} missing',
                  ),
                  Text(
                    e.value['status'] == 'partial'
                        ? 'Accepted-day subtotal / statistic only'
                        : '${e.value['status']}',
                  ),
                  Text('${summary['start']} to ${summary['end']}'),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

class HistoricalChart extends StatelessWidget {
  const HistoricalChart({
    super.key,
    required this.periods,
    required this.monthly,
    required this.variable,
  });
  final List<Map<String, dynamic>> periods, monthly;
  final String variable;
  @override
  Widget build(BuildContext context) {
    final unit =
        variable == 'temperature' || variable == 'tmin' || variable == 'tmax'
        ? '°C'
        : 'mm';
    final rows = monthly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$variable · $unit · NASA POWER LST${variable == 'et0' ? ' / compiled Rust FAO-56' : ''}',
        ),
        const Text(
          'Each bar is a monthly accepted-day statistic. Missing months are gaps; partial values are labelled in the accessible table.',
        ),
        SizedBox(
          height: 200,
          child: ExcludeSemantics(
            child: BarChart(
              BarChartData(
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: [
                  for (final (i, r) in rows.indexed)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        if (r['metrics'][variable]['value'] is num)
                          BarChartRodData(
                            toY: (r['metrics'][variable]['value'] as num)
                                .toDouble(),
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
        ExpansionTile(
          title: const Text('Accessible chart values & coverage'),
          children: [
            for (final r in rows)
              ListTile(
                title: Text(
                  '${r['start']} to ${r['end']} · ${r['metrics'][variable]['value'] ?? 'Unavailable'} $unit',
                ),
                subtitle: Text(
                  '${r['metrics'][variable]['valid_days']}/${r['metrics'][variable]['expected_days']} days · ${r['metrics'][variable]['status']}',
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class HistoricalResult extends StatelessWidget {
  const HistoricalResult({super.key, required this.result});
  final Map<String, dynamic> result;
  @override
  Widget build(BuildContext context) {
    final periods = List<Map<String, dynamic>>.from(result['periods'] as List);
    return SectionCard(
      title: 'Saved simulated results · ${result['request']['name']}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${result['request']['mode']} · saved ${result['created_at']} · result ${result['id']}',
          ),
          SelectableText(
            'Reproducible calculation SHA-256: ${result['calculation_sha256']}',
          ),
          HistoricalSeasonComparison(periods: periods),
          const Text(
            'Scenario inputs are hypothetical. Environmental inputs retain their original real/cached-real classification. No recommendation is authorized.',
          ),
          for (final p in periods)
            ExpansionTile(
              initiallyExpanded: periods.length <= 2,
              title: Text('${p['start']} to ${p['end']} · ${p['day_basis']}'),
              children: [
                HistoricalMetrics(summary: p),
                for (final variable in ['rainfall', 'temperature', 'et0'])
                  HistoricalChart(
                    periods: periods,
                    monthly: List<Map<String, dynamic>>.from(
                      p['monthly'] as List,
                    ),
                    variable: variable,
                  ),
                for (final s in p['strategies'] as List)
                  ExpansionTile(
                    title: Text('${s['identity']} · simulated'),
                    children: [
                      for (final plan in s['plans'] as List) ...[
                        Text(
                          '${plan['profile_id']} · ${plan['start']} to ${plan['end']} · ${plan['duration_days']} declared days',
                        ),
                        HistoricalMetrics(
                          summary: Map<String, dynamic>.from(
                            plan['environment'] as Map,
                          ),
                        ),
                      ],
                      Text(
                        'Declared irrigation: ${s['assumptions']['irrigation']} · drainage: ${s['assumptions']['drainage']}',
                      ),
                      Text('${s['assumption_review']['explanation']}'),
                      for (final f in s['rust_findings'] as List)
                        Text('Rust: ${f['explanation']}'),
                      for (final gap in s['calendar']['unknown_gaps'] as List)
                        Text('${gap['start']} to ${gap['end']} · Unknown gap'),
                      for (final conflict in s['calendar']['overlaps'] as List)
                        Text('Chronology conflict: ${conflict['explanation']}'),
                      for (final c in s['crop_references'] as List)
                        ListTile(
                          title: Text(
                            'Reference: ${c['profile']['id']} · ${c['profile']['region_id']}',
                          ),
                          subtitle: Text(
                            'Reference traits require local review. ${(c['sources'] as List? ?? []).map((v) => '${v['title']} · ${v['url']}').join('\n')}',
                          ),
                        ),
                      const Text(
                        'ETc, effective rainfall, water stress, irrigation volume and crop yield cannot yet be calculated.',
                      ),
                    ],
                  ),
                if ((p['excluded_evidence'] as List).isNotEmpty)
                  const Text(
                    'As-of mode withheld archive evidence: availability by the decision timestamp was not proven.',
                  ),
              ],
            ),
          ExpansionTile(
            title: const Text('Historical reference method & completeness'),
            children: [
              for (final e in (result['baseline'] as Map).entries)
                Text(
                  '${e.key}: ${e.value['value'] ?? 'Unavailable'} · ${e.value['sample_count']} complete seasons\n${e.value['method']}\nPeriods used: ${e.value['periods_used']}\nIncomplete/excluded: ${e.value['excluded_periods']}',
                ),
              const Text(
                'Unequal or incomplete coverage is not silently compared. Two-year differences are not proof of long-term climate change. No anomaly or crop-damage threshold is inferred.',
              ),
            ],
          ),
          ExpansionTile(
            title: const Text('Original source lineage'),
            children: [
              for (final source in result['source_lineage'] as List)
                ListTile(
                  title: Text('${source['dataset']} · ${source['version']}'),
                  subtitle: Text(
                    'Retrieved ${source['retrieved_at']} · publication ${source['publication_at'] ?? 'unknown'}\nSHA-256 ${source['sha256']}',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Matching month offsets, distinct line patterns and a readable value table.
class HistoricalSeasonComparison extends StatelessWidget {
  const HistoricalSeasonComparison({super.key, required this.periods});
  final List<Map<String, dynamic>> periods;
  @override
  Widget build(BuildContext context) {
    final displayed = periods.take(2).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Season comparison · original coverage retained'),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final p in displayed)
              SizedBox(
                width: 330,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${p['start']} to ${p['end']}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        for (final variable in [
                          'rainfall',
                          'temperature',
                          'et0',
                        ])
                          Text(
                            '$variable: ${p['metrics'][variable]['value'] is num ? (p['metrics'][variable]['value'] as num).toStringAsFixed(2) : 'Unavailable'} ${p['metrics'][variable]['unit']} · ${p['metrics'][variable]['valid_days']}/${p['metrics'][variable]['expected_days']} days · ${p['metrics'][variable]['status']}',
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (displayed.length == 2) ...[
          for (final variable in ['rainfall', 'temperature', 'et0'])
            Text(
              displayed[0]['metrics'][variable]['complete_value'] is num &&
                      displayed[1]['metrics'][variable]['complete_value'] is num
                  ? '$variable difference (second minus first): ${((displayed[1]['metrics'][variable]['complete_value'] as num) - (displayed[0]['metrics'][variable]['complete_value'] as num)).toStringAsFixed(2)} ${displayed[0]['metrics'][variable]['unit']}; direct difference without period-length adjustment.'
                  : '$variable complete-period difference unavailable: at least one season is incomplete.',
            ),
          const Text(
            'Charts align monthly position within each requested season. Compare the actual dates in the tables, especially for custom or unequal seasons. Blue solid line = first season; orange dashed line = second season.',
          ),
          for (final variable in ['rainfall', 'temperature', 'et0']) ...[
            Text(
              '$variable · ${variable == 'temperature' ? '°C' : 'mm'} · NASA POWER LST${variable == 'et0' ? ' / Rust FAO-56' : ''}',
            ),
            SizedBox(
              height: 180,
              child: ExcludeSemantics(
                child: LineChart(
                  LineChartData(
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      for (final (i, p) in displayed.indexed)
                        LineChartBarData(
                          color: i == 0 ? Colors.blue : Colors.deepOrange,
                          dashArray: i == 0 ? null : [7, 4],
                          barWidth: i == 0 ? 3 : 2,
                          isCurved: false,
                          dotData: const FlDotData(show: true),
                          spots: [
                            for (final (month, row)
                                in (p['monthly'] as List).indexed)
                              row['metrics'][variable]['value'] is num
                                  ? FlSpot(
                                      month.toDouble(),
                                      (row['metrics'][variable]['value'] as num)
                                          .toDouble(),
                                    )
                                  : FlSpot.nullSpot,
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}
