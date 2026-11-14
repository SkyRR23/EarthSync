import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/farm_journal.dart';
import '../../design/components/product.dart';
import '../../state/journal_provider.dart';
import '../../state/platform_provider.dart';
import 'companion_copy.dart';

class RiskCenter extends ConsumerStatefulWidget {
  const RiskCenter({super.key, required this.snapshot});
  final FarmJournalSnapshot snapshot;
  @override
  ConsumerState<RiskCenter> createState() => _RiskCenterState();
}

class _RiskCenterState extends ConsumerState<RiskCenter> {
  String? _error;
  bool _busy = false;
  final _ids = <String, String>{};
  @override
  Widget build(BuildContext context) {
    final forecasts = widget.snapshot
        .rows('intelligence')
        .where((j) => j['kind'] == 'forecast')
        .toList();
    final acknowledged = widget.snapshot
        .rows('entries')
        .where((e) => e['kind'] == 'warning_acknowledgment')
        .expand((e) => e['environmental_job_ids'] as List? ?? [])
        .toSet();
    final now = DateTime.now().toUtc();
    return SectionCard(
      title: CompanionCopy.text(context, 'Risk & warnings'),
      icon: Icons.warning_amber_outlined,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Official issued alerts: unavailable. A missing alert is not an all-clear. The available GFS snapshots are sparse regional temperature forecasts, not a warning service or crop-specific frost forecast.',
            ),
            if (forecasts.isEmpty)
              Text(CompanionCopy.text(context, 'Forecast unavailable')),
            for (final job in forecasts) ...[
              if (job['status'] != 'succeeded')
                Text(
                  'Forecast request ${job['status']}: ${job['error'] ?? 'Pending'}. No weather values substituted.',
                ),
              if (job['result'] case final Map result)
                Builder(
                  builder: (_) {
                    final records = (result['records'] as List? ?? [])
                        .cast<Map>();
                    final future = records
                        .where(
                          (r) => DateTime.parse(
                            r['valid_at'] as String,
                          ).isAfter(now),
                        )
                        .toList();
                    final retrieved = DateTime.tryParse(
                      result['retrieved_at'] as String? ?? '',
                    );
                    final stale =
                        retrieved == null ||
                        now.difference(retrieved).inMinutes >= 30 ||
                        future.isEmpty ||
                        widget.snapshot.cached;
                    return ExpansionTile(
                      title: Text(
                        '${result['provider']} · ${stale ? 'Stale / expired saved forecast' : 'Dated forecast snapshot'}',
                      ),
                      subtitle: Text(
                        'Retrieved ${result['retrieved_at']} · model initialized ${result['model_initialized_at']}',
                      ),
                      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Publication / issuance timestamp: unavailable; model initialization is not publication time.',
                        ),
                        Text(
                          'Native support: ${result['grid_spacing_degrees']}° grid · ${result['unit']} · ${result['timezone']}',
                        ),
                        for (final r in records)
                          Text(
                            '${r['valid_at']} · ${r['temperature_c'] ?? 'Unknown'} ${r['unit']} · native grid point ${r['grid_point']}',
                          ),
                        for (final indicator
                            in result['derived_indicators'] as List? ?? [])
                          Text(
                            'Computed indicator: ${indicator['name']} · ${stale
                                ? 'not current; refresh before use'
                                : indicator['value'] == null
                                ? 'Unknown'
                                : indicator['value'] == true
                                ? 'Present in sampled future times'
                                : 'Not present in sampled times; unsampled times remain unknown'}. ${indicator['basis']}',
                          ),
                        for (final r in records)
                          Text(
                            'Source: ${r['source_url']} · SHA-256 ${r['source_sha256']}',
                          ),
                        Text((result['limitations'] as List? ?? []).join('\n')),
                        if (acknowledged.contains(job['id']))
                          const Text(
                            'Acknowledged by farmer · saved in record history',
                          ),
                        if (!acknowledged.contains(job['id']))
                          OutlinedButton(
                            onPressed: _busy || widget.snapshot.cached
                                ? null
                                : () async {
                                    if (!await confirmAction(
                                          context,
                                          title:
                                              'Record that you read this snapshot?',
                                          message:
                                              'Acknowledgment does not certify safety or confirm an official warning. The original source and valid times remain unchanged.',
                                          confirmLabel: 'Acknowledge',
                                        ) ||
                                        !context.mounted) {
                                      return;
                                    }
                                    setState(() {
                                      _busy = true;
                                      _error = null;
                                    });
                                    try {
                                      final id = _ids.putIfAbsent(
                                        job['id'] as String,
                                        journalId,
                                      );
                                      await FarmJournalClient(
                                        ref.read(platformFarmClientProvider)!,
                                      ).save(widget.snapshot.farmId, {
                                        'id': id,
                                        'kind': 'warning_acknowledgment',
                                        'occurred_on': DateTime.now()
                                            .toUtc()
                                            .toIso8601String()
                                            .substring(0, 10),
                                        'environmental_job_ids': [job['id']],
                                        'notes':
                                            'Read the dated regional forecast snapshot. No official warning or safe-field conclusion established.',
                                      });
                                      ref.invalidate(journalProvider);
                                      ref.invalidate(platformAssistantProvider);
                                    } catch (e) {
                                      if (mounted) {
                                        setState(
                                          () => _error =
                                              'Acknowledgment not saved: $e. Inspect the timeline before retrying.',
                                        );
                                      }
                                    } finally {
                                      if (mounted) {
                                        setState(() => _busy = false);
                                      }
                                    }
                                  },
                            child: const Text('Acknowledge snapshot'),
                          ),
                      ],
                    );
                  },
                ),
            ],
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => context.push('/field'),
                  child: const Text('Retrieve a new source snapshot'),
                ),
                TextButton(
                  onPressed: () => context.push('/rotations'),
                  child: const Text(
                    'Explicitly reassess with selected sources',
                  ),
                ),
              ],
            ),
            const Text(
              'Refresh and reassessment are on demand. No background delivery, scheduler or pest prediction is implied.',
            ),
          ],
        ),
      ),
    );
  }
}
