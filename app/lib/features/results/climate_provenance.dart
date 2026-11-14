import 'package:flutter/material.dart';

import '../../data/models/field_analysis.dart';
import '../../design/components/feedback.dart';

/// Climate and crop evidence have separate labels even in mixed test payloads.
class ClimateProvenance extends StatelessWidget {
  const ClimateProvenance({
    super.key,
    required this.analysis,
    this.compact = false,
  });
  final FieldAnalysis analysis;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    final c = a.climateSummary;
    final p = a.trace?.provenance;
    if (compact && p != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            a.trace!.retrievalMode == 'live_http'
                ? 'Live NASA POWER · modeled historical data'
                : 'Captured NASA POWER · offline replay',
          ),
          ExpansionTile(
            title: const Text('Source, retrieval date and limitations'),
            children: [ClimateProvenance(analysis: a)],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          p == null
              ? 'Climate: ${c.dataKind ?? "unverified demo"}'
              : a.trace!.retrievalMode == 'live_http'
              ? 'Real NASA POWER climate · modeled data'
              : 'Captured real NASA POWER climate · offline replay',
        ),
        if (p != null) ...[
          Text('Dataset: ${p['product']}'),
          Text('Historical window: ${c.period} · ${p['time_standard']}'),
          Text(
            'Requested point: ${a.location.latitude}, ${a.location.longitude}',
          ),
          Text(
            'Retrieved: ${a.dataQuality.fetchedAt?.toUtc().toIso8601String() ?? "unknown"}',
          ),
          Text(
            'Precipitation: ${c.totalRainMm?.toStringAsFixed(2) ?? "unknown"} mm · '
            'Mean temperature: ${c.meanTempC?.toStringAsFixed(4) ?? "unknown"} °C',
          ),
          Text(p['spatial_support'] as String),
          const Text(
            'Completeness describes daily coverage, not scientific accuracy. Missing values remain unknown.',
          ),
          Text(
            a.scenarios.isEmpty
                ? 'Crop suitability: unknown — no reviewed crop constraints supplied.'
                : 'Crop suitability: unknown — reference-only profiles, not verified for this field.',
          ),
        ],
        if (a.dataQuality.syntheticCropReferences)
          const FsDataQualityBanner(
            message:
                'Synthetic crop profiles — test scenarios, not verified crop advice.',
            kind: FsBannerKind.warning,
          ),
      ],
    );
  }
}
