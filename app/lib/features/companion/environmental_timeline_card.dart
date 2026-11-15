import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../field/evidence_panels.dart';

/// Original source times stay distinct from the time this request was saved.
class EnvironmentalTimelineCard extends StatelessWidget {
  const EnvironmentalTimelineCard({super.key, required this.job});
  final Map<String, dynamic> job;
  @override
  Widget build(BuildContext context) {
    final result = job['result'] as Map?;
    final kind = job['kind'];
    final updated = job['updated'];
    final savedAt = updated is num
        ? DateTime.fromMillisecondsSinceEpoch(
            (updated * 1000).round(),
            isUtc: true,
          ).toIso8601String()
        : updated ?? 'Unknown';
    return ExpansionTile(
      title: Text('Environmental context · $kind · ${job['status']}'),
      subtitle: Text('Request saved $savedAt · on demand'),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      childrenPadding: const EdgeInsets.all(12),
      children: [
        if (result == null)
          Text(
            'No accepted observation: ${job['error'] ?? 'Request not complete'}. No substitute values supplied.',
          ),
        if (result != null) ...[
          Text(
            '${result['provider'] ?? 'Source recorded below'} · ${result['dataset'] ?? kind}',
          ),
          Text(
            'Retrieved ${result['retrieved_at'] ?? 'Unknown'}; source observation time ${result['observation_time'] ?? 'Unavailable'}. Retrieval is not an acquisition date.',
          ),
          if (kind == 'soil_map') ...[
            Text(
              '${result['property']} · ${result['depth_cm']} cm · ${result['resolution_m']} m modeled grid · ${result['unit']}',
            ),
            for (final cell in (result['cells'] as List? ?? []).where(
              (c) => c['at_query_point'] == true,
            ))
              Text(
                'Cell at query point: ${cell['value'] ?? 'Missing'} ${result['unit']} · ${cell['quality']}',
              ),
            const Text(
              'A modeled grid cell is not a laboratory measurement or a field average. Crop suitability is not established.',
            ),
          ],
          if (kind == 'forecast') ...[
            Text(
              'Model initialized ${result['model_initialized_at']}; ${result['grid_spacing_degrees']}° grid. Publication time unavailable.',
            ),
            for (final record in result['records'] as List? ?? [])
              Text(
                '${record['valid_at']} · ${record['temperature_c'] ?? 'Unknown'} ${record['unit']}',
              ),
            const Text(
              'Saved forecast valid times remain unchanged. Check Risk & warnings for staleness; these are not observed current weather or official alerts.',
            ),
          ],
          Text((result['limitations'] as List? ?? []).join('\n')),
        ],
        TextButton(
          onPressed: () => context.push('/field'),
          child: const Text('Inspect this field’s map & source snapshots'),
        ),
        EvidenceDetails(
          title: 'Original source and quality details',
          data: job,
        ),
      ],
    );
  }
}
