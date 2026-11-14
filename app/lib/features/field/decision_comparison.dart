import 'package:flutter/material.dart';
import '../../data/farm_journal.dart';
import '../../data/engine/v03_engine.dart';
import '../../design/components/product.dart';
import '../companion/companion_copy.dart';
import 'assessment_screen.dart';
import 'evidence_panels.dart';

/// Extends 7X's immutable assessment comparison with a declared baseline,
/// multiple alternatives, explicit preferences and persistent group callbacks.
class DecisionComparison extends StatefulWidget {
  const DecisionComparison({
    super.key,
    required this.decisions,
    this.initialComparison,
    this.onSave,
    this.onEdit,
  });
  final List<Map<String, dynamic>> decisions;
  final Map<String, dynamic>? initialComparison;
  final Future<void> Function(Map<String, dynamic>)? onSave;
  final ValueChanged<String>? onEdit;
  @override
  State<DecisionComparison> createState() => _DecisionComparisonState();
}

class _DecisionComparisonState extends State<DecisionComparison> {
  late List<String?> _selected;
  final _priorities = <String>{};
  final _name = TextEditingController(),
      _reason = TextEditingController(),
      _limits = TextEditingController();
  bool _declared = false, _busy = false;
  String? _choice, _error;
  String _id = journalId();
  @override
  void initState() {
    super.initState();
    final saved = widget.initialComparison;
    _selected = saved == null
        ? [null, null, null]
        : [
            saved['baseline_decision_id'] as String,
            ...(saved['alternative_decision_ids'] as List).cast<String>(),
          ];
    _name.text = saved?['name'] as String? ?? '';
    _reason.text = saved?['exploration_reason'] as String? ?? '';
    _limits.text = saved?['practical_constraints'] as String? ?? '';
    _priorities.addAll((saved?['priorities'] as List? ?? []).cast<String>());
    _declared = saved?['baseline_declared_existing_plan'] == true;
    _choice = saved?['chosen_decision_id'] as String?;
  }

