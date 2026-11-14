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
  });
  final PlatformFarm farm;
  final PlatformFarmClient client;
  final List<Map<String, dynamic>> records;
  final VoidCallback onSaved;
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
          TextField(
            controller: _start,
            decoration: const InputDecoration(
              labelText: 'Water / first crop start (YYYY-MM-DD)',
            ),
          ),
          TextField(
            controller: _end,
            decoration: const InputDecoration(
              labelText: 'Water / first crop end (YYYY-MM-DD)',
            ),
          ),
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
                            widget.farm.productionSystem &&
                        p['region_id'] == selected['region_id'],
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
              TextField(
                controller: _nextStart,
                decoration: const InputDecoration(
                  labelText: 'Second declared planting (YYYY-MM-DD)',
                ),
              ),
              TextField(
                controller: _nextEnd,
                decoration: const InputDecoration(
                  labelText: 'Second declared harvest (YYYY-MM-DD)',
                ),
              ),
              const Text(
                'Sequence order asserts successive use of this one field. Overlapping inclusive dates conflict. Dates are farmer proposals, not source-recommended dates.',
              ),
            ],
          ],
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
                          {'profile_id': _profile, 'start': start, 'end': end},
                          {
                            'profile_id': _second,
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
