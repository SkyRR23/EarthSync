import 'historical_reference.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../src/rust/api/bridge.dart' as rust;
import '../data/engine/rust_engine.dart';
import '../data/models/farmer_input.dart';
import '../state/providers.dart';
import 'simulation_clock.dart';

class RotationSimulator extends ConsumerStatefulWidget {
  const RotationSimulator({super.key, required this.baseline, required this.onGenerated, required this.onChosen, required this.onInvalidated, this.initialResult});
  final List<String?> baseline;
  final Map<String,dynamic>? initialResult;
  final ValueChanged<int> onChosen;
  final VoidCallback onInvalidated;
  final void Function(List<List<String>>, Map<String, dynamic>) onGenerated;
  @override
  ConsumerState<RotationSimulator> createState() => _RotationSimulatorState();
}

class _RotationSimulatorState extends ConsumerState<RotationSimulator> {
  bool _busy = false;
  int _months = 4;
  bool _diversity = true;
  Map<String, dynamic>? _result;
  String? _error;
  @override
  void initState() {
    super.initState();
    _result = widget.initialResult;
    _months = (_result?['season_months'] as num?)?.toInt() ?? 4;
  }
  @override
  void didUpdateWidget(covariant RotationSimulator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.baseline.join('|') != widget.baseline.join('|')) _result = null;
    if (oldWidget.initialResult != widget.initialResult) {
      _result = widget.initialResult;
      _months = (_result?['season_months'] as num?)?.toInt() ?? _months;
    }
  }
  Future<void> _run() async {
    setState(() { _busy = true; _error = null; _result = null; });
    try {
      final bundle = jsonDecode(await rootBundle.loadString('assets/fixtures/rotation_reference_context.json')) as Map<String, dynamic>;
      if (!mounted) return;
      final date = ref.read(simulationClockProvider);
      final state = ref.read(analysisProvider);
      final climate = state is AnalysisReady ? state.analysis.climateSummary : null;
      final draft = ref.read(farmerDraftProvider);
      final window = ref.read(historicalWindowProvider);
      final sameYear = window.startYear == date.year && window.endYear == date.year;
      final usingReference = ref.read(referenceChoiceProvider);
      final reference = usingReference ? await ref.read(historicalReferenceProvider.future) : null;
      if (!mounted) return;
      final historicalMonths = usingReference ? <Map<String,dynamic>>[for(final m in reference?['months'] as List? ?? []) if(m['year'] == date.year) Map<String,dynamic>.from(m as Map)] : <Map<String,dynamic>>[if (sameYear && climate != null) for (final m in climate.months) if (m.year == date.year) {'month':m.month,'temp_c':m.tempMeanC,'rain_mm':m.rainMm}];
      final request = {
        'schema_version': 'earthsync.simulation.v1',
        'simulation_date': date.toIso8601String().substring(0, 10),
        'data_year': date.year,
        'start_month': draft.plantingMonth == null || draft.plantingMonth == 0 ? date.month : draft.plantingMonth,
        'season_months': _months,
        'prefer_diversity': _diversity,
        'baseline': widget.baseline,
        'irrigated': draft.irrigation == Irrigation.full ? true : draft.irrigation == Irrigation.none ? false : null,
        'months': historicalMonths,
        'climate_source': usingReference ? 'Archived Yangon reference point 16.85, 96.15; not the saved field' : climate?.sourceId,
        'climate_source_hash': reference?['source_sha256'],
        'profiles': bundle['profiles'], 'sources': bundle['sources'],
      };
      await RustEngine.init();
      final output = jsonDecode(await rust.analyzeIntegrationJson(requestJson: jsonEncode(request))) as Map<String, dynamic>;
      if (!mounted) return;
      if ((request['baseline'] as List).join('|') != widget.baseline.join('|') || request['simulation_date'] != ref.read(simulationClockProvider).toIso8601String().substring(0,10)) throw StateError('The plan or simulation date changed. Compare again.');
      if (output['status'] != 'success') throw StateError(output['message'] ?? 'Simulation could not run.');
      setState(() => _result = output);
      widget.onGenerated([for (final option in output['alternatives'] as List) (option['crops'] as List).cast<String>()], output);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final date = ref.watch(simulationClockProvider);
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Compare alternative rotations', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      Text('Historical analog: ${date.year}. Enter your existing three-crop plan, then generate two alternatives. This is an exploratory simulation.'),
      Text(ref.watch(referenceChoiceProvider) ? 'Using the explicit offline Yangon reference, not readings from your field.' : 'Using loaded historical field context. Open Weather to load data or select the offline reference.'),
      DropdownButtonFormField<int>(key: ValueKey('months:$_months'), initialValue: _months, decoration: const InputDecoration(labelText: 'Assumed length of each season'), items: [for (final n in [2,3,4,6]) DropdownMenuItem(value: n, child: Text('$n months · simulation assumption'))], onChanged: _busy ? null : (n) { setState(() { _months = n ?? 4; _result = null; }); widget.onInvalidated(); }),
      SwitchListTile(title: const Text('Prefer crop-family diversity in this simulation'), subtitle: const Text('A planning objective, not a guaranteed pest or soil benefit'), value: _diversity, onChanged: _busy ? null : (value) {setState(() { _diversity = value; _result = null; }); widget.onInvalidated();}),
      FilledButton.icon(onPressed: _busy ? null : _run, icon: const Icon(Icons.compare_arrows), label: Text(_busy ? 'Comparing your options…' : 'Generate & compare alternatives')),
      if (_error != null) Text(_error!),
      if (_result != null && _result!['simulation_date'] == date.toIso8601String().substring(0,10)) ...[
        Text(_result!['recommendation'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
        for (final entry in [ {'name':'Existing plan', 'result':_result!['baseline']}, for (final (i, option) in (_result!['alternatives'] as List).indexed) {'name':'Alternative ${i+1}', 'result': option} ])
          ExpansionTile(title: Text(entry['name'] as String), subtitle: Text('${((entry['result'] as Map)['crops'] as List).map((c) => Crops.label(c as String?)).join(' → ')}\nReference mismatches: ${(entry['result'] as Map)['reference_conflicts']} · comparisons with data: ${(entry['result'] as Map)['known_comparisons']}'), children: [for (final finding in (entry['result'] as Map)['findings'] as List) ListTile(title: Text(Crops.label(finding['crop'] as String?)), subtitle: Text(finding['reason'] as String))]),
        Wrap(spacing: 8, children: [for (var i = 0; i <= (_result!['alternatives'] as List).length; i++) OutlinedButton(onPressed: () => widget.onChosen(i), child: Text(i == 0 ? 'Keep existing plan' : 'Choose Alternative $i'))]),
        ExpansionTile(title: const Text('Assumptions and sources'), children: [for (final limit in _result!['limitations'] as List) ListTile(title: Text('$limit')), for (final source in _result!['sources'] as List) ListTile(title: Text('${source['title'] ?? source['id']}'), subtitle: SelectableText('${source['url'] ?? 'URL unavailable'}'))]),
      ],
    ])));
  }
}