  @override
  void dispose() {
    _name.dispose();
    _reason.dispose();
    _limits.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String tr(String text) => CompanionCopy.text(context, text);
    final ids = widget.decisions.map((d) => d['id'] as String).toSet();
    final selectedIds = _selected.whereType<String>().toList();
    final complete =
        selectedIds.length == _selected.length &&
        selectedIds.toSet().length == selectedIds.length &&
        selectedIds.every(ids.contains);
    final selected = [
      for (final id in _selected)
        if (id != null && ids.contains(id))
          widget.decisions.firstWhere((d) => d['id'] == id),
    ];
    return SectionCard(
      title: 'Compare baseline and alternative rotations',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Choose at least three saved rotation sequences. Declare your existing plan as the baseline; alternatives are proposals to explore. No preferred crop, score or guaranteed rotation benefit is inferred. Different source snapshots and history can affect results.',
          ),
          if (widget.decisions.length < 3)
            const Text(
              'Save at least three separate two-crop sequences first: your existing plan, alternative A and alternative B.',
            ),
          for (var i = 0; i < _selected.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: DropdownButtonFormField<String>(
                key: ValueKey('strategy:$i:${_selected[i]}'),
                initialValue: ids.contains(_selected[i]) ? _selected[i] : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: i == 0
                      ? 'Baseline · farmer-declared existing plan'
                      : 'Alternative ${String.fromCharCode(64 + i)} saved decision',
                ),
                items: [
                  for (final d in widget.decisions)
                    DropdownMenuItem(
                      value: d['id'] as String,
                      child: Text(
                        _decisionLabel(d),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(() {
                        _selected[i] = v;
                        _choice = null;
                        _declared = false;
                      }),
              ),
            ),
          if (_selected.length < 6)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _selected.add(null)),
              child: const Text('Add another strategy'),
            ),
          if (_selected.length > 3)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _selected.removeLast();
                      _choice = null;
                    }),
              child: const Text('Remove last strategy'),
            ),
          if (!complete && selectedIds.isNotEmpty)
            const Text('Select different saved decisions for every strategy.'),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _declared,
            title: const Text(
              'I declare that the baseline reflects my existing plan',
            ),
            subtitle: const Text(
              'This is a farmer declaration, not an invented rotation or a recommendation. Completed operations must be recorded in farm history separately.',
            ),
            onChanged: _busy
                ? null
                : (v) => setState(() => _declared = v == true),
          ),
          TextField(
            controller: _name,
            maxLength: 150,
            decoration: const InputDecoration(
              labelText: 'Name this comparison',
            ),
          ),
          TextField(
            controller: _reason,
            maxLength: 1000,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Why are you exploring these strategies?',
            ),
          ),
          Text(tr('Farmer priorities')),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final p in farmerPriorityLabels.entries)
                FilterChip(
                  label: Text(tr(p.value)),
                  selected: _priorities.contains(p.key),
                  onSelected: _busy
                      ? null
                      : (yes) => setState(() {
                          yes
                              ? _priorities.add(p.key)
                              : _priorities.remove(p.key);
                        }),
                ),
            ],
          ),
          TextField(
            controller: _limits,
            maxLength: 1000,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText:
                  'Irrigation, budget, labor, equipment & other practical constraints',
            ),
          ),
          if (complete) ...[
            DropdownButtonFormField<String>(
              key: ValueKey('choice:$_choice'),
              initialValue: _choice,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Your choice (optional; never a scientific ranking)',
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Undecided')),
                for (final (i, d) in selected.indexed)
                  DropdownMenuItem(
                    value: d['id'] as String,
                    child: Text(
                      i == 0
                          ? 'Baseline'
                          : 'Alternative ${String.fromCharCode(64 + i)}',
                    ),
                  ),
              ],
              onChanged: _busy ? null : (v) => setState(() => _choice = v),
            ),
            LayoutBuilder(
              builder: (_, box) {
                final columns = box.maxWidth >= 900
                    ? 3
                    : box.maxWidth >= 700
                    ? 2
                    : 1;
                final width = (box.maxWidth - (columns - 1) * 16) / columns;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final (i, d) in selected.indexed)
                      SizedBox(
                        width: width,
                        child: _SavedAlternative(
                          label: i == 0
                              ? 'Baseline · existing plan'
                              : 'Alternative ${String.fromCharCode(64 + i)}',
                          decision: d,
                          priorities: _priorities.toList(),
                          baseline: selected.first,
                          reason: _reason.text,
                          constraints: _limits.text,
                          onEdit: widget.onEdit == null
                              ? null
                              : () => widget.onEdit!(d['id'] as String),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
          if (widget.onSave != null)
            FilledButton.icon(
              icon: const Icon(Icons.save_outlined),
              onPressed: _busy || !complete || !_declared
                  ? null
                  : () async {
                      if (_name.text.trim().isEmpty ||
                          _reason.text.trim().isEmpty) {
                        setState(
                          () => _error =
                              'Give the comparison a name and a reason to explore it.',
                        );
                        return;
                      }
                      if (!await confirmAction(
                            context,
                            title: 'Save this declared comparison?',
                            message:
                                'This saves your baseline declaration, chosen alternatives, priorities and optional choice. It does not approve crop suitability or guarantee benefits.',
                            confirmLabel: 'Save comparison',
                          ) ||
                          !context.mounted) {
                        return;
                      }
                      setState(() {
                        _busy = true;
                        _error = null;
                      });
                      try {
                        await widget.onSave!({
                          'schema_version': 'earthsync.comparison.v1',
                          'id': _id,
                          'name': _name.text.trim(),
                          'baseline_decision_id': selectedIds.first,
                          'alternative_decision_ids': selectedIds
                              .skip(1)
                              .toList(),
                          'baseline_declared_existing_plan': true,
                          'chosen_decision_id': _choice,
                          'priorities': _priorities.toList(),
                          'practical_constraints': _limits.text.trim(),
                          'exploration_reason': _reason.text.trim(),
                        });
                        if (mounted) {
                          setState(() {
                            _id = journalId();
                            _error =
                                'Comparison saved. Reopen it from saved comparisons.';
                          });
                        }
                      } catch (e) {
                        if (mounted) {
                          setState(
                            () => _error =
                                'Could not save: $e. Inspect saved comparisons before retrying.',
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              label: const Text('Confirm & save comparison'),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
        ],
      ),
    );
  }
}

String _decisionLabel(Map<String, dynamic> d) {
  final scenarios =
      d['assessment']?['result']?['data']?['context']?['scenarios'] as List? ??
      [];
  final sequence = [
    for (final s in scenarios)
      for (final p in s['plans'] as List) p['profile_id'] ?? 'Crop unknown',
  ].join(' → ');
  return '$sequence · ${d['assessment']['assessed_at']} · ${d['id']}';
}

class _SavedAlternative extends StatelessWidget {
  const _SavedAlternative({
    required this.label,
    required this.decision,
    this.priorities = const [],
    this.reason = '',
    this.constraints = '',
    this.onEdit,
    this.baseline,
  });
  final Map<String, dynamic>? baseline;
  final String label;
  final Map<String, dynamic> decision;
  final List<String> priorities;
  final String reason, constraints;
  final VoidCallback? onEdit;

  String date(Map value) =>
      '${value['year']}-${'${value['month']}'.padLeft(2, '0')}-${'${value['day']}'.padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final assessment = decision['assessment'] as Map;
    final result = Map<String, dynamic>.from(assessment['result'] as Map);
    final data = result['data'] as Map?;
    final contextData = data?['context'] as Map?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$label · ${decision['id']}'),
        Text('Assessed: ${assessment['assessed_at']}'),
        if (baseline != null && baseline!['id'] != decision['id'])
          _InputChanges(baseline: baseline!, alternative: decision),
        Text(
          'Why explored (farmer declaration): ${reason.isEmpty ? 'Not recorded' : reason}',
        ),
        Text(
          'Practical constraints (farmer declaration): ${constraints.isEmpty ? 'Unknown' : constraints}',
        ),
        if (onEdit != null)
          TextButton(
            onPressed: onEdit,
            child: const Text('Edit as a new proposal'),
          ),

        for (final scenario in (contextData?['scenarios'] as List?) ?? [])
          for (final plan in scenario['plans'] as List)
            Text(
              '${plan['profile_id']} · ${date(plan['period']['start'] as Map)} → ${date(plan['period']['end'] as Map)} · declared ${plan['system']}',
            ),
        _StrategyEvidence(
          assessment: Map<String, dynamic>.from(assessment),
          priorities: priorities,
        ),
        V03ResultPanel(result: V03Result.decode(result)),
        EvidenceDetails(
          title: '$label reference scope, sources and missing requirements',
          data: {
            'catalog_projection': assessment['catalog_projection'],
            'evidence': assessment['evidence'],
            'evidence_gaps': assessment['evidence_gaps'],
            'water_findings': assessment['water_findings'],
            'history': contextData?['history'],
            'history_complete': contextData?['history_complete'],
            'engine_binary_sha256': assessment['engine_binary_sha256'],
          },
        ),
      ],
    );
  }
}

