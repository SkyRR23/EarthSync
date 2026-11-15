import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/models/farmer_input.dart';
import '../design/components/page.dart';
import '../design/tokens.dart';
import '../state/providers.dart' as team;
import '../evidence/data/farm_journal.dart' show journalId;
import '../evidence/state/local_farm_provider.dart';
import 'farm_bridge.dart';
import 'rotation_simulator.dart';
import 'simulation_clock.dart';

final savedRotationPlansProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  ref.watch(localRevisionProvider);
  final profile = await ref.watch(selectedFarmBridgeProvider.future);
  final farm = profile.farm;
  if (farm == null) return [];
  return (await ref.watch(
    localFarmStoreProvider.future,
  )).records(farm.id, 'rotation_plan');
});

class RotationPlansPage extends ConsumerStatefulWidget {
  const RotationPlansPage({super.key});
  @override
  ConsumerState<RotationPlansPage> createState() => _RotationPlansState();
}

class _RotationPlansState extends ConsumerState<RotationPlansPage> {
  final _sequences = List.generate(3, (_) => List<String?>.filled(3, null));
  final _reason = TextEditingController();
  int? _chosen;
  bool _saving = false;
  String? _message;
  Map<String, dynamic>? _simulation;
  static const _names = ['Existing plan', 'Alternative 1', 'Alternative 2'];
  @override
  void initState() {
    super.initState();
    final crop = ref.read(team.farmerDraftProvider).currentCrop;
    if (Crops.options.containsKey(crop)) _sequences[0][0] = crop;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!kIsWeb && (_simulation == null || _simulation!['simulation_date'] != ref.read(simulationClockProvider).toIso8601String().substring(0,10))) {
      setState(() => _message = 'Generate and compare the rotation alternatives before saving this simulation decision.');
      return;
    }
    if (_chosen == null || _sequences[_chosen!].every((crop) => crop == null)) {
      setState(() => _message = 'Choose a plan and add at least one crop.');
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final farm = (await ref.read(selectedFarmBridgeProvider.future)).farm;
      if (farm == null) throw StateError('Choose your field first.');
      final now = DateTime.now().toUtc().toIso8601String();
      final store = await ref.read(localFarmStoreProvider.future);
      await store.put(farm.id, 'rotation_plan', {
        'id': journalId(),
        'farm_id': farm.id,
        'farm_revision': farm.confirmedAt.toUtc().toIso8601String(),
        'created_at': now,
        'updated_at': now,
        'origin': 'farmer_selected',
        if (!kIsWeb) 'simulation_assessment': _simulation,
        'evidence_type': 'farmer_reported',
        'selected_option': _chosen,
        'reason': _reason.text.trim(),
        'strategies': [
          for (var i = 0; i < 3; i++)
            {
              'name': _names[i],
              'seasons': [..._sequences[i]],
            },
        ],
        'suitability': 'not_determined',
        'limitations': [
          'Unreviewed crop rules remain blocked.',
          'No yield, income, irrigation or fertilizer benefit has been established.',
        ],
      }, queue: true);
      ref.read(localRevisionProvider.notifier).changed();
      if (mounted) {
        setState(
          () => _message = 'Your rotation decision is saved on this device.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _message = 'Could not save: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _reopen(Map<String, dynamic> plan) {
    final strategies = plan['strategies'] as List;
    setState(() {
      for (var i = 0; i < 3; i++) {
        final seasons = (strategies[i] as Map)['seasons'] as List;
        for (var j = 0; j < 3; j++) {
          _sequences[i][j] = seasons[j] as String?;
        }
      }
      _simulation = plan['simulation_assessment'] is Map ? Map<String,dynamic>.from(plan['simulation_assessment'] as Map) : null;
      _chosen = plan['selected_option'] as int?;
      _reason.text = plan['reason'] as String? ?? '';
      _message = 'Saved decision opened. Saving creates a new dated decision.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(savedRotationPlansProvider);
    return FsPage(
      title: 'Crop rotation decisions',
      children: [
        Padding(
          padding: const EdgeInsets.all(FsSpace.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!kIsWeb) ...[
                const SimulationBanner(),
              ],
              Text(
                'Compare your next three seasons',
                style: context.type.title2,
              ),
              const SizedBox(height: FsSpace.sm),
              const Text(
                'Enter your existing three-crop sequence. In the simulation, the Rust engine generates two alternatives and explains the comparison before you choose.',
              ),
              const SizedBox(height: FsSpace.md),
              for (var i = 0; i < (kIsWeb ? 3 : 1); i++)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(FsSpace.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(_names[i], style: context.type.headline),
                        for (var j = 0; j < 3; j++)
                          Padding(
                            padding: const EdgeInsets.only(top: FsSpace.sm),
                            child: DropdownButtonFormField<String>(
                              key: ValueKey(
                                'rotation-$i-$j-${_sequences[i][j]}',
                              ),
                              initialValue: _sequences[i][j],
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Season ${j + 1} crop',
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('Not decided'),
                                ),
                                for (final crop in Crops.options.entries)
                                  DropdownMenuItem(
                                    value: crop.key,
                                    child: Text(crop.value),
                                  ),
                              ],
                              onChanged: (crop) => setState(() { _sequences[i][j] = crop; _simulation = null; }),
                            ),
                          ),
                        const SizedBox(height: FsSpace.sm),
                        OutlinedButton.icon(
                          onPressed: () => setState(() => _chosen = i),
                          icon: Icon(
                            _chosen == i
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                          ),
                          label: Text(
                            _chosen == i
                                ? 'My selected plan'
                                : 'Choose this plan',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: FsSpace.md),
              if (!kIsWeb)
                RotationSimulator(initialResult: _simulation, onChosen: (index) => setState(() => _chosen = index), onInvalidated: () => setState(() => _simulation = null), baseline: List<String?>.of(_sequences[0]), onGenerated: (alternatives, result) => setState(() {
                  for (var i = 0; i < alternatives.length && i < 2; i++) { _sequences[i + 1] = alternatives[i].cast<String?>(); }
                  _simulation = result;
                  _chosen = null;
                })),
              if (!kIsWeb && _chosen != null) Text(_chosen == 0 ? 'Your selection: existing plan' : 'Your selection: Alternative $_chosen', style: context.type.headline),
              Text('Evidence to review', style: context.type.headline),
              const Text(
                'Crop suitability is not yet determined. Historical comparisons do not predict future yield or certify a crop recommendation.',
              ),
              Wrap(
                spacing: FsSpace.sm,
                runSpacing: FsSpace.sm,
                children: [
                  TextButton.icon(
                    onPressed: () => context.push('/soil-map'),
                    icon: const Icon(Icons.layers_outlined),
                    label: const Text('Soil properties'),
                  ),
                  TextButton.icon(
                    onPressed: () => context.push('/historical'),
                    icon: const Icon(Icons.history),
                    label: const Text('Historical timeline'),
                  ),
                  TextButton.icon(
                    onPressed: () => context.push('/rotations'),
                    icon: const Icon(Icons.compare_arrows),
                    label: const Text('Detailed evidence comparison'),
                  ),
                  TextButton.icon(
                    onPressed: () => context.push('/crop-intelligence'),
                    icon: const Icon(Icons.menu_book),
                    label: const Text('Crop references'),
                  ),
                ],
              ),
              TextField(
                controller: _reason,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Why I chose this plan (optional)',
                ),
              ),
              const SizedBox(height: FsSpace.md),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save my rotation decision'),
              ),
              if (_saving) const LinearProgressIndicator(),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.all(FsSpace.sm),
                  child: Text(_message!),
                ),
              TextButton(
                onPressed: () => context.push('/tasks'),
                child: const Text('Create a planting or field-check task'),
              ),
              const SizedBox(height: FsSpace.md),
              Text('Saved decisions', style: context.type.title2),
              saved.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, _) =>
                    Text('Saved decisions could not open: $error'),
                data: (plans) => Column(
                  children: [
                    if (plans.isEmpty)
                      const Text(
                        'Your saved choices will appear here, including offline.',
                      ),
                    for (final plan in plans)
                      ListTile(
                        title: Text(
                          _names[(plan['selected_option'] as int?) ?? 0],
                        ),
                        subtitle: Text(
                          '${plan['created_at']} · Farmer-selected · Suitability unknown',
                        ),
                        onTap: () => _reopen(plan),
                        trailing: IconButton(
                          tooltip: 'Delete saved decision',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final farm = (await ref.read(
                              selectedFarmBridgeProvider.future,
                            )).farm;
                            if (farm == null) return;
                            await (await ref.read(
                              localFarmStoreProvider.future,
                            )).remove(
                              farm.id,
                              'rotation_plan',
                              plan['id'] as String,
                            );
                            ref.read(localRevisionProvider.notifier).changed();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
