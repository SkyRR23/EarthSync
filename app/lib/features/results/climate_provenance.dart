import 'package:flutter/cupertino.dart';

import '../../app/strings.dart';
import '../../data/models/field_analysis.dart';
import '../../design/components/feedback.dart';
import '../../design/components/grouped.dart';
import '../../design/tokens.dart';

/// Where the weather numbers come from (live NASA POWER, captured replay, or
/// demo). Climate and crop evidence keep separate labels. Exact wording of the
/// headline rows is checked by the team's NASA bridge tests.
class ClimateProvenance extends StatelessWidget {
  const ClimateProvenance({super.key, required this.analysis});
  final FieldAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    final c = a.climateSummary;
    final p = a.trace?.provenance;
    final t = context.type;
    final small = t.footnote;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FsGroupedSection(
          header: S.provenanceHeader,
          padded: true,
          children: [
            Row(
              children: [
                Icon(CupertinoIcons.globe, color: context.fs.tint, size: 22),
                const SizedBox(width: FsSpace.sm),
                Expanded(
                  child: Text(
                    p == null
                        ? 'Climate: ${c.dataKind ?? "unverified demo"}'
                        : a.trace!.retrievalMode == 'live_http'
                        ? 'Real NASA POWER climate · modeled data'
                        : 'Captured real NASA POWER climate · offline replay',
                    style: t.headline,
                  ),
                ),
              ],
            ),
            if (p != null) ...[
              const SizedBox(height: FsSpace.sm),
              Text('Dataset: ${p['product']}', style: small),
              Text(
                'Historical window: ${c.period} · ${p['time_standard']}',
                style: small,
              ),
              Text(
                'Requested point: ${a.location.latitude}, ${a.location.longitude}',
                style: small,
              ),
              Text(
                'Retrieved: ${a.dataQuality.fetchedAt?.toUtc().toIso8601String() ?? "unknown"}',
                style: small,
              ),
              Text(
                'Precipitation: ${c.totalRainMm?.toStringAsFixed(2) ?? "unknown"} mm · '
                'Mean temperature: ${c.meanTempC?.toStringAsFixed(4) ?? "unknown"} °C',
                style: small,
              ),
              if (p['spatial_support'] is String)
                Text(p['spatial_support'] as String, style: small),
              const SizedBox(height: FsSpace.xs),
              Text(
                'Completeness describes daily coverage, not scientific accuracy. Missing values remain unknown.',
                style: small,
              ),
              Text(
                'Crop suitability: unknown — no source-backed crop constraints supplied.',
                style: small,
              ),
            ],
          ],
        ),
        if (a.dataQuality.syntheticCropReferences)
          const FsBanner(
            message:
                'Synthetic crop profiles — test scenarios, not verified crop advice.',
            tone: FsTone.caution,
            icon: CupertinoIcons.exclamationmark_circle_fill,
          ),
      ],
    );
  }
}
