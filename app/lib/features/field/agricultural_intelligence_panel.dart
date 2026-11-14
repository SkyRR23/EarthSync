import 'package:flutter/material.dart';
import '../../data/platform_farms.dart';
import '../../data/engine/v03_engine.dart';
import '../../design/components/product.dart';
import 'assessment_screen.dart';
import 'evidence_panels.dart';

/// Values and findings come from immutable server records and compiled Rust.
/// This widget formats them and never computes agricultural quantities.
class AgriculturalIntelligencePanel extends StatefulWidget {
  const AgriculturalIntelligencePanel({
    super.key,
    required this.farm,
    required this.client,
    required this.records,
    required this.onSaved,
    this.initialDecision,
    this.farmerReports = const [],
    this.environmentalSnapshots = const [],
    this.farmerObservations = const [],
  });
  final PlatformFarm farm;
  final PlatformFarmClient client;
  final List<Map<String, dynamic>> records;
  final VoidCallback onSaved;
  final Map<String, dynamic>? initialDecision;
  final List<Map<String, dynamic>> farmerReports,
      environmentalSnapshots,
      farmerObservations;
  @override
  State<AgriculturalIntelligencePanel> createState() => _IntelligenceState();
}

class _IntelligenceState extends State<AgriculturalIntelligencePanel> {
  final _query = TextEditingController(text: 'rice');
  final _start = TextEditingController(), _end = TextEditingController();
  final _nextStart = TextEditingController(),
      _nextEnd = TextEditingController();
  Map<String, dynamic>? _reference, _job, _assessment;
  String? _profile, _second, _error;
  List<String> _evidenceIds = [];
  final _profiles = <String, Map<String, dynamic>>{};
  bool _busy = false;
  final _selectedReports = <String>{},
      _selectedJobs = <String>{},
      _selectedObservations = <String>{};

  @override
  void initState() {
    super.initState();
    final saved = widget.initialDecision?['assessment'] as Map?;
    if (saved == null) return;
    final context = saved['result']?['data']?['context'] as Map?;
    final scenarios = context?['scenarios'] as List? ?? [];
    if (scenarios.length != 1) return;
    final plans = scenarios.first['plans'] as List;
    String date(Map day) =>
        '${day['year']}-${'${day['month']}'.padLeft(2, '0')}-${'${day['day']}'.padLeft(2, '0')}';
    for (final sidecar in saved['catalog_projection'] as List? ?? []) {
      final profile = Map<String, dynamic>.from(sidecar['profile'] as Map);
      final projected = (context?['catalog'] as List? ?? [])
          .where((p) => p['id'] == profile['id'])
          .firstOrNull;
      if (projected == null) continue;
      _profiles[profile['id'] as String] = {
        ...profile,
        'identity_projection_system': projected['system'],
        'identity_projection_blocked': false,
      };
    }
    if (plans.isNotEmpty) {
      _profile = plans[0]['profile_id'] as String?;
      _start.text = date(plans[0]['period']['start'] as Map);
      _end.text = date(plans[0]['period']['end'] as Map);
    }
    if (plans.length == 2) {
      _second = plans[1]['profile_id'] as String?;
      _nextStart.text = date(plans[1]['period']['start'] as Map);
      _nextEnd.text = date(plans[1]['period']['end'] as Map);
    }
    _selectedJobs.addAll(
      (saved['environmental_snapshots'] as List? ?? []).map(
        (j) => j['id'] as String,
      ),
    );
    _selectedObservations.addAll(
      (saved['farmer_observations'] as List? ?? []).map(
        (j) => j['id'] as String,
      ),
    );
    _evidenceIds = (saved['evidence'] as List? ?? [])
        .map((e) => e['id'] as String)
        .toList();
    _selectedReports.addAll(
      (saved['farmer_reports'] as List? ?? []).map((r) => r['id'] as String),
    );
  }

