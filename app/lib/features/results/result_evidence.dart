import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data/models/farmer_input.dart';
import '../../data/models/field_analysis.dart';
import '../../design/components/feedback.dart';
import '../../design/components/scenario.dart' show monthNames;
import '../../design/tokens.dart';

class ResultReadings extends StatelessWidget {
  const ResultReadings({super.key, required this.analysis});
  final FieldAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final c = analysis.climateSummary;
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FsSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Historical climate result', style: t.titleLarge),
            Text(c.period),
            const SizedBox(height: FsSpace.sm),
            Text(
              'Rainfall total: ${c.totalRainMm?.toStringAsFixed(2) ?? "Unknown"} mm',
              style: t.titleMedium,
            ),
            Text(
              'Mean temperature: ${c.meanTempC?.toStringAsFixed(2) ?? "Unknown"} °C',
              style: t.titleMedium,
            ),
            const SizedBox(height: FsSpace.sm),
            if (analysis.trace != null)
              const Text('Calculated by the compiled Rust engine.'),
            const Text(
              'Historical conditions, not a weather forecast or a crop suitability score.',
            ),
            if (c.months.length == 1)
              const Text(
                'Only one month selected. On Review, select a full completed year to compare wet and dry months.',
              ),
          ],
        ),
      ),
    );
  }
}

class RecommendationStatus extends StatelessWidget {
  const RecommendationStatus({super.key, required this.analysis});
  final FieldAnalysis analysis;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const FsSectionTitle('Recommendation status'),
      Text(
        analysis.scenarios.isEmpty
            ? 'No crop recommendation is available for this field yet.'
            : 'Reference options to explore — suitability is not established.',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: FsSpace.sm),
      Text(
        analysis.scenarios.isEmpty
            ? 'Climate data are available separately. This flow has no reviewed crop profile and rotation rules for the selected crop.'
            : 'The published rice–pulse examples are assessed by Rust. Their sources are reference-only; the engine keeps their suitability unknown. They are not ranked planting recommendations.',
      ),
      const FsSectionTitle('Evidence still needed'),
      const FsBulletList([
        'Crop variety and a locally reviewed production-system profile.',
        'Soil texture, pH and salinity measurements; field drainage observations.',
        'Water availability through the growing season and residual soil moisture.',
        'Planting and harvest dates, rotation rules, and local pest and disease history.',
      ]),
      const Text(
        'Review these with a local agricultural adviser before choosing a planting sequence. No yield, profit or water-saving estimate has been calculated.',
      ),
    ],
  );
}

class FieldEvidence extends StatelessWidget {
  const FieldEvidence({super.key, required this.analysis});
  final FieldAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final trace = analysis.trace;
    if (trace == null) return const SizedBox.shrink();
    final input = jsonDecode(trace.farmerInputJson) as Map<String, dynamic>;
    final month = input['planting_month'] as int?;
    final previous = (input['recent_rotation'] as List<dynamic>)
        .map((crop) => Crops.label(crop as String))
        .join(', ');
    final water = switch (input['irrigation']) {
      'full' => 'Available all year (reported)',
      'partial' => 'Sometimes available; timing unconfirmed',
      'none' => 'Rain only (reported)',
      _ => 'Unknown',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FsSectionTitle('Your field inputs'),
        Text('Current crop: ${Crops.label(input['current_crop'] as String?)}'),
        Text('Previous crops: ${previous.isEmpty ? "Unknown" : previous}'),
        Text(
          'Planned planting month: ${month == null ? "Unknown" : monthNames[month - 1]}',
        ),
        Text('Water: $water'),
        Text('Drainage: ${input['drainage']} (reported, not measured)'),
        const Text('Soil texture, pH and salinity: not collected'),
      ],
    );
  }
}

class MonthlyEvidenceTable extends StatelessWidget {
  const MonthlyEvidenceTable({super.key, required this.analysis});
  final FieldAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final coverage =
        analysis.trace?.provenance['coverage'] as List<dynamic>? ?? [];
    String coverageLabel(MonthlyClimate month) {
      final entry = coverage
          .where(
            (c) =>
                c['period']['year'] == month.year &&
                c['period']['month'] == month.month,
          )
          .firstOrNull;
      if (entry == null) return 'Daily coverage unavailable';
      final missing = entry['missing_or_invalid_dates'] as Map<String, dynamic>;
      return '${entry['expected_days']} expected days · '
          'missing rain: ${(missing['PRECTOTCORR'] as List).length}, '
          'temperature: ${(missing['T2M'] as List).length}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FsSectionTitle('Monthly values and coverage'),
        const Text(
          'Missing values are unknown, never zero. Coverage describes availability, not accuracy.',
        ),
        if (analysis.climateSummary.months.isEmpty)
          const Text('No monthly observations were returned.'),
        for (final month in analysis.climateSummary.months)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: FsSpace.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${monthNames[month.month - 1]} ${month.year ?? ""}',
                  style: t.titleMedium,
                ),
                Text(
                  'Rain: ${month.rainMm?.toStringAsFixed(2) ?? "Unknown"} mm · Mean temperature: ${month.tempMeanC?.toStringAsFixed(2) ?? "Unknown"} °C',
                ),
                if (analysis.trace != null)
                  Text(coverageLabel(month), style: t.bodySmall),
              ],
            ),
          ),
      ],
    );
  }
}
