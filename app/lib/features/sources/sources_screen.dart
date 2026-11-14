import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/strings.dart';
import '../results/climate_provenance.dart';
import '../../data/models/field_analysis.dart';
import '../../design/components/badges.dart';
import '../../design/components/feedback.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';

class SourcesScreen extends ConsumerWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(analysisProvider);
    final a = state is AnalysisReady ? state.analysis : null;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text(S.sources)),
      body: a == null
          ? const FsStateView.loading()
          : ListView(
              padding: const EdgeInsets.all(FsSpace.gutter),
              children: [
                Text(
                  'Each result comes from one of these sources. Satellite grids and soil '
                  'models describe your region, not your exact plot.',
                  style: t.bodyLarge,
                ),
                ClimateProvenance(analysis: a),
                if (a.trace != null) ...[
                  ExpansionTile(
                    title: const Text('Exact backend response and provenance'),
                    children: [SelectableText(a.trace!.backendResponseJson)],
                  ),
                  ExpansionTile(
                    title: const Text(
                      'Retained farmer answers (not all used by Rust)',
                    ),
                    children: [SelectableText(a.trace!.farmerInputJson)],
                  ),
                  ExpansionTile(
                    title: const Text('Exact Rust request and result'),
                    children: [
                      SelectableText(a.trace!.rustRequestJson),
                      const Divider(),
                      SelectableText(a.trace!.rustResultJson),
                    ],
                  ),
                ],
                const FsSectionTitle('Evidence types'),
                for (final type in EvidenceType.values)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      evidenceStyle(type).$2,
                      color: evidenceStyle(type).$1,
                    ),
                    title: Text(evidenceTypeLabel(type)),
                  ),
                const FsSectionTitle('Sources used'),
                for (final r in a.references)
                  Card(
                    margin: const EdgeInsets.only(bottom: FsSpace.sm),
                    child: ListTile(
                      minTileHeight: FsSpace.minTouch + 8,
                      leading: Icon(
                        evidenceStyle(r.type).$2,
                        color: evidenceStyle(r.type).$1,
                      ),
                      title: Text(r.title),
                      subtitle: Text(evidenceTypeLabel(r.type)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showSourceSheet(context, r),
                    ),
                  ),
                const FsSectionTitle(S.assumptions),
                FsBulletList(a.assumptions),
              ],
            ),
    );
  }
}
