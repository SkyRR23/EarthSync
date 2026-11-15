import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../design/components/product.dart';
import '../../data/platform_farms.dart';
import '../field/decision_comparison.dart';
import '../../state/journal_provider.dart';
import '../../state/platform_provider.dart';
import '../field/agricultural_intelligence_panel.dart';
import 'companion_copy.dart';
import '../realtime/realtime_panel.dart';

/// Reuses the existing NASA/Rust assessment journey for strategy creation/editing.
class RotationWorkspace extends ConsumerStatefulWidget {
  const RotationWorkspace({super.key});
  @override
  ConsumerState<RotationWorkspace> createState() => _RotationWorkspaceState();
}

class _RotationWorkspaceState extends ConsumerState<RotationWorkspace> {
  String? _edit, _comparison;
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(journalProvider);
    final snapshot = state.hasError ? null : state.value;
    final farm = ref.watch(platformFarmProvider).value;
    final client = ref.watch(platformFarmClientProvider);
    final decisions = snapshot?.rows('decisions') ?? [];
    final selected = decisions.where((d) => d['id'] == _edit).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(CompanionCopy.text(context, 'Compare alternatives')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1300),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextButton.icon(
                onPressed: () => context.push('/historical'),
                icon: const Icon(Icons.history),
                label: const Text('Historical Simulation Lab'),
              ),
              const PageHeader(
                title: 'Rotation strategies',
                subtitle:
                    'Create and save each proposed sequence, then compare your declared existing plan with alternatives. Editing saves a new assessment; previous evidence and decisions remain immutable.',
              ),
              ExpansionTile(
                title: Text(realtimeCopy(context, 'Real-time EarthSync')),
                subtitle: const Text(
                  'Latest environmental context alongside all three strategies; no suitability ranking.',
                ),
                children: const [RealtimePanel(compact: true, fieldOnly: true)],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => context.push('/season'),
                    child: const Text('Farm history & priorities'),
                  ),
                  TextButton(
                    onPressed: () => context.push('/field'),
                    child: const Text('Field map & environment'),
                  ),
                  TextButton(
                    onPressed: () => context.push('/crops'),
                    child: const Text('Explore crop references'),
                  ),
                ],
              ),
              if (state.isLoading) const LinearProgressIndicator(),
              if (snapshot == null || farm == null || client == null)
                EvidenceNotice(
                  title: 'Connect this farm',
                  message:
                      'This workflow uses the selected confirmed farm revision and private local evidence service. Connect and refresh before creating assessments.',
                  action: TextButton(
                    onPressed: () => context.push('/farm-evidence'),
                    child: const Text('Open farm connection'),
                  ),
                ),
              if (snapshot != null) ...[
                DropdownButtonFormField<String>(
                  key: ValueKey('saved:$_comparison'),
                  initialValue: _comparison,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Reopen saved comparison',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('New comparison'),
                    ),
                    for (final c in snapshot.rows('comparisons'))
                      DropdownMenuItem(
                        value: c['id'] as String,
                        child: Text(
                          '${c['name']} · ${c['recorded_at']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _comparison = v),
                ),
                DecisionComparison(
                  key: ValueKey('comparison:${snapshot.farmId}:$_comparison'),
                  decisions: decisions,
                  initialComparison: snapshot
                      .rows('comparisons')
                      .where((c) => c['id'] == _comparison)
                      .firstOrNull,
                  onEdit: snapshot.cached
                      ? null
                      : (id) => setState(() => _edit = id),
                  onSave: snapshot.cached || client == null
                      ? null
                      : (value) async {
                          await client.transport.request(
                            'POST',
                            '${PlatformFarmClient.prefix}/farms/${snapshot.farmId}/comparisons',
                            expectedStatus: 201,
                            body: value,
                          );
                          ref.invalidate(journalProvider);
                          ref.invalidate(platformAssistantProvider);
                        },
                ),
                if (snapshot.cached)
                  Text(
                    'Cached copy · read only · retrieved ${snapshot.retrieved}. Reconnect before calculating or saving.',
                  ),
                DropdownButtonFormField<String>(
                  key: ValueKey(_edit),
                  initialValue: selected?['id'] as String?,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Reopen an assessment as an editable proposal',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Create a new strategy'),
                    ),
                    for (final d in decisions)
                      DropdownMenuItem(
                        value: d['id'] as String,
                        child: Text(
                          '${d['assessment']['assessed_at']} · ${d['id']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: snapshot.cached
                      ? null
                      : (v) => setState(() => _edit = v),
                ),
                if (!snapshot.cached && farm != null && client != null)
                  AbsorbPointer(
                    key: ValueKey('editor:${snapshot.farmId}:$_edit'),
                    absorbing: state.isLoading,
                    child: AgriculturalIntelligencePanel(
                      key: ValueKey('strategy:${snapshot.farmId}:$_edit'),
                      farm: farm,
                      client: client,
                      records: snapshot.rows('evidence'),
                      farmerReports: snapshot.rows('entries'),
                      environmentalSnapshots: snapshot.rows('intelligence'),
                      farmerObservations: snapshot.rows('observations'),
                      initialDecision: selected,
                      onSaved: () {
                        ref.invalidate(journalProvider);
                        ref.invalidate(platformDecisionsProvider);
                        ref.invalidate(platformAssistantProvider);
                      },
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