String referenceValue(Object? value) {
  if (value == null) return 'Unknown';
  if (value is Map) {
    return value.entries
        .map((e) => '${e.key}: ${referenceValue(e.value)}')
        .join('; ');
  }
  if (value is List) return value.map(referenceValue).join(', ');
  return '$value';
}

class _StrategyEvidence extends StatelessWidget {
  const _StrategyEvidence({required this.assessment, required this.priorities});
  final Map<String, dynamic> assessment;
  final List<String> priorities;
  @override
  Widget build(BuildContext context) {
    final projections = assessment['catalog_projection'] as List? ?? [];
    final evidence = assessment['evidence'] as List? ?? [];
    final reports = assessment['farmer_reports'] as List? ?? [];
    final environmentalSnapshots =
        assessment['environmental_snapshots'] as List? ?? [];
    final contextData = assessment['result']?['data']?['context'] as Map?;
    const traits = {
      'Nitrogen-fixing potential': ['nitrogen_fixation'],
      'Ground cover': ['ground_cover'],
      'Organic matter contributions': ['organic_matter_contribution'],
      'Root characteristics': ['ecological_soil_depth', 'rooting_depth'],
      'Forage value': ['forage_value'],
      'Erosion-related considerations': ['erosion_protection'],
      'Water-use characteristics': ['water_demand', 'kc_stages'],
      'Pest-cycle considerations': ['pest_cycle'],
    };
    const matchingParameters = {
      'less_water': ['water_demand', 'kc_stages', 'growing_period_rainfall'],
      'soil': [
        'soil_ph_by_depth',
        'ecological_soil_ph',
        'ecological_soil_depth',
        'soil_texture',
      ],
      'nitrogen_potential': ['nitrogen_fixation'],
      'erosion': ['erosion_protection'],
      'forage': ['forage_value'],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExpansionTile(
          title: const Text('NASA, soil & water context'),
          initiallyExpanded: true,
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final job in environmentalSnapshots) ...[
              Text(
                'Selected source reference: ${job['kind']} · ${job['result']['provider']} · retrieved ${job['result']['retrieved_at'] ?? 'Unknown'}',
              ),
              if (job['kind'] == 'soil_map') ...[
                Text(
                  'Modeled pH mean at ${job['result']['depth_cm']} cm · native ${job['result']['resolution_m']} m grid; not a farm laboratory measurement.',
                ),
                for (final cell in job['result']['cells'] as List? ?? [])
                  if (cell['at_query_point'] == true)
                    Text(
                      'Native cell covering the query point: ${cell['value'] ?? 'Unknown'} pH · ${cell['quality']} · uncertainty intervals unavailable.',
                    ),
                Text(
                  'Source: ${job['result']['source_url']} · SHA-256 ${job['result']['source_sha256']}',
                ),
              ],
              if (job['kind'] == 'forecast') ...[
                Text(
                  'NOAA regional ${job['result']['grid_spacing_degrees']}° grid · model initialized ${job['result']['model_initialized_at']} · publication time unavailable.',
                ),
                for (final r in job['result']['records'] as List? ?? [])
                  Text(
                    '${r['valid_at']} · ${r['temperature_c'] ?? 'Unknown'} ${r['unit']} · original forecast, not historical crop-period evidence',
                  ),
                const Text(
                  'Check original valid times before use; older snapshots may have expired. Official warnings and current observed weather are unavailable.',
                ),
              ],
              if (job['kind'] == 'optical_discovery')
                const Text(
                  'Satellite metadata discovery only. No validated NDVI pixels or crop-stress conclusion.',
                ),
              const Text(
                'Reference context is retained with this saved strategy; it does not activate Rust suitability rules.',
              ),
            ],
            if (evidence.isEmpty)
              const Text(
                'No environmental snapshot selected. Retrieve and explicitly select accepted NASA evidence before reassessing.',
              ),
            for (final e in evidence)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${e['provider']} · ${e['dataset']} · ${e['data_type']}',
                    ),
                    Text(
                      '${e['temporal']['start'] ?? e['temporal']['acquired_at'] ?? 'Time unknown'} → ${e['temporal']['end'] ?? ''} · retrieved ${e['temporal']['retrieved_at']}',
                    ),
                    Text(
                      '${e['spatial']['support']} · native resolution: ${e['spatial']['resolution_m'] ?? e['spatial']['resolution_degrees'] ?? 'Unquantified'}',
                    ),
                    if (e['source_metadata']?['calculation']
                        case final Map calculation)
                      Text(
                        'Rust reference ET0: ${calculation['et0_total_mm'] ?? 'Unknown'} mm; rainfall: ${calculation['rainfall_total_mm'] ?? 'Unknown'} mm. ETc and irrigation remain unknown without accepted crop/field evidence.',
                      ),
                    Text('Source: ${e['source_url']} · ${e['review']}'),
                  ],
                ),
              ),
            for (final r in reports)
              Text(
                'Farmer report ${r['occurred_on']}: irrigation ${r['irrigation']}, drainage ${r['drainage']}, water access ${r['water_access']}. ${r['soil_test'] == null ? '' : 'Soil test as reported: ${referenceValue(r['soil_test'])}'}',
              ),
            if (!evidence.any(
                  (e) => (e['measurements'] as List? ?? []).any(
                    (m) => [
                      'ph',
                      'organic_carbon',
                      'soil_moisture',
                    ].contains(m['variable']),
                  ),
                ) &&
                !reports.any((r) => r['soil_test'] != null))
              const Text(
                'No applicable soil test/property selected. Soil conditions remain unknown.',
              ),
            const Text(
              'Regional grids are not exact field measurements. Forecasts, satellite observations and farmer reports retain distinct dates, quality and units; none is silently substituted for NASA historical climate.',
            ),
          ],
        ),
        ExpansionTile(
          title: const Text('Current / prior reported crop history'),
          children: [
            if ((contextData?['history'] as List? ?? []).isEmpty)
              const Text(
                'No completed crop history supplied to this assessment. History completeness is unknown.',
              ),
            for (final h in contextData?['history'] as List? ?? [])
              ListTile(
                title: Text(
                  h['fallow'] == true
                      ? 'Declared fallow'
                      : '${h['crop_id'] ?? 'Crop unknown'}',
                ),
                subtitle: Text(
                  '${referenceValue(h['period'])} · farmer reported',
                ),
              ),
          ],
        ),
        ExpansionTile(
          title: const Text('Crop characteristics & possible benefits'),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'No field benefit is independently established. Crop characteristics are reference facts, not guaranteed nitrogen credit, income, pest prevention or erosion reduction.',
            ),
            for (final sidecar in projections) ...[
              Text(
                '${sidecar['profile']['id']} · ${sidecar['profile']['production_system']} · ${sidecar['profile']['region_id'] ?? 'Global reference'}',
              ),
              if (sidecar['qualitative_identity'] case final Map identity) ...[
                Text(
                  'Reference identity: ${identity['crop']['scientific_name']}; family ${identity['crop']['family']}; recorded use categories: ${referenceValue(identity['crop']['categories'])}.',
                ),
                Text(
                  'Citation: ${identity['source']['title']} · ${identity['source']['url']}',
                ),
                Text(identity['limitation'] as String),
              ],
              for (final trait in traits.entries) ...[
                Text(
                  '${trait.key}: ${trait.value.any((key) => sidecar['profile']['parameters'][key]?['state'] == 'available') ? 'Reference characteristic available below; local benefit unverified.' : 'Insufficient applicable trait evidence.'}',
                ),
              ],
              for (final p in (sidecar['profile']['parameters'] as Map).entries)
                if (p.value['state'] == 'available')
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '${p.key.toString().replaceAll('_', ' ')}: ${referenceValue(p.value['value'])} ${p.value['unit'] ?? ''}. ${p.value['statistic']}\nScope: ${p.value['spatial_support']}. Claims: ${(p.value['claim_ids'] as List).join(', ')}',
                    ),
                  ),
              for (final source in sidecar['sources'] as List? ?? [])
                Text(
                  'Citation: ${source['publisher']} · ${source['title']} · ${source['url']} · source version ${source['version']} · retrieved ${source['retrieved_at'] ?? source['retrieval_date'] ?? 'Unknown'}',
                ),
            ],
          ],
        ),
        ExpansionTile(
          title: const Text('Priority alignment & practical limits'),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (priorities.isEmpty)
              const Text('No comparison priorities declared.'),
            for (final priority in priorities)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Text(
                  '${farmerPriorityLabels[priority] ?? priority}: ${projections.any((s) => (matchingParameters[priority] ?? []).any((key) => s['profile']['parameters'][key]?['state'] == 'available')) ? 'Related reference information exists in the characteristics panel. Farm alignment still requires applicable soil, water, cultivar and management evidence.' : 'Cannot yet evaluate alignment from supplied source evidence.'}',
                ),
              ),
            const Text(
              'Budget, labor, equipment, irrigation access and market interests are farmer-declared constraints. Prices, profits, market access and numerical priority weights are not inferred.',
            ),
          ],
        ),
        const Text(
          'Local review required: confirm crop identity/cultivar, production system, soil depth, water delivery, planting windows and source applicability. All 60 reviewed crop-rule candidates remain blocked; zero executable suitability recommendations are approved.',
        ),
      ],
    );
  }
}

class _InputChanges extends StatelessWidget {
  const _InputChanges({required this.baseline, required this.alternative});
  final Map<String, dynamic> baseline, alternative;
  @override
  Widget build(BuildContext context) {
    final before = baseline['assessment'] as Map,
        after = alternative['assessment'] as Map;
    Set<String> sourceIds(Map a) => {
      for (final e in a['evidence'] as List? ?? []) e['id'] as String,
      for (final e in a['environmental_snapshots'] as List? ?? [])
        e['id'] as String,
    };
    final old = sourceIds(before), current = sourceIds(after);
    return Text(
      'Compared with the baseline: ${current.difference(old).length} source snapshots added; ${old.difference(current).length} removed. Declared sequences and dates are shown below. Input changes do not establish agricultural improvement.',
    );
  }
}
