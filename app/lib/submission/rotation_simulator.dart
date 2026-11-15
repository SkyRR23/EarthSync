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

// Saved assessments must match the inputs they actually compared, including
// source changes on the same simulation day. Keep this local provenance out of
// the native bridge contract.
final rotationContextKeyProvider = Provider<String>((ref) {
  final date = ref.watch(simulationClockProvider);
  final reference = ref.watch(referenceChoiceProvider);
  final draft = ref.watch(farmerDraftProvider);
  final window = ref.watch(historicalWindowProvider);
  final analysis = ref.watch(analysisProvider);
  return jsonEncode({
    'version': 1,
    'date': date.toIso8601String().substring(0, 10),
    'reference': reference,
    'field': [draft.fieldLatitude, draft.fieldLongitude],
    'boundary': draft.farm?.toJson(),
    'planting_month': draft.plantingMonth,
    'irrigation': draft.irrigation?.name,
    if (!reference) 'window': [window.startYear, window.endYear],
    if (!reference) 'climate': analysis is AnalysisReady ? {
      'source': analysis.analysis.climateSummary.sourceId,
      'months': [for (final m in analysis.analysis.climateSummary.months)
        [m.year, m.month, m.tempMeanC, m.rainMm]],
    } : null,
  });
});

bool rotationAssessmentIsCurrent(Map<String, dynamic>? result,
    String contextKey, List<String?> baseline) {
  final saved = result?['baseline'];
  return result?['input_context_key'] == contextKey && saved is Map &&
      saved['crops'] is List && (saved['crops'] as List).join('|') == baseline.join('|');
}

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
  String _water = 'saved';
  Map<String, dynamic>? _result;
  String? _error;
  @override
  void initState() {
    super.initState();
    _result = widget.initialResult;
    _months = (_result?['season_months'] as num?)?.toInt() ?? 4;
    _diversity = _result?['prefer_diversity'] as bool? ?? true;
    _water = _result?['water_scenario'] as String? ?? 'saved';
  }
  @override
  void didUpdateWidget(covariant RotationSimulator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.baseline.join('|') != widget.baseline.join('|')) _result = null;
    if (oldWidget.initialResult != widget.initialResult) {
      _result = widget.initialResult;
      _months = (_result?['season_months'] as num?)?.toInt() ?? _months;
      _diversity = _result?['prefer_diversity'] as bool? ?? _diversity;
      _water = _result?['water_scenario'] as String? ?? _water;
    }
  }
  Future<void> _run() async {
    final contextKey = ref.read(rotationContextKeyProvider);
    final baseline = List<String?>.of(widget.baseline);
    final date = ref.read(simulationClockProvider);
    final draft = ref.read(farmerDraftProvider);
    final state = ref.read(analysisProvider);
    final window = ref.read(historicalWindowProvider);
    final usingReference = ref.read(referenceChoiceProvider);
    final months = _months;
    final diversity = _diversity;
    final water = _water;
    widget.onInvalidated();
    setState(() { _busy = true; _error = null; _result = null; });
    try {
      final bundle = jsonDecode(await rootBundle.loadString('assets/fixtures/rotation_reference_context.json')) as Map<String, dynamic>;
      if (!mounted) return;
      final climate = state is AnalysisReady ? state.analysis.climateSummary : null;
      final sameYear = window.startYear == date.year && window.endYear == date.year;
      final reference = usingReference ? await ref.read(historicalReferenceProvider.future) : null;
      if (!mounted) return;
      final historicalMonths = usingReference ? <Map<String,dynamic>>[for(final m in reference?['months'] as List? ?? []) if(m['year'] == date.year) Map<String,dynamic>.from(m as Map)] : <Map<String,dynamic>>[if (sameYear && climate != null) for (final m in climate.months) if (m.year == date.year) {'month':m.month,'temp_c':m.tempMeanC,'rain_mm':m.rainMm}];
      final request = {
        'schema_version': 'earthsync.simulation.v1',
        'simulation_date': date.toIso8601String().substring(0, 10),
        'data_year': date.year,
        'start_month': draft.plantingMonth == null || draft.plantingMonth == 0 ? date.month : draft.plantingMonth,
        'season_months': months,
        'prefer_diversity': diversity,
        'baseline': baseline,
        'irrigated': switch (water) {
          'rainfed' => false,
          'irrigated' => true,
          _ => draft.irrigation == Irrigation.full ? true : draft.irrigation == Irrigation.none ? false : null,
        },
        'months': historicalMonths,
        'climate_source': usingReference ? 'Archived Yangon reference point 16.85, 96.15; not the saved field' : climate?.sourceId,
        'climate_source_hash': reference?['source_sha256'],
        'profiles': bundle['profiles'], 'sources': bundle['sources'],
      };
      await RustEngine.init();
      final output = jsonDecode(await rust.analyzeIntegrationJson(requestJson: jsonEncode(request))) as Map<String, dynamic>;
      if (!mounted) return;
      if (baseline.join('|') != widget.baseline.join('|') || contextKey != ref.read(rotationContextKeyProvider) || months != _months || diversity != _diversity || water != _water) throw StateError('Your plan, date or comparison inputs changed. Compare again.');
      if (output['status'] != 'success') throw StateError(output['message'] ?? 'Simulation could not run.');
      output['input_context_key'] = contextKey;
      output['water_scenario'] = water;
      setState(() => _result = output);
      widget.onGenerated([for (final option in output['alternatives'] as List) (option['crops'] as List).cast<String>()], output);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final date = ref.watch(simulationClockProvider);
    final current = rotationAssessmentIsCurrent(_result,
        ref.watch(rotationContextKeyProvider), widget.baseline);
    final irrigation = ref.watch(farmerDraftProvider.select((d) => d.irrigation));
    final waterLabel = irrigation == Irrigation.none ? 'rain only' :
        irrigation == Irrigation.full ? 'irrigated' : 'water supply not fully known';
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('What could I plant instead?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      Text('Compare two alternatives using ${date.year} history and your chosen assumptions.'),
      Text(ref.watch(referenceChoiceProvider) ? 'Using the explicit offline Yangon reference, not readings from your field.' : 'Using loaded historical field context. Open Weather to load data or select the offline reference.'),
      DropdownButtonFormField<int>(key: ValueKey('months:$_months'), initialValue: _months, decoration: const InputDecoration(labelText: 'Assumed length of each season'), items: [for (final n in [2,3,4,6]) DropdownMenuItem(value: n, child: Text('$n months · simulation assumption'))], onChanged: _busy ? null : (n) { setState(() { _months = n ?? 4; _result = null; }); widget.onInvalidated(); }),
      DropdownButtonFormField<String>(key: ValueKey('water:$_water'), initialValue: _water,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Water supply for this comparison'),
        items: [
          DropdownMenuItem(value: 'saved', child: Text('Saved answer: $waterLabel')),
          const DropdownMenuItem(value: 'rainfed', child: Text('Assume rain only')),
          const DropdownMenuItem(value: 'irrigated', child: Text('Assume irrigation is available')),
        ], onChanged: _busy ? null : (value) {
          setState(() { _water = value ?? 'saved'; _result = null; });
          widget.onInvalidated();
        }),
      const Text('Rain-only comparisons use a complete historical year. Irrigation availability does not tell us how much water is supplied.'),
      SwitchListTile(title: const Text('Prefer crop-family diversity in this simulation'), subtitle: const Text('A planning objective, not a guaranteed pest or soil benefit'), value: _diversity, onChanged: _busy ? null : (value) {setState(() { _diversity = value; _result = null; }); widget.onInvalidated();}),
      FilledButton.icon(onPressed: _busy ? null : _run, icon: const Icon(Icons.compare_arrows), label: Text(_busy ? 'Comparing your options…' : 'Generate & compare alternatives')),
      if (_error != null) Text(_error!),
      if (_result != null && !current) const Text('This comparison belongs to earlier inputs. Generate it again before choosing or saving.'),
      if (_result != null && current) ...[
        Text('${_result!['climate_source'] ?? 'Source not available'}'),
        Text(_result!['recommendation'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
        for (final entry in [ {'name':'Existing plan', 'result':_result!['baseline']}, for (final (i, option) in (_result!['alternatives'] as List).indexed) {'name':'Alternative ${i+1}', 'result': option} ])
          _RotationOption(name: entry['name'] as String,
            result: Map<String,dynamic>.from(entry['result'] as Map),
            start: DateTime(date.year, (_result!['start_month'] as num).toInt()),
            months: (_result!['season_months'] as num).toInt()),
        Wrap(spacing: 8, children: [for (var i = 0; i <= (_result!['alternatives'] as List).length; i++) OutlinedButton(onPressed: () => widget.onChosen(i), child: Text(i == 0 ? 'Keep existing plan' : 'Choose Alternative $i'))]),
        ExpansionTile(title: const Text('Assumptions and sources'), children: [for (final limit in _result!['limitations'] as List) ListTile(title: Text('$limit')), for (final source in _result!['sources'] as List) ListTile(title: Text('${source['title'] ?? source['id']}'), subtitle: SelectableText('${source['url'] ?? 'URL unavailable'}'))]),
      ],
    ])));
  }
}