  Widget _dateField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: IconButton(
            tooltip: 'Choose $label',
            onPressed: _busy
                ? null
                : () async {
                    final parsed = DateTime.tryParse(controller.text);
                    final first = DateTime(1900), last = DateTime(2200);
                    final selected = await showDatePicker(
                      context: context,
                      initialDate:
                          parsed != null &&
                              !parsed.isBefore(first) &&
                              !parsed.isAfter(last)
                          ? parsed
                          : DateTime.now(),
                      firstDate: first,
                      lastDate: last,
                    );
                    if (mounted && selected != null) {
                      controller.text = selected.toIso8601String().substring(
                        0,
                        10,
                      );
                    }
                  },
            icon: const Icon(Icons.calendar_month),
          ),
        ),
      );
  @override
  void dispose() {
    for (final c in [_query, _start, _end, _nextStart, _nextEnd]) {
      c.dispose();
    }
    super.dispose();
  }

  (String, String) _dates(TextEditingController a, TextEditingController b) {
    final start = DateTime.tryParse(a.text), end = DateTime.tryParse(b.text);
    if (start == null ||
        end == null ||
        start.toIso8601String().substring(0, 10) != a.text ||
        end.toIso8601String().substring(0, 10) != b.text ||
        end.isBefore(start) ||
        end.difference(start).inDays >= 366) {
      throw const FormatException(
        'Enter exact ordered YYYY-MM-DD dates, at most 366 days.',
      );
    }
    return (a.text, b.text);
  }

  Future<void> _act(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _retrieve() async {
    final (start, end) = _dates(_start, _end);
    if (DateTime.parse(start).year < 2001 ||
        !DateTime.parse(end).isBefore(DateTime.now().toUtc())) {
      throw const FormatException(
        'This water contract requires historical days from 2001. Unsupported lineages remain unavailable.',
      );
    }
    var job = await widget.client.water(
      widget.farm.id,
      widget.farm.point,
      start,
      end,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _job = job;
      _evidenceIds = [];
    });
    for (
      var i = 0;
      i < 90 && ['queued', 'running'].contains(job['status']);
      i++
    ) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) {
        return;
      }
      job = await widget.client.job(job['id'] as String);
      if (!mounted) {
        return;
      }
      setState(() => _job = job);
    }
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final profiles = _profiles.values.toList();
    final selected = profiles.where((p) => p['id'] == _profile).firstOrNull;
    final saved = widget.records
        .where((r) => r['source_metadata']['policy'] == 'fao56-daily-pm.v1')
        .take(3);
    return SectionCard(
      title: 'Crop references & water intelligence',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Historical regional evidence · English · global location support. ET0 describes reference-grass atmospheric water demand; it does not prescribe irrigation.',
          ),
          _dateField(_start, 'Water / first crop start (YYYY-MM-DD)'),
          _dateField(_end, 'Water / first crop end (YYYY-MM-DD)'),
          FilledButton(
            onPressed: _busy ? null : () => _act(_retrieve),
            child: const Text('Retrieve NASA inputs & calculate ET0'),
          ),
          if (_job != null) ...[
            Semantics(
              container: true,
              liveRegion: true,
              child: Text(
                'Water job: ${_job!['status']} · ${_job!['error'] ?? ''}',
              ),
            ),
            Text(
              'Provider cache: ${_job!['result']?['cache_hit'] ?? 'pending'}',
            ),
            for (final gap in (_job!['result']?['gaps'] as List?) ?? [])
              Text('Unavailable: ${gap['parameter']} · ${gap['code']}'),
            if (['queued', 'running'].contains(_job!['status']) && !_busy)
              TextButton(
                onPressed: () => _act(() async {
                  final job = await widget.client.job(_job!['id'] as String);
                  if (mounted) {
                    setState(() => _job = job);
                    widget.onSaved();
                  }
                }),
                child: const Text('Check pending water job'),
              ),
          ],
          for (final r in saved) ...[
            WaterCalculationView(record: r),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _evidenceIds = [
                        r['id'] as String,
                        ...List<String>.from(
                          r['source_metadata']['parent_evidence_ids'] as List,
                        ),
                      ];
                    }),
              child: const Text(
                'Use this saved calculation and source snapshots',
              ),
            ),
          ],
          Text('Explicitly selected snapshots: ${_evidenceIds.length}'),
          const Divider(),
          TextField(
            controller: _query,
            decoration: const InputDecoration(
              labelText: 'Exact crop name or identity (7P v2)',
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final crop in [
                'rice',
                'maize',
                'mung bean',
                'sesame',
                'groundnut',
              ])
                ActionChip(
                  label: Text(crop),
                  onPressed: _busy ? null : () => _query.text = crop,
                ),
            ],
          ),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _act(() async {
                    final result = await widget.client.references(
                      _query.text.trim(),
                    );
                    if (mounted) {
                      setState(() {
                        _reference = result;
                        for (final p in (result['profiles'] as List?) ?? []) {
                          _profiles[p['id'] as String] =
                              Map<String, dynamic>.from(p as Map);
                        }
                      });
                    }
                  }),
            child: const Text('Look up crop references'),
          ),
          if (_reference != null) ...[
            if (_reference!['rule_review'] != null) ...[
              const Text(
                '7V scientific review: zero executable crop rules accepted. FAO-56 development/late Kc stages require linear interpolation. Local applicability remains blocked.',
              ),
              EvidenceDetails(
                title: '7V blocked applicability and method findings',
                data: _reference!['rule_review'],
              ),
            ],
            const Text(
              'Look up another crop to add its profiles to the comparison. Identity-only projection requires the exact reference region and compatible production system; it does not establish farm applicability.',
            ),
            Text(
              'Reference lookup: ${_reference!['status']} · recommendation eligible: false',
            ),
            for (final p in profiles)
              ExpansionTile(
                title: Text('${p['id']} · source-reviewed reference'),
                subtitle: Text('${p['region_id']} · ${p['production_system']}'),
                children: [
                  Text(
                    'Identity projection: ${p['identity_projection_blocked'] == true ? 'blocked' : p['identity_projection_system']}',
                  ),
                  EvidenceDetails(
                    title:
                        'Reference facts, units, scope and missing dependencies',
                    data: p,
                  ),
                ],
              ),
            EvidenceDetails(
              title: 'Full source-backed reference lookup',
              data: _reference,
            ),
            DropdownButtonFormField<String>(
              key: ValueKey('first:${_reference.hashCode}'),
              initialValue: _profile,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'First reference profile (exact scope)',
              ),
              items: [
                for (final p in profiles.where(
                  (p) =>
                      p['identity_projection_blocked'] == false &&
                      p['identity_projection_system'] ==
                          widget.farm.productionSystem,
                ))
                  DropdownMenuItem(
                    value: p['id'] as String,
                    child: Text('${p['id']}', overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                      _profile = v;
                      _second = null;
                    }),
            ),
            if (selected != null) ...[
              const Text(
                'The profile region is reference scope you selected; it is not inferred farm applicability. All imported rules remain disabled.',
              ),
              DropdownButtonFormField<String>(
                key: ValueKey('second:$_profile:${_reference.hashCode}'),
                initialValue: _second,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Optional second profile for declared sequence',
                ),
                items: [
                  for (final p in profiles.where(
                    (p) =>
                        p['identity_projection_blocked'] == false &&
                        p['identity_projection_system'] ==
                            widget.farm.productionSystem,
                  ))
                    DropdownMenuItem(
                      value: p['id'] as String,
                      child: Text(
                        '${p['id']}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _busy ? null : (v) => setState(() => _second = v),
              ),
            ],
            if (_second != null) ...[
              _dateField(_nextStart, 'Second declared planting (YYYY-MM-DD)'),
              _dateField(_nextEnd, 'Second declared harvest (YYYY-MM-DD)'),
              const Text(
                'Sequence order asserts successive use of this one field. Overlapping inclusive dates conflict. Dates are farmer proposals, not source-recommended dates.',
              ),
            ],
          ],
          if (widget.environmentalSnapshots.isNotEmpty)
            ExpansionTile(
              title: const Text('Choose soil / forecast reference snapshots'),
              children: [
                const Text(
                  'Selected 7G snapshots are saved with this assessment for explanation. Their units, native resolution, original times, missingness and scientific restrictions remain. They do not activate a Rust suitability rule.',
                ),
                for (final j in widget.environmentalSnapshots.where(
                  (j) => j['status'] == 'succeeded',
                ))
                  CheckboxListTile(
                    title: Text(
                      '${j['kind']} · ${j['result']?['provider'] ?? 'Source reference'}',
                    ),
                    subtitle: Text(
                      '${j['result']?['retrieved_at'] ?? 'Time unknown'} · reference context, not executable requirements',
                    ),
                    value: _selectedJobs.contains(j['id']),
                    onChanged: _busy
                        ? null
                        : (yes) => setState(() {
                            yes == true
                                ? _selectedJobs.add(j['id'] as String)
                                : _selectedJobs.remove(j['id']);
                          }),
                  ),
              ],
            ),
          if (widget.farmerObservations.isNotEmpty)
            ExpansionTile(
              title: const Text('Choose earlier farmer observations'),
              children: [
                for (final r in widget.farmerObservations)
                  CheckboxListTile(
                    title: Text(
                      '${r['observed_on']} · ${r['crop_name'] ?? 'Crop unknown'}',
                    ),
                    subtitle: Text(r['notes'] as String),
                    value: _selectedObservations.contains(r['id']),
                    onChanged: _busy
                        ? null
                        : (yes) => setState(() {
                            yes == true
                                ? _selectedObservations.add(r['id'] as String)
                                : _selectedObservations.remove(r['id']);
                          }),
                  ),
              ],
            ),
          if (widget.farmerReports.isNotEmpty)
            ExpansionTile(
              title: const Text('Choose farmer reports for this assessment'),
              children: [
                const Text(
                  'Only checked reports are retained with the saved assessment. Supported soil, drainage and irrigation availability reports reach Rust as unverified farmer reports. Priorities/resources remain declared context, with no invented weights.',
                ),
                for (final report in widget.farmerReports)
                  CheckboxListTile(
                    title: Text(
                      '${report['kind']} · ${report['occurred_on']} · ${report['crop_name'] ?? 'Farm context'}',
                    ),
                    subtitle: Text(
                      '${(report['priorities'] as List).join(', ')} · ${report['resources'] ?? ''}',
                    ),
                    value: _selectedReports.contains(report['id']),
                    onChanged: _busy
                        ? null
                        : (yes) => setState(() {
                            yes == true
                                ? _selectedReports.add(report['id'] as String)
                                : _selectedReports.remove(report['id']);
                          }),
                  ),
              ],
            ),
          FilledButton(
            onPressed: _busy
                ? null
                : () => _act(() async {
                    final (start, end) = _dates(_start, _end);
                    final (nextStart, nextEnd) = _second == null
                        ? (start, end)
                        : _dates(_nextStart, _nextEnd);
                    final result = await widget.client.assess({
                      'farm_id': widget.farm.id,
                      'catalog_version': 'v2',
                      'farmer_report_ids': _selectedReports.toList(),
                      'environmental_job_ids': _selectedJobs.toList(),
                      'observation_ids': _selectedObservations.toList(),
                      'evidence_ids': _evidenceIds,
                      'profile_ids': _profile == null || _second != null
                          ? []
                          : [_profile],
                      'pilot_id': selected?['region_id'],
                      'start': nextStart.compareTo(start) < 0
                          ? nextStart
                          : start,
                      'end': nextEnd.compareTo(end) > 0 ? nextEnd : end,
                      'sequential_field': _second != null,
                      if (_second != null)
                        'plans': [
                          {
                            'profile_id': _profile,
                            'start': start,
                            'end': end,
                            'reference_region': selected?['region_id'],
                          },
                          {
                            'profile_id': _second,
                            'reference_region':
                                _profiles[_second]?['region_id'],
                            'start': nextStart,
                            'end': nextEnd,
                          },
                        ],
                    });
                    if (mounted) {
                      setState(() => _assessment = result);
                      widget.onSaved();
                    }
                  }),
            child: const Text('Save crop & water evidence assessment'),
          ),
          if (_assessment != null) ...[
            V03ResultPanel(
              result: V03Result.decode(
                Map<String, dynamic>.from(_assessment!['result'] as Map),
              ),
            ),
            EvidenceDetails(
              title: 'Saved source sidecars and conditional water findings',
              data: _assessment,
            ),
          ],
          const Text(
            'Next steps: confirm crop/cultivar and actual stage dates with an adviser; measure root-zone soil water, field capacity and wilting point; record rainfall, drainage, irrigation supply and delivery efficiency. Rainfed water stress and irrigated demand remain unknown without a field balance. Paddy also needs preparation, seepage/percolation and standing-water targets.',
          ),
          const Text(
            'Evidence labels: measured · modeled · farmer-reported · source-reviewed reference · independently accepted rule · synthetic software test · missing/unavailable. No 7P rule is independently accepted.',
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            EvidenceNotice(title: 'Action unavailable', message: _error!),
        ],
      ),
    );
  }
}

