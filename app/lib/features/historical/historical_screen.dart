import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../data/farm_journal.dart';
import '../../data/models/home_profile.dart';
import '../../data/platform_farms.dart';
import '../../design/components/product.dart';
import '../../state/home_provider.dart';
import '../../state/platform_provider.dart';
import '../map/gibs_layer.dart';
import 'historical_client.dart';
import 'historical_results.dart';

String historicalText(BuildContext context, String english) {
  const my = {
    'Historical Simulation Lab': 'အတိတ်အချက်အလက်ဖြင့် စမ်းသပ်စီစဉ်ရာ',
    'Historical replay': 'အတိတ်ကာလ ပြန်လည်ကြည့်ရှုရန်',
    'Retrospective simulation': 'အတိတ်အခြေအနေဖြင့် စမ်းသပ်စီစဉ်ခြင်း',
    'As-of-date decision simulation':
        'ဆုံးဖြတ်သည့်နေ့အထိ အချက်အလက်ဖြင့် စမ်းသပ်ခြင်း',
    'Retrieve selected NASA period': 'ရွေးထားသောကာလအတွက် NASA အချက်အလက်ရယူမည်',
    'Run & save simulation': 'စမ်းသပ်တွက်ချက်ပြီး သိမ်းမည်',
    'Keep for offline viewing': 'အင်တာနက်မရှိချိန် ကြည့်ရန် သိမ်းမည်',
    'Play': 'ပြသမည်',
    'Pause': 'ခေတ္တရပ်မည်',
  };
  return Localizations.localeOf(context).languageCode == 'my'
      ? my[english] ?? english
      : english;
}

class HistoricalScreen extends ConsumerWidget {
  const HistoricalScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(homeProfileProvider).value;
    final client = ref.watch(platformFarmClientProvider);
    final farm = profile?.farm;
    return Scaffold(
      appBar: AppBar(
        title: Text(historicalText(context, 'Historical Simulation Lab')),
      ),
      body: farm == null || client == null
          ? Center(
              child: TextButton(
                onPressed: () => context.push('/farm-evidence'),
                child: const Text('Connect this farm'),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(farm.id),
                    initialValue: farm.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Saved confirmed farm',
                    ),
                    items: [
                      for (final f in profile!.farms)
                        DropdownMenuItem(
                          value: f.id,
                          child: Text(f.name ?? 'My farm'),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        ref.read(homeProfileProvider.notifier).selectFarm(v);
                      }
                    },
                  ),
                ),
                Expanded(
                  child: HistoricalWorkspace(
                    key: ValueKey('${farm.id}:${farmRevision(farm)}'),
                    farm: farm,
                    platform: client,
                  ),
                ),
              ],
            ),
    );
  }
}

class HistoricalWorkspace extends StatefulWidget {
  const HistoricalWorkspace({
    super.key,
    required this.farm,
    required this.platform,
  });
  final ConfirmedFarm farm;
  final PlatformFarmClient platform;
  @override
  State<HistoricalWorkspace> createState() => _HistoricalWorkspaceState();
}

class _HistoricalWorkspaceState extends State<HistoricalWorkspace> {
  late final HistoricalClient _client;
  final _cache = FarmJournalCache();
  HistoricalSnapshot? _snapshot;
  final _name = TextEditingController(text: 'My historical what-if');
  final _search = TextEditingController(text: 'rice');
  List<Map<String, dynamic>> _profiles = [];
  Map<String, dynamic>? _replay, _result, _imagery;
  final _strategies = [
    for (final id in ['baseline', 'alternative_a', 'alternative_b'])
      _StrategyDraft(id),
  ];
  final _priorities = <String>{};
  DateTime _start = DateTime.utc(2024),
      _end = DateTime.utc(2024, 12, 31),
      _date = DateTime.utc(2024);
  DateTime _decision = DateTime.utc(2024);
  String _mode = 'retrospective',
      _step = 'day',
      _layer = 'rainfall',
      _comparison = 'selected',
      _pendingId = journalId();
  String? _error, _notice, _parent, _comparisonId;
  bool _busy = false, _loading = true, _autoRun = false;
  int _compareYear = 2025;
  DateTime _secondStart = DateTime.utc(2025),
      _secondEnd = DateTime.utc(2025, 12, 31);
  double _speed = 1, _opacity = .7;
  Timer? _play, _debounce;
  int _epoch = 0, _imageEpoch = 0;
  @override
  void initState() {
    super.initState();
    _client = HistoricalClient(widget.platform);
    _load();
  }

  @override
  void dispose() {
    _play?.cancel();
    _debounce?.cancel();
    _client.dispose();
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  bool get offline => _snapshot?.cached == true;
  List<Map<String, dynamic>> get windows => _snapshot?.rows('windows') ?? [];
  List<Map<String, dynamic>> get simulations =>
      _snapshot?.rows('simulations') ?? [];
  Future<void> _load() async {
    try {
      final snapshot = await loadHistorical(
        widget.farm,
        widget.platform,
        _cache,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
        if (snapshot?.cached == true) {
          _replay = snapshot!.data['saved_replay'] as Map<String, dynamic>?;
          _result = snapshot.data['saved_result'] as Map<String, dynamic>?;
          final selected = snapshot.data['selected_date'] as String?;
          if (selected != null) _date = DateTime.parse(selected);
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Historical records unavailable. Connect the local service or save an offline copy while connected, then retry.';
          _loading = false;
        });
      }
    }
  }

