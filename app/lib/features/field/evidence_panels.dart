import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/integration_provider.dart';

class EvidenceDetails extends StatelessWidget {
  const EvidenceDetails({super.key, required this.title, required this.data});
  final String title;
  final Object? data;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: Text(title),
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: SelectableText(const JsonEncoder.withIndent('  ').convert(data)),
      ),
    ],
  );
}

class EnvironmentalPanel extends ConsumerWidget {
  const EnvironmentalPanel({super.key, required this.target});
  final String target;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(environmentalProvider(target))
      .when(
        loading: () => const LinearProgressIndicator(
          semanticsLabel: 'Loading environmental context',
        ),
        error: (error, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Environmental service unavailable. Soil and weather conditions are unknown.',
            ),
            TextButton(
              onPressed: () => ref.invalidate(environmentalProvider(target)),
              child: const Text('Retry environmental context'),
            ),
          ],
        ),
        data: (data) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Environmental context',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'Regional models and source availability. No field soil measurement or agricultural diagnosis is available.',
            ),
            for (final evidence in data['evidence'] as List)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${evidence['context_kind']} · ${evidence['availability']}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${evidence['source']['provider']} · ${evidence['source']['dataset']}',
                      ),
                      Text(
                        evidence['reason'] as String? ??
                            'Reference context only; not usable for analysis.',
                      ),
                      Text(
                        'Resolution: ${evidence['spatial_support']['nominal_resolution_m'] ?? 'unknown'} m · quality: ${evidence['quality']['qa_status']}',
                      ),
                      Text(
                        'Observation interval: ${evidence['temporal_support']['valid_start'] ?? 'unknown'} to ${evidence['temporal_support']['valid_end'] ?? 'unknown'}',
                      ),
                      Text(
                        'Retrieved: ${evidence['temporal_support']['retrieved_at'] ?? 'not retrieved'} · issued: ${evidence['temporal_support']['issue_time'] ?? 'unknown'}',
                      ),
                      if ((evidence['values'] as List).isEmpty)
                        const Text(
                          'Measurements and units unavailable; no values were retrieved.',
                        ),
                      for (final value in evidence['values'] as List)
                        Text(
                          '${value['variable']} (${value['data_kind']}, ${value['statistic']}): ${value['value'] ?? 'unknown'} ${value['unit']} · depth ${value['depth_cm'] ?? 'unknown'} cm · ${value['quality']} · reference only',
                        ),
                      EvidenceDetails(
                        title: 'Source, units, dates and limitations',
                        data: evidence,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
}

class SatelliteEvidencePanel extends ConsumerWidget {
  const SatelliteEvidencePanel({super.key, required this.target});
  final String target;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(satelliteProvider(target))
      .when(
        loading: () => const LinearProgressIndicator(
          semanticsLabel: 'Loading satellite availability',
        ),
        error: (_, _) => Column(
          children: [
            const Text(
              'Satellite availability service unavailable. No optical or radar observations verified.',
            ),
            TextButton(
              onPressed: () => ref.invalidate(satelliteProvider(target)),
              child: const Text('Retry satellite availability'),
            ),
          ],
        ),
        data: (data) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Optical / SAR evidence timeline',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              'Requested dates: ${data['query']['start']} to ${data['query']['end']}',
            ),
            for (final provider in data['providers'] as List)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('${provider['provider']} · ${provider['status']}'),
                      Text('${provider['reason']}'),
                      const Text(
                        'Acquisition, retrieval, units, resolution and quality: unavailable until actual products are validated.',
                      ),
                      EvidenceDetails(
                        title: 'Provider source and unavailable details',
                        data: provider,
                      ),
                    ],
                  ),
                ),
              ),
            for (final event in data['events'] as List)
              EvidenceDetails(
                title: '${event['date']} · ${event['type']}',
                data: event,
              ),
            for (final event in data['undated_photos'] as List)
              EvidenceDetails(
                title: 'Farmer photo · capture date unknown',
                data: event,
              ),
            const Text(
              'Radar brightness cannot establish flooding or soil moisture here. Photos can be uploaded independently.',
            ),
          ],
        ),
      );
}