class _RotationOption extends StatelessWidget {
  const _RotationOption({required this.name, required this.result, required this.start, required this.months});
  final String name;
  final Map<String,dynamic> result;
  final DateTime start;
  final int months;
  static const _names = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  String _month(DateTime date) => '${_names[date.month - 1]} ${date.year}';
  @override
  Widget build(BuildContext context) {
    final crops = result['crops'] as List;
    final known = (result['known_comparisons'] as num).toInt();
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(name, style: Theme.of(context).textTheme.titleMedium),
        for (final (index, crop) in crops.indexed) ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(child: Text('${index + 1}')),
          title: Text(Crops.label(crop as String?)),
          subtitle: Text('${_month(DateTime(start.year, start.month + index * months))} – ${_month(DateTime(start.year, start.month + (index + 1) * months - 1))}'),
        ),
        Text(known == 0 ? 'Climate fit: not enough comparable inputs' :
            '${result['reference_conflicts']} reference mismatches across $known climate checks'),
        Text('${result['family_breaks']} crop-family changes · a diversity measure'),
        ExpansionTile(title: const Text('Why this comparison?'), children: [
          for (final finding in result['findings'] as List) ListTile(
            title: Text(Crops.label(finding['crop'] as String?)),
            subtitle: Text(finding['reason'] as String)),
        ]),
      ])));
  }
}
