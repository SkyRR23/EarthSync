import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/farm_journal.dart';
import '../../design/components/product.dart';

String sourceFingerprint(Map job) {
  final result = job['result'] as Map? ?? {};
  return '${job['kind']}:${result['source_sha256']}:${result['model_initialized_at']}:${(result['records'] as List? ?? []).map((r) => r['source_sha256']).join(',')}';
}

class ReassessmentNotice extends StatelessWidget {
  const ReassessmentNotice({super.key, required this.snapshot});
  final FarmJournalSnapshot snapshot;
  @override
  Widget build(BuildContext context) {
    final decisions = snapshot.rows('decisions');
    if (decisions.isEmpty) return const SizedBox.shrink();
    final latest = decisions.first['assessment'] as Map;
    final selected = {
      for (final r in latest['farmer_reports'] as List? ?? []) r['id'],
      for (final r in latest['farmer_observations'] as List? ?? []) r['id'],
    };
    final selectedSources = {
      for (final j in latest['environmental_snapshots'] as List? ?? [])
        sourceFingerprint(j as Map),
    };
    final reports =
        [...snapshot.rows('entries'), ...snapshot.rows('observations')]
            .where(
              (r) =>
                  r['kind'] != 'warning_acknowledgment' &&
                  !selected.contains(r['id']),
            )
            .length;
    final sources = snapshot
        .rows('intelligence')
        .where(
          (j) =>
              j['status'] == 'succeeded' &&
              !selectedSources.contains(sourceFingerprint(j)),
        )
        .length;
    if (reports == 0 && sources == 0) return const SizedBox.shrink();
    return EvidenceNotice(
      title: 'Review changed or unselected context',
      message:
          '$reports farmer records and $sources source snapshots are not included in the latest saved assessment. Select them explicitly to reassess. This does not imply that a crop became suitable or that monitoring is automatic.',
      action: TextButton(
        onPressed: () => context.push('/rotations'),
        child: const Text('Reopen a strategy and select evidence'),
      ),
    );
  }
}