class WaterCalculationView extends StatelessWidget {
  const WaterCalculationView({super.key, required this.record});
  final Map<String, dynamic> record;
  String value(Object? n) => n == null ? 'Unknown' : '$n';
  @override
  Widget build(BuildContext context) {
    final c = record['source_metadata']['calculation'] as Map;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Calculated modeled ET0 · ${record['temporal']['start']} to ${record['temporal']['end']} · NASA POWER LST',
        ),
        Semantics(
          container: true,
          liveRegion: true,
          child: Text(
            'Reference ET0 total: ${value(c['et0_total_mm'])} mm · ${c['et0_usable_days']}/${c['expected_days']} usable days',
          ),
        ),
        Semantics(
          container: true,
          child: Text(
            'Rainfall total: ${value(c['rainfall_total_mm'])} mm · ${c['rainfall_usable_days']}/${c['expected_days']} usable days',
          ),
        ),
        if (c['et0_total_mm'] == null)
          Text(
            'ET0 partial sum on usable days only: ${value(c['et0_partial_sum_mm'])} mm; period total remains unknown.',
          ),
        if (c['rainfall_total_mm'] == null)
          Text(
            'Rainfall partial sum on usable days only: ${value(c['rainfall_partial_sum_mm'])} mm; period total remains unknown.',
          ),
        const Text(
          'ETc: Unknown — accepted stage coefficients and actual offsets absent. Effective rainfall, soil storage, depletion, net/gross irrigation and water stress: Unknown — field balance inputs absent. No exact volume or schedule is issued.',
        ),
        for (final d in c['days'] as List)
          Text(
            '${d['date']['year']}-${d['date']['month']}-${d['date']['day']} · ET0 ${value(d['et0_mm'])} mm/day · rain ${value(d['rainfall_mm'])} mm · ${d['missing_reason'] ?? 'calculated'}',
          ),
        for (final l in record['limitations'] as List) Text('$l'),
        EvidenceDetails(
          title:
              'FAO-56 intermediates, exact inputs, original hashes and provenance',
          data: record,
        ),
      ],
    );
  }
}