  void _changed() {
    _debounce?.cancel();
    _client.cancel();
    _epoch++;
    setState(() {
      _result = null;
      _busy = false;
      _pendingId = journalId();
      _error = null;
    });
    if (_autoRun && !offline) {
      _debounce = Timer(const Duration(milliseconds: 700), _simulate);
    }
  }

  void _selectDate(DateTime day) {
    setState(() {
      _date = day;
      _imagery = null;
      _imageEpoch++;
    });
  }

  void _setPeriod(DateTime start, DateTime end) {
    _play?.cancel();
    _play = null;
    final shift = start.year - _start.year;
    for (final strategy in _strategies) {
      for (final plan in strategy.plans) {
        plan.start = DateTime.utc(
          plan.start.year + shift,
          plan.start.month,
          plan.start.day,
        );
        plan.end = DateTime.utc(
          plan.end.year + shift,
          plan.end.month,
          plan.end.day,
        );
      }
    }
    setState(() {
      _start = start;
      _end = end;
      _date = start;
      _replay = null;
      _imagery = null;
    });
    _changed();
  }

  Future<void> _range() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2001),
      lastDate: DateTime.now().subtract(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _start, end: _end),
    );
    if (range != null) {
      if (range.duration.inDays >= 366) {
        setState(
          () => _error =
              'Select at most 366 days per season. Fetch context years separately.',
        );
        return;
      }
      _setPeriod(
        DateTime.utc(range.start.year, range.start.month, range.start.day),
        DateTime.utc(range.end.year, range.end.month, range.end.day),
      );
    }
  }

  Future<void> _retrieve({bool contextYears = false}) async {
    if (_snapshot == null || offline) return;
    _client.cancel();
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final ranges = contextYears
          ? [
              for (var y = 2015; y <= 2025; y++)
                (DateTime.utc(y), DateTime.utc(y, 12, 31)),
            ]
          : [(_start, _end)];
      for (final (start, end) in ranges) {
        if (!mounted || epoch != _epoch) return;
        setState(
          () => _notice =
              'Retrieving ${start.year} · bounded NASA POWER / Rust job',
        );
        final value = await _client.run('historical', {
          'farm_id': _snapshot!.farmId,
          'revision': farmRevision(widget.farm),
          'start': historicalDay(start),
          'end': historicalDay(end),
        });
        if (!mounted || epoch != _epoch || value == null) return;
        final rows = [...windows.where((w) => w['id'] != value['id']), value];
        setState(
          () => _snapshot = HistoricalSnapshot({
            ..._snapshot!.data,
            'windows': rows,
          }),
        );
        if (start == _start && end == _end) {
          final replay = await _client.replay(
            _snapshot!.farmId,
            value['id'] as String,
          );
          if (!mounted || epoch != _epoch) return;
          setState(() => _replay = replay);
        }
      }
      if (mounted && epoch == _epoch) {
        setState(
          () => _notice =
              'Historical evidence saved on the server. Keep a device copy to reopen offline.',
        );
      }
    } catch (_) {
      if (mounted && epoch == _epoch) {
        setState(
          () => _error =
              'Historical provider unavailable or the data contract was not accepted. Saved records remain available; missing values stay unknown. Retry explicitly.',
        );
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  Future<void> _openArchive(Map<String, dynamic> a) async {
    _client.cancel();
    final epoch = ++_epoch;
    _play?.cancel();
    _play = null;
    setState(() {
      _replay = null;
      _imagery = null;
      _busy = true;
      _date = DateTime.parse(a['start'] as String);
    });
    try {
      final value = offline
          ? _snapshot!.data['saved_replay'] as Map<String, dynamic>?
          : await _client.replay(_snapshot!.farmId, a['id'] as String);
      if (mounted && epoch == _epoch) {
        setState(() {
          _replay = value?['id'] == a['id'] ? value : null;
          _notice = _replay == null
              ? 'This archive was not saved on this device.'
              : null;
        });
      }
    } catch (_) {
      if (mounted && epoch == _epoch) {
        setState(
          () => _error =
              'Could not open this archive. No other date was substituted.',
        );
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  Future<void> _lookup() async {
    try {
      final value = await widget.platform.references(_search.text.trim());
      if (mounted) {
        setState(() {
          _profiles = [
            for (final p in value['profiles'] as List? ?? [])
              if (p['identity_projection_blocked'] != true)
                Map<String, dynamic>.from(p as Map),
          ];
          _notice = _profiles.isEmpty
              ? 'No usable reference identity for this search.'
              : 'Reference identities only; source scope and crop requirements still require review.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Crop references unavailable. Reconnect and retry.',
        );
      }
    }
  }

  Future<void> _simulate() async {
    if (_snapshot == null || offline) return;
    _debounce?.cancel();
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      if (_strategies.any((s) => s.plans.any((p) => p.profile == null))) {
        throw const FormatException(
          'Choose a reference identity for every crop period.',
        );
      }
      final periods = _comparison == 'context'
          ? [
              for (var y = 2015; y <= 2025; y++)
                {
                  'start': historicalDay(
                    DateTime.utc(y, _start.month, _start.day),
                  ),
                  'end': historicalDay(
                    DateTime.utc(
                      y + _end.year - _start.year,
                      _end.month,
                      _end.day,
                    ),
                  ),
                },
            ]
          : [
              {'start': historicalDay(_start), 'end': historicalDay(_end)},
              if (_comparison == 'custom_seasons')
                {
                  'start': historicalDay(_secondStart),
                  'end': historicalDay(_secondEnd),
                },
              if (_comparison == 'two_years')
                {
                  'start': historicalDay(
                    DateTime.utc(_compareYear, _start.month, _start.day),
                  ),
                  'end': historicalDay(
                    DateTime.utc(
                      _compareYear + _end.year - _start.year,
                      _end.month,
                      _end.day,
                    ),
                  ),
                },
            ];
      // Anchor always matches the user's editable dates. Context years follow.
      if (_comparison == 'context') {
        periods.removeWhere((p) => p['start'] == historicalDay(_start));
        periods.insert(0, {
          'start': historicalDay(_start),
          'end': historicalDay(_end),
        });
        if (periods.length > 11) {
          throw const FormatException(
            'Select a year from 2015–2025 for this contextual comparison.',
          );
        }
      }
      final selected = <Map<String, dynamic>>[];
      for (final period in periods) {
        final overlaps =
            windows
                .where(
                  (w) =>
                      (w['start'] as String).compareTo(period['end']!) <= 0 &&
                      (w['end'] as String).compareTo(period['start']!) >= 0,
                )
                .toList()
              ..sort(
                (a, b) => (b['created_at'] as String).compareTo(
                  a['created_at'] as String,
                ),
              );
        // Prefer one enclosing archive; otherwise select adjacent annual files.
        final full = overlaps
            .where(
              (w) =>
                  (w['start'] as String).compareTo(period['start']!) <= 0 &&
                  (w['end'] as String).compareTo(period['end']!) >= 0,
            )
            .firstOrNull;
        if (full != null) {
          selected.add(full);
        } else {
          final years = <String>{};
          for (final a in overlaps) {
            if (years.add((a['start'] as String).substring(0, 4))) {
              selected.add(a);
            }
          }
        }
      }
      final body = {
        'schema_version': 'earthsync.simulation.v1',
        'id': _pendingId,
        'farm_id': _snapshot!.farmId,
        'revision': farmRevision(widget.farm),
        'name': _name.text.trim(),
        'parent_id': _parent,
        'comparison_id': _comparisonId,
        'mode': _mode,
        'decision_at': _mode == 'as_of_date'
            ? _decision.toUtc().toIso8601String()
            : null,
        'archive_ids': selected.map((a) => a['id'] as String).toSet().toList(),
        'periods': periods,
        'strategies': _strategies.map((s) => s.toJson()).toList(),
        'priorities': _priorities.toList(),
        'replay_day':
            historicalDay(_date).compareTo(historicalDay(_start)) >= 0 &&
                historicalDay(_date).compareTo(historicalDay(_end)) <= 0
            ? historicalDay(_date)
            : historicalDay(_start),
        'replay_step': _step,
        'replay_speed': _speed,
      };
      final value = await _client.run('simulations', body);
      if (!mounted || epoch != _epoch || value == null) return;
      setState(() {
        _result = value;
        _autoRun = true;
        _parent = value['id'] as String;
        _snapshot = HistoricalSnapshot({
          ..._snapshot!.data,
          'simulations': [
            value,
            ...simulations.where((s) => s['id'] != value['id']),
          ].take(10).toList(),
        });
        _notice =
            'Simulation saved. Edits recompute and save a new result; original snapshots remain unchanged.';
      });
    } catch (e) {
      if (mounted && epoch == _epoch) {
        setState(
          () => _error = e is FormatException
              ? e.message
              : 'Simulation could not be accepted. Check crop reference scope, period bounds and archived source coverage, then retry. The prior saved results remain available.',
        );
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  Future<void> _openSimulation(Map<String, dynamic> saved) async {
    _client.cancel();
    final epoch = ++_epoch;
    try {
      final value = offline
          ? _snapshot!.data['saved_result'] as Map<String, dynamic>?
          : Map<String, dynamic>.from(
              await widget.platform.transport.request(
                    'GET',
                    '$historicalPrefix/farms/${_snapshot!.farmId}/simulations/${saved['id']}',
                    expectedStatus: 200,
                  )
                  as Map,
            );
      if (!mounted || epoch != _epoch) return;
      if (value == null || value['id'] != saved['id']) {
        setState(
          () => _notice = 'This simulation was not kept on this device.',
        );
        return;
      }
      setState(() {
        _result = value;
        _autoRun = false;
        _parent = value['id'] as String;
        _notice =
            'Saved result opened with its original inputs and source lineage. Duplicate it to edit.';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Saved simulation unavailable. Retry when connected.',
        );
      }
    }
  }

  Future<void> _importComparison(String? id) async {
    if (id == null) {
      setState(() => _comparisonId = null);
      _changed();
      return;
    }
    try {
      final groups = _snapshot!.rows('comparisons');
      final group = groups.firstWhere((g) => g['id'] == id);
      final decisions = await widget.platform.decisions(_snapshot!.farmId);
      if (!mounted) return;
      final ids = [
        group['baseline_decision_id'],
        ...(group['alternative_decision_ids'] as List).take(2),
      ];
      for (var i = 0; i < 3; i++) {
        final saved =
            decisions.firstWhere((d) => d['id'] == ids[i])['assessment'] as Map;
        final plans =
            saved['result']['data']['context']['scenarios'][0]['plans'] as List;
        DateTime day(Map d) =>
            DateTime.utc(d['year'] as int, d['month'] as int, d['day'] as int);
        final yearShift =
            _start.year - day(plans[0]['period']['start'] as Map).year;
        final references = saved['catalog_projection'] as List;
        _strategies[i].plans.clear();
        for (final p in plans) {
          final first = day(p['period']['start'] as Map),
              last = day(p['period']['end'] as Map);
          final r =
              references.firstWhere(
                    (r) => r['profile']['id'] == p['profile_id'],
                  )['profile']
                  as Map;
          _strategies[i].plans.add(
            _PlanDraft(
                DateTime.utc(first.year + yearShift, first.month, first.day),
                DateTime.utc(last.year + yearShift, last.month, last.day),
              )
              ..profile = p['profile_id'] as String
              ..region = r['region_id'] as String?,
          );
          if (!_profiles.any((v) => v['id'] == r['id'])) {
            _profiles.add(Map<String, dynamic>.from(r));
          }
        }
      }
      setState(() => _comparisonId = id);
      _changed();
      setState(
        () => _notice =
            'Imported the saved baseline and A/B as hypothetical sequences in ${_start.year}. Review dates and assumptions before running. A new comparison will be saved; the original is preserved.',
      );
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Could not import this comparison. Reconnect and retry.',
        );
      }
    }
  }

  void _duplicate() {
    if (_result == null || offline) return;
    final raw = _result!['request'] as Map;
    setState(() {
      _name.text = '${raw['name']} copy';
      _parent = _result!['id'] as String;
      _start = DateTime.parse(raw['periods'][0]['start'] as String);
      _end = DateTime.parse(raw['periods'][0]['end'] as String);
      _mode = raw['mode'] as String;
      _comparison = (raw['periods'] as List).length > 2
          ? 'context'
          : (raw['periods'] as List).length == 2
          ? 'two_years'
          : 'selected';
      if (raw['decision_at'] != null) {
        _decision = DateTime.parse(raw['decision_at'] as String);
      }
      _priorities
        ..clear()
        ..addAll((raw['priorities'] as List).cast<String>());
      _comparisonId = raw['comparison_id'] as String?;
      for (var i = 0; i < 3; i++) {
        _strategies[i].restore(
          Map<String, dynamic>.from(raw['strategies'][i] as Map),
        );
      }
      for (final s in _strategies) {
        for (final p in s.plans) {
          if (!_profiles.any((v) => v['id'] == p.profile)) {
            _profiles.add({
              'id': p.profile,
              'region_id': p.region,
              'production_system': 'saved reference identity',
            });
          }
        }
      }
      _result = null;
      _autoRun = false;
      _pendingId = journalId();
      _notice =
          'Editing a new hypothetical copy. Run to save a new immutable result.';
    });
  }

  Future<void> _keep() async {
    try {
      await _cache.save(historicalCacheKey(widget.farm, widget.platform), {
        ..._snapshot!.data,
        'simulations': [
          for (final v in simulations)
            {
              'id': v['id'],
              'name': v['request']?['name'] ?? v['name'],
              'created_at': v['created_at'],
            },
        ],
        'saved_replay': _replay,
        'saved_result': _result,
        'selected_date': historicalDay(_date),
        'kept_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) {
        setState(
          () => _notice =
              'Device copy saved. Offline viewing is read only; writes are never queued.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Device storage is unavailable or this copy is too large. Server records are preserved.',
        );
      }
    }
  }

  Future<void> _image() async {
    final day = historicalDay(_date), epoch = ++_imageEpoch;
    try {
      final result = Map<String, dynamic>.from(
        await widget.platform.transport.request(
              'GET',
              '$historicalPrefix/historical/imagery?day=$day',
              expectedStatus: 200,
            )
            as Map,
      );
      if (mounted && epoch == _imageEpoch && day == historicalDay(_date)) {
        setState(() => _imagery = result);
      }
    } catch (_) {
      if (mounted && epoch == _imageEpoch) {
        setState(() {
          _imagery = null;
          _notice =
              'Imagery unavailable: supported provider dates could not be verified. No image or NDVI was invented.';
        });
      }
    }
  }

  void _move(int direction) {
    final start = DateTime.parse(
      _replay?['start'] as String? ?? historicalDay(_start),
    );
    final end = DateTime.parse(
      _replay?['end'] as String? ?? historicalDay(_end),
    );
    var next = _step == 'month'
        ? DateTime.utc(
            _date.year,
            _date.month + direction,
            _date.day.clamp(1, 28),
          )
        : _date.add(Duration(days: direction * (_step == 'week' ? 7 : 1)));
    if (next.isAfter(end)) {
      _play?.cancel();
      _play = null;
      next = end;
    }
    if (next.isBefore(start)) next = start;
    _selectDate(next);
  }

  void _togglePlay() {
    if (_play != null) {
      _play!.cancel();
      setState(() => _play = null);
      return;
    }
    setState(
      () => _play = Timer.periodic(
        Duration(milliseconds: (1200 / _speed).round()),
        (_) {
          if (mounted) _move(1);
        },
      ),
    );
  }

  Future<void> _pickPlan(_PlanDraft p, bool end) async {
    final selected = await showDatePicker(
      context: context,
      firstDate: _start,
      lastDate: _end,
      initialDate:
          (end ? p.end : p.start).isBefore(_start) ||
              (end ? p.end : p.start).isAfter(_end)
          ? _start
          : end
          ? p.end
          : p.start,
    );
    if (selected != null) {
      setState(() {
        if (end) {
          p.end = selected;
        } else {
          p.start = selected;
        }
      });
      _changed();
    }
  }

  Widget _choice(
    String label,
    String value,
    List<String> options,
    ValueChanged<String> change, {
    bool enabled = true,
  }) => DropdownButtonFormField<String>(
    key: ValueKey('$label:$value'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final v in options)
        DropdownMenuItem(value: v, child: Text(v.replaceAll('_', ' '))),
    ],
    onChanged: !enabled
        ? null
        : (v) {
            if (v != null) change(v);
          },
  );
  @override
  Widget build(BuildContext context) {
    String tr(String v) => historicalText(context, v);
    final timeline = _snapshot?.data['timeline'] as Map?;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1360),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const PageHeader(
              title: 'Historical Agricultural Scenario Simulation Lab',
              subtitle:
                  'Real past environmental conditions + hypothetical farming decisions. Retrospective analysis is not a forecast. No crop yield, suitability score or irrigation prescription is inferred.',
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in {
                  '/field': 'Farm map',
                  '/season': 'Farmer history',
                  '/rotations': 'Rotation comparisons',
                  '/assistant': 'Ask about saved evidence',
                }.entries)
                  TextButton(
                    onPressed: () => context.push(entry.key),
                    child: Text(entry.value),
                  ),
              ],
            ),
            if (_loading || _busy) const LinearProgressIndicator(),
            if (_snapshot == null && !_loading)
              TextButton(
                onPressed: () => context.push('/farm-evidence'),
                child: const Text('Connect this confirmed farm revision'),
              ),
            if (offline)
              EvidenceNotice(
                title: 'Offline · cached historical records · read only',
                message:
                    'Original source timestamps are retained. Kept on device: ${_snapshot!.data['kept_at']}. Reconnect and refresh before calculating or saving; no writes will be submitted automatically.',
              ),
            const EvidenceNotice(
              title: 'Historical source mode',
              message:
                  'Current conditions are separate. If current weather is unavailable, these accepted historical records remain useful context. They do not describe current field health or future weather.',
            ),
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_notice != null)
              Semantics(liveRegion: true, child: Text(_notice!)),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('Refresh saved records'),
                ),
                TextButton(
                  onPressed: _snapshot == null || offline ? null : _keep,
                  child: Text(tr('Keep for offline viewing')),
                ),
              ],
            ),
            SectionCard(
              title: tr('Historical replay'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final y in [2024, 2025])
                        OutlinedButton(
                          onPressed: () => _setPeriod(
                            DateTime.utc(y),
                            DateTime.utc(y, 12, 31),
                          ),
                          child: Text('Detailed $y'),
                        ),
                      OutlinedButton(
                        onPressed: _range,
                        child: Text(
                          'Custom: ${historicalDay(_start)} to ${historicalDay(_end)}',
                        ),
                      ),
                    ],
                  ),
                  _choice(
                    'Historical year',
                    '${_start.year}',
                    [for (var y = 2001; y < DateTime.now().year; y++) '$y'],
                    (v) => _setPeriod(
                      DateTime.utc(int.parse(v)),
                      DateTime.utc(int.parse(v), 12, 31),
                    ),
                  ),
                  FilledButton(
                    onPressed: _busy || offline || _snapshot == null
                        ? null
                        : () => _retrieve(),
                    child: Text(tr('Retrieve selected NASA period')),
                  ),
                  TextButton(
                    onPressed: _busy || offline || _snapshot == null
                        ? null
                        : () => _retrieve(contextYears: true),
                    child: const Text(
                      'Retrieve 2015–2025 context · 11 bounded annual jobs',
                    ),
                  ),
                  for (final archive in windows)
                    ListTile(
                      title: Text(
                        '${archive['start']} to ${archive['end']} · ${archive['source_mode']}',
                      ),
                      subtitle: Text(
                        'NASA POWER LST · saved ${archive['created_at']}',
                      ),
                      trailing: TextButton(
                        onPressed: _busy ? null : () => _openArchive(archive),
                        child: const Text('Open replay'),
                      ),
                    ),
                  if (_replay != null) ...[
                    HistoricalReplayControls(
                      start: DateTime.parse(_replay!['start'] as String),
                      end: DateTime.parse(_replay!['end'] as String),
                      selected: _date,
                      onChanged: _selectDate,
                    ),
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        IconButton(
                          tooltip: 'Previous period',
                          onPressed: () => _move(-1),
                          icon: const Icon(Icons.skip_previous),
                        ),
                        FilledButton(
                          onPressed: _togglePlay,
                          child: Text(tr(_play == null ? 'Play' : 'Pause')),
                        ),
                        IconButton(
                          tooltip: 'Next period',
                          onPressed: () => _move(1),
                          icon: const Icon(Icons.skip_next),
                        ),
                        SizedBox(
                          width: 140,
                          child: _choice('Time step', _step, [
                            'day',
                            'week',
                            'month',
                          ], (v) => setState(() => _step = v)),
                        ),
                        SizedBox(
                          width: 130,
                          child: _choice(
                            'Replay speed',
                            '$_speed',
                            ['0.5', '1.0', '2.0', '4.0'],
                            (v) {
                              final playing = _play != null;
                              _play?.cancel();
                              _play = null;
                              setState(() => _speed = double.parse(v));
                              if (playing) _togglePlay();
                            },
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      'Playback advances historical dates locally; it is not a live feed.',
                    ),
                    _choice(
                      'Dataset / chart layer',
                      _layer,
                      ['rainfall', 'temperature', 'tmin', 'tmax', 'et0'],
                      (v) => setState(() => _layer = v),
                    ),
                    for (final r in _replay!['records'] as List)
                      for (final m in r['measurements'] as List)
                        if (m['date'] == historicalDay(_date) &&
                            m['variable'] == _layer)
                          Text(
                            '${historicalDay(_date)} · ${m['value'] ?? 'Unavailable'} ${m['unit']} · ${m['quality']} ${m['missing_reason'] ?? ''}',
                          ),
                    HistoricalMetrics(
                      summary: Map<String, dynamic>.from(
                        _replay!['summary'] as Map,
                      ),
                    ),
                    HistoricalChart(
                      periods: [
                        Map<String, dynamic>.from(_replay!['summary'] as Map),
                      ],
                      monthly: List<Map<String, dynamic>>.from(
                        _replay!['monthly'] as List,
                      ),
                      variable: _layer,
                    ),
                    ExpansionTile(
                      title: const Text(
                        'Original sources, units & missing data',
                      ),
                      children: [
                        for (final r in _replay!['records'] as List)
                          ListTile(
                            title: Text(
                              '${r['provider']} · ${r['source_metadata']['parameter']} · ${r['dataset_version']}',
                            ),
                            subtitle: Text(
                              '${r['temporal']['start']} to ${r['temporal']['end']} · ${r['temporal']['day_basis']}\nRetrieved ${r['temporal']['retrieved_at']}\n${r['spatial']['support']}\nSource SHA-256 ${r['response_sha256']}\n${(r['limitations'] as List).join('\n')}',
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            _mapPanel(),
            SectionCard(
              title: 'Hypothetical farming scenarios',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _choice(
                    'Scientific mode',
                    _mode,
                    ['retrospective', 'as_of_date'],
                    (v) {
                      setState(() => _mode = v);
                      _changed();
                    },
                    enabled: !offline,
                  ),
                  Text(
                    tr(
                      _mode == 'retrospective'
                          ? 'Retrospective simulation'
                          : 'As-of-date decision simulation',
                    ),
                  ),
                  if (_mode == 'as_of_date') ...[
                    TextButton(
                      onPressed: offline
                          ? null
                          : () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: _decision,
                                firstDate: DateTime(2001),
                                lastDate: DateTime.now().subtract(
                                  const Duration(days: 1),
                                ),
                              );
                              if (d != null) {
                                setState(
                                  () => _decision = DateTime.utc(
                                    d.year,
                                    d.month,
                                    d.day,
                                  ),
                                );
                                _changed();
                              }
                            },
                      child: Text(
                        'Decision date: ${historicalDay(_decision)} · 00:00 UTC',
                      ),
                    ),
                    const Text(
                      'Unknown historic publication times are withheld. Current archives do not prove what was available then. Decision-day daily data are withheld.',
                    ),
                  ],
                  TextField(
                    controller: _name,
                    enabled: !offline,
                    decoration: const InputDecoration(
                      labelText: 'Simulation name',
                    ),
                    onChanged: (_) => _changed(),
                  ),
                  _choice(
                    'Environmental comparison',
                    _comparison,
                    ['selected', 'two_years', 'custom_seasons', 'context'],
                    (v) {
                      setState(() => _comparison = v);
                      _changed();
                    },
                    enabled: !offline,
                  ),
                  if (_comparison == 'two_years')
                    _choice(
                      'Comparison year',
                      '$_compareYear',
                      [for (var y = 2001; y < DateTime.now().year; y++) '$y'],
                      (v) {
                        setState(() => _compareYear = int.parse(v));
                        _changed();
                      },
                      enabled: !offline,
                    ),
                  if (_comparison == 'custom_seasons')
                    TextButton(
                      onPressed: offline
                          ? null
                          : () async {
                              final range = await showDateRangePicker(
                                context: context,
                                firstDate: DateTime(2001),
                                lastDate: DateTime.now().subtract(
                                  const Duration(days: 1),
                                ),
                                initialDateRange: DateTimeRange(
                                  start: _secondStart,
                                  end: _secondEnd,
                                ),
                              );
                              if (range != null) {
                                setState(() {
                                  _secondStart = range.start;
                                  _secondEnd = range.end;
                                });
                                _changed();
                              }
                            },
                      child: Text(
                        'Second growing season: ${historicalDay(_secondStart)} to ${historicalDay(_secondEnd)}',
                      ),
                    ),
                  const Text(
                    'Compare selected years or two calendar seasons. Context uses the same season in 2015–2025. Unequal coverage stays explicit. Fetch adjacent annual archives for cross-year seasons; leap-day mapping requires review.',
                  ),
                  TextField(
                    controller: _search,
                    enabled: !offline,
                    decoration: const InputDecoration(
                      labelText:
                          'Search crop references (previous / current crops)',
                    ),
                    onSubmitted: (_) => _lookup(),
                  ),
                  TextButton(
                    onPressed: offline ? null : _lookup,
                    child: const Text('Find source-backed crop identities'),
                  ),
                  for (final s in _strategies) _strategyEditor(s),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final p in farmerPriorityLabels.entries)
                        FilterChip(
                          label: Text(p.value),
                          selected: _priorities.contains(p.key),
                          onSelected: offline
                              ? null
                              : (v) {
                                  setState(() {
                                    if (v) {
                                      _priorities.add(p.key);
                                    } else {
                                      _priorities.remove(p.key);
                                    }
                                  });
                                  _changed();
                                },
                        ),
                    ],
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey('attach:$_comparisonId'),
                    initialValue: _comparisonId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText:
                          'Attach to an existing three-strategy comparison (optional)',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Independent hypothetical scenarios'),
                      ),
                      for (final c
                          in _snapshot?.rows('comparisons') ??
                              <Map<String, dynamic>>[])
                        DropdownMenuItem(
                          value: c['id'] as String,
                          child: Text(c['name'] as String),
                        ),
                    ],
                    onChanged: offline ? null : _importComparison,
                  ),
                  FilledButton(
                    onPressed: _busy || offline || _snapshot == null
                        ? null
                        : _simulate,
                    child: Text(tr('Run & save simulation')),
                  ),
                  const Text(
                    'Changing dates changes period summaries and Rust chronology. Water assumptions change declared constraints; ETc, irrigation volumes, yields and suitability remain unavailable without accepted models. After the first run, edits trigger a new saved calculation.',
                  ),
                ],
              ),
            ),
            if (_result != null) ...[
              HistoricalResult(result: _result!),
              TextButton(
                onPressed: offline ? null : _duplicate,
                child: const Text('Duplicate saved simulation & edit'),
              ),
            ],
            SectionCard(
              title: 'Saved simulations',
              child: Column(
                children: [
                  for (final s in simulations)
                    ListTile(
                      title: Text(
                        '${s['request']?['name'] ?? s['name']} · ${s['created_at']}',
                      ),
                      subtitle: Text(
                        'Simulated · original inputs and source lineage preserved',
                      ),
                      trailing: TextButton(
                        onPressed: () => _openSimulation(s),
                        child: const Text('Reopen simulation'),
                      ),
                    ),
                  if (simulations.isEmpty)
                    const Text('No saved simulations for this farm revision.'),
                ],
              ),
            ),
            SectionCard(
              title: 'Actual farmer-reported crop history',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Actual reports, declared plans and hypothetical scenarios are separate. A gap is unknown, never proof of bare ground.',
                  ),
                  for (final p in timeline?['periods'] as List? ?? [])
                    Text(
                      '${p['start']} to ${p['end'] ?? 'ongoing'} · ${p['label']} · farmer reported',
                    ),
                  for (final p in timeline?['unknown_gaps'] as List? ?? [])
                    Text('${p['start']} to ${p['end']} · Unknown gap'),
                  for (final p in timeline?['overlaps'] as List? ?? [])
                    Text(
                      '${p['start']} to ${p['end']} · Chronology conflict requiring review',
                    ),
                  TextButton(
                    onPressed: () => context.push('/season'),
                    child: const Text(
                      'Open dated farmer journal & declared bare/fallow periods',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _strategyEditor(_StrategyDraft s) => ExpansionTile(
    key: ValueKey('strategy:${s.id}'),
    initiallyExpanded: true,
    title: Text(
      s.id == 'baseline'
          ? 'Baseline · hypothetical existing plan'
          : s.id == 'alternative_a'
          ? 'Alternative A · hypothetical'
          : 'Alternative B · hypothetical',
    ),
    children: [
      for (final (i, p) in s.plans.indexed)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey('${s.id}:$i:${p.profile}'),
                initialValue: p.profile,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText:
                      '${s.id} · ${i == 0 ? 'Previous crop' : 'Current / next crop'} reference',
                ),
                items: [
                  for (final r in _profiles)
                    DropdownMenuItem(
                      value: r['id'] as String,
                      child: Text(
                        '${r['id']} · ${r['production_system']}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: offline
                    ? null
                    : (v) {
                        setState(() {
                          p.profile = v;
                          p.region =
                              _profiles.firstWhere(
                                    (r) => r['id'] == v,
                                  )['region_id']
                                  as String?;
                        });
                        _changed();
                      },
              ),
              Wrap(
                children: [
                  TextButton(
                    onPressed: offline ? null : () => _pickPlan(p, false),
                    child: Text(
                      '${s.id} crop ${i + 1} planting: ${historicalDay(p.start)}',
                    ),
                  ),
                  TextButton(
                    onPressed: offline ? null : () => _pickPlan(p, true),
                    child: Text(
                      '${s.id} crop ${i + 1} harvest: ${historicalDay(p.end)}',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      _choice(
        '${s.id} · Irrigation availability',
        s.irrigation,
        ['unknown', 'none', 'rain_only', 'supplemental', 'regular'],
        (v) {
          setState(() => s.irrigation = v);
          _changed();
        },
        enabled: !offline,
      ),
      _choice(
        '${s.id} · Drainage',
        s.drainage,
        ['unknown', 'free', 'poor', 'standing_water'],
        (v) {
          setState(() => s.drainage = v);
          _changed();
        },
        enabled: !offline,
      ),
      for (final key in ['water_management', 'labor', 'equipment', 'resources'])
        TextFormField(
          key: ValueKey('${s.id}:$key:$_parent'),
          initialValue: s.constraints[key],
          enabled: !offline,
          maxLength: key == 'water_management' ? 1000 : 500,
          decoration: InputDecoration(
            labelText: '${s.id} · ${key.replaceAll('_', ' ')} assumptions',
          ),
          onChanged: (v) {
            s.constraints[key] = v;
            _changed();
          },
        ),
      _choice(
        '${s.id} · Gap declaration',
        s.gap,
        ['unknown', 'fallow', 'bare_field'],
        (v) {
          setState(() => s.gap = v);
          _changed();
        },
        enabled: !offline,
      ),
      const Text(
        'The gap declaration applies only between these hypothetical crop periods. Unknown remains unknown.',
      ),
    ],
  );
  Widget _mapPanel() {
    final soil =
        (_snapshot?.rows('intelligence') ?? [])
                .where(
                  (j) => j['kind'] == 'soil_map' && j['status'] == 'succeeded',
                )
                .firstOrNull?['result']
            as Map?;
    return SectionCard(
      title: 'Dated satellite map & static soil context',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Requested imagery date: ${historicalDay(_date)} · actual acquisition time ${_imagery?['acquired_at'] ?? 'unknown'}',
          ),
          TextButton(
            onPressed: offline ? null : _image,
            child: const Text('Validate date & show NASA true colour'),
          ),
          Slider(
            value: _opacity,
            onChanged: (v) => setState(() => _opacity = v),
            label: 'Overlay opacity ${(_opacity * 100).round()}%',
            semanticFormatterCallback: (v) =>
                '${(v * 100).round()} percent opacity',
          ),
          SizedBox(
            height: 320,
            child: FlutterMap(
              key: ValueKey('historical-map:${widget.farm.id}'),
              options: MapOptions(
                initialCenter: LatLng(
                  widget.farm.point.latitude,
                  widget.farm.point.longitude,
                ),
                initialZoom: 10,
              ),
              children: [
                if (!offline) ...baseMapLayers(),
                if (!offline &&
                    _imagery?['requested_date'] == historicalDay(_date) &&
                    _imagery?['tile_url'] != null)
                  Opacity(
                    opacity: _opacity,
                    child: TileLayer(
                      key: ValueKey('imagery:${historicalDay(_date)}'),
                      urlTemplate: _imagery!['tile_url'] as String,
                      maxNativeZoom: 9,
                      userAgentPackageName: 'org.fieldshift.app',
                    ),
                  ),
                if (soil != null)
                  PolygonLayer(
                    polygons: [
                      for (final c in soil['cells'] as List)
                        if (c['value'] != null)
                          Polygon(
                            points: [
                              for (final p
                                  in c['geometry']['coordinates'][0] as List)
                                LatLng(
                                  (p[1] as num).toDouble(),
                                  (p[0] as num).toDouble(),
                                ),
                            ],
                            color: Colors.purple.withValues(
                              alpha: _opacity * .4,
                            ),
                            borderColor: Colors.purple,
                            borderStrokeWidth: .3,
                          ),
                    ],
                  ),
                if (widget.farm.boundary != null)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: [
                          for (final p in widget.farm.boundary!.vertices)
                            LatLng(p.latitude, p.longitude),
                        ],
                        color: Colors.transparent,
                        borderColor: Colors.orange,
                        borderStrokeWidth: 3,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(
                        widget.farm.point.latitude,
                        widget.farm.point.longitude,
                      ),
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Text(
            'NASA GIBS MODIS true colour · © OpenStreetMap contributors. Clouds and missing tiles do not establish field conditions. Numerical NDVI remains unavailable; RGB imagery is never converted to NDVI.',
          ),
          if (_imagery != null)
            Text(
              '${_imagery!['status']} · provider time dimension ${_imagery!['time_dimensions']} · capability metadata retrieved ${_imagery!['capabilities_retrieved_at']}',
            ),
          const Text(
            'SoilGrids is one static modeled pH snapshot, not an annual soil-change series. Timeline movement never changes its version. Purple outlines identify cells; use the values and units below.',
          ),
          if (soil == null)
            const Text(
              'No accepted SoilGrids snapshot saved for this farm. Retrieve soil context from the farm map.',
            )
          else ...[
            Text(
              'ISRIC SoilGrids · ${soil['dataset_version'] ?? soil['policy'] ?? 'RUN05'} · ${soil['depth_cm']} cm · native ${soil['resolution_m']} m · retrieved ${soil['retrieved_at']} · SHA-256 ${soil['source_sha256']}',
            ),
            for (final c in soil['cells'] as List)
              if (c['at_query_point'] == true)
                Text(
                  'Native cell at confirmed point: ${c['value'] ?? 'Unavailable'} pH · raw ${c['raw_value']} · ${c['quality']}',
                ),
            const Text(
              'Modeled soil property, not a farmer laboratory measurement. Missing cells and uncertainty remain unresolved.',
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanDraft {
  String? profile, region;
  DateTime start, end;
  _PlanDraft(this.start, this.end);
  Map<String, dynamic> toJson() => {
    'profile_id': profile,
    'reference_region': region,
    'start': historicalDay(start),
    'end': historicalDay(end),
  };
}

class _StrategyDraft {
  _StrategyDraft(this.id);
  final String id;
  final plans = [
    _PlanDraft(DateTime.utc(2024), DateTime.utc(2024, 5, 31)),
    _PlanDraft(DateTime.utc(2024, 6, 15), DateTime.utc(2024, 10, 31)),
  ];
  String irrigation = 'unknown', drainage = 'unknown', gap = 'unknown';
  final constraints = <String, String>{
    'water_management': '',
    'labor': '',
    'equipment': '',
    'resources': '',
  };
  Map<String, dynamic> toJson() => {
    'identity': id,
    'plans': plans.map((p) => p.toJson()).toList(),
    'assumptions': {
      'irrigation': irrigation,
      'drainage': drainage,
      ...constraints,
    },
    'intervals':
        gap == 'unknown' ||
            !plans[0].end.add(const Duration(days: 1)).isBefore(plans[1].start)
        ? []
        : [
            {
              'kind': gap,
              'start': historicalDay(plans[0].end.add(const Duration(days: 1))),
              'end': historicalDay(
                plans[1].start.subtract(const Duration(days: 1)),
              ),
            },
          ],
  };
  void restore(Map<String, dynamic> raw) {
    plans.clear();
    for (final p in raw['plans'] as List) {
      plans.add(
        _PlanDraft(
            DateTime.parse(p['start'] as String),
            DateTime.parse(p['end'] as String),
          )
          ..profile = p['profile_id'] as String
          ..region = p['reference_region'] as String?,
      );
    }
    final a = raw['assumptions'] as Map;
    irrigation = a['irrigation'] as String;
    drainage = a['drainage'] as String;
    for (final k in constraints.keys) {
      constraints[k] = a[k] as String;
    }
    gap = (raw['intervals'] as List).isEmpty
        ? 'unknown'
        : raw['intervals'][0]['kind'] as String;
  }
}
