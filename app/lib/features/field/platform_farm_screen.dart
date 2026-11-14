import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/engine/v03_engine.dart';
import '../../data/platform_farms.dart';
import '../../data/platform_transport.dart';
import '../../design/components/product.dart';
import '../../state/home_provider.dart';
import '../../state/integration_provider.dart';
import '../../state/platform_provider.dart';
import 'assessment_screen.dart';
import 'evidence_panels.dart';

class PlatformFarmScreen extends ConsumerWidget {
  const PlatformFarmScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = ref.watch(homeProfileProvider).value?.farm;
    return Scaffold(
      appBar: AppBar(title: const Text('Persisted farm evidence')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const PageHeader(
                title: 'Local farm evidence',
                subtitle:
                    'Private single-user service on this device. Historical records do not establish a crop recommendation.',
              ),
              if (local == null)
                TextButton(
                  onPressed: () => context.push('/location'),
                  child: const Text('Confirm a farm first'),
                )
              else
                _FarmConnection(
                  key: ValueKey('${local.id}:${local.confirmedAt}'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FarmConnection extends ConsumerStatefulWidget {
  const _FarmConnection({super.key});
  @override
  ConsumerState<_FarmConnection> createState() => _FarmConnectionState();
}

class _FarmConnectionState extends ConsumerState<_FarmConnection> {
  String? _system, _error;
  bool _busy = false;
  Future<void> _link() async {
    final local = ref.read(homeProfileProvider).value!.farm!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(platformFarmClientProvider)!.confirm(local, _system!);
      if (mounted) ref.invalidate(platformFarmProvider);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(platformFarmClientProvider);
    if (client == null) {
      return const Text('The local evidence service is not configured.');
    }
    final linked = ref.watch(platformFarmProvider);
    return linked.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => EvidenceNotice(
        title: 'Local service unavailable',
        message: '$e',
        action: TextButton(
          onPressed: () => ref.invalidate(platformFarmProvider),
          child: const Text('Retry connection'),
        ),
      ),
      data: (farm) => farm == null
          ? SectionCard(
              title: 'Save this confirmed farm to the local service',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'This copies the confirmed farm name, point and confirmation date after your action below. Area and device location stay separate. Existing workspace photos and planning notes are not copied. Editing the confirmed farm creates a separate revision; prior records remain in the local archive.',
                  ),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Farmer-declared production system',
                    ),
                    items: [
                      for (final system in [
                        'dryland',
                        'rainfed',
                        'irrigated',
                        'flooded_lowland',
                      ])
                        DropdownMenuItem(value: system, child: Text(system)),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _system = v),
                  ),
                  FilledButton(
                    onPressed: _busy || _system == null ? null : _link,
                    child: const Text('Confirm local farm persistence'),
                  ),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null) Text(_error!),
                ],
              ),
            )
          : _FarmRecords(key: ValueKey(farm.id), farm: farm),
    );
  }
}

class _FarmRecords extends ConsumerStatefulWidget {
  const _FarmRecords({super.key, required this.farm});
  final PlatformFarm farm;
  @override
  ConsumerState<_FarmRecords> createState() => _FarmRecordsState();
}

class _FarmRecordsState extends ConsumerState<_FarmRecords> {
  final _start = TextEditingController(), _end = TextEditingController();
  String? _profile, _error;
  bool _busy = false;
  V03Result? _validation;
  final _selectedEvidence = <String>{};
  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(platformContextProvider);
    ref.invalidate(platformDecisionsProvider);
    ref.invalidate(platformAssistantProvider);
  }

  Future<void> _action(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _validation = null;
    });
    try {
      await action();
      if (mounted) _refresh();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          if (e is PlatformFailure && e.validation != null) {
            _validation = V03Result.decode(e.validation!);
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  (String, String) _dates() {
    final first = DateTime.tryParse(_start.text),
        last = DateTime.tryParse(_end.text);
    if (first == null ||
        last == null ||
        first.toIso8601String().substring(0, 10) != _start.text ||
        last.toIso8601String().substring(0, 10) != _end.text ||
        last.isBefore(first) ||
        last.difference(first).inDays >= 366) {
      throw const FormatException(
        'Enter exact ordered dates covering at most 366 days.',
      );
    }
    return (_start.text, _end.text);
  }

  @override
  Widget build(BuildContext context) {
    final farm = widget.farm;
    final client = ref.watch(platformFarmClientProvider)!;
    final data = ref.watch(platformContextProvider);
    final decisions = ref.watch(platformDecisionsProvider);
    final catalog = ref.watch(catalogProvider).value;
    final profiles = ((catalog?['reference']?['profiles'] as List?) ?? [])
        .cast<Map<String, dynamic>>();
    final selected = profiles.where((p) => p['id'] == _profile).firstOrNull;
    final records =
        ((data.isLoading ? null : data.value?['evidence'] as List?) ?? [])
            .cast<Map<String, dynamic>>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Database farm: ${farm.id}\nConfirmed point: ${farm.point.label}\nDeclared system: ${farm.productionSystem}',
        ),
        Wrap(
          spacing: 12,
          children: [
            TextButton(
              onPressed: _refresh,
              child: const Text('Refresh saved records'),
            ),
            FilledButton.tonal(
              onPressed: () => context.push('/daily-climate?farm=1'),
              child: const Text('Retrieve daily climate for this farm'),
            ),
            TextButton(
              onPressed: () => context.push('/assistant'),
              child: const Text('Ask about saved evidence'),
            ),
            TextButton(
              onPressed: () => context.push('/photos'),
              child: const Text('Private workspace photos'),
            ),
          ],
        ),
        const EvidenceNotice(
          title: 'Photo ownership',
          message:
              'Existing photos remain in the authorized 7H workspace. Linking this farm does not transfer or expose them. Farm-owned 7I objects remain separate; migration requires a verified workspace token, explicit selection and sanitizer checks. No automatic migration is enabled.',
        ),
        if (data.isLoading || decisions.isLoading || _busy)
          const LinearProgressIndicator(),
        if (data.hasError) Text('Saved evidence unavailable: ${data.error}'),
        for (final r in records) ...[
          CheckboxListTile(
            title: Text(
              'Include ${r['dataset']} · ${r['source_metadata']['parameter'] ?? r['source_identifier']}',
            ),
            subtitle: Text(
              'Retrieved ${r['temporal']['retrieved_at']} · ${r['review']}\n${r['source_metadata']['review_scope'] ?? 'Source applicability requires review.'}',
            ),
            value: _selectedEvidence.contains(r['id']),
            onChanged: _busy
                ? null
                : (include) => setState(() {
                    if (include == true) {
                      _selectedEvidence.add(r['id'] as String);
                    } else {
                      _selectedEvidence.remove(r['id']);
                    }
                  }),
          ),
          EvidenceDetails(
            title:
                '${r['dataset']} · ${r['temporal']['start']} – ${r['temporal']['end']}',
            data: r,
          ),
        ],
        if (records.isEmpty && data.hasValue)
          const Text(
            'No saved evidence for this farm revision. Retrieve daily climate to populate it.',
          ),
        SectionCard(
          title: 'Reference assessment and reported history',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Declare the period and optional reference profile. Region/system compatibility is checked by the server. All crop profiles remain recommendation-ineligible. Local planning notes are preserved separately and are not silently promoted into history.',
              ),
              DropdownButtonFormField<String>(
                initialValue: _profile,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Optional reference profile',
                ),
                items: [
                  for (final p in profiles.where((p) => p['kind'] != 'fallow'))
                    DropdownMenuItem(
                      value: p['id'] as String,
                      child: Text(
                        '${p['common_name']} · ${p['pilot_id']}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _busy ? null : (v) => setState(() => _profile = v),
              ),
              TextField(
                controller: _start,
                decoration: const InputDecoration(
                  labelText: 'Start date (YYYY-MM-DD)',
                ),
              ),
              TextField(
                controller: _end,
                decoration: const InputDecoration(
                  labelText: 'End date (YYYY-MM-DD)',
                ),
              ),
              Text(
                '${_selectedEvidence.length} source records selected. An empty selection produces an explicit evidence gap assessment.',
              ),
              FilledButton(
                onPressed: _busy || !data.hasValue
                    ? null
                    : () => _action(() async {
                        final (start, end) = _dates();
                        // The farmer chooses immutable snapshots explicitly.
                        // The server checks source applicability and rejects
                        // multiple records for the same variable.
                        final applicable = records
                            .where((r) => _selectedEvidence.contains(r['id']))
                            .toList();
                        await client.assess({
                          'farm_id': farm.id,
                          'evidence_ids': applicable
                              .map((r) => r['id'])
                              .toList(),
                          'profile_ids': _profile == null ? [] : [_profile],
                          'pilot_id': selected?['pilot_id'],
                          'start': start,
                          'end': end,
                        });
                      }),
                child: const Text('Run and save actual Rust assessment'),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _action(() async {
                        final (start, end) = _dates();
                        await client.history(farm.id, {
                          'crop_id': selected == null
                              ? null
                              : '${selected['crop_id']}@catalog-${catalog!['reference']['catalog_version']}',
                          'fallow': false,
                          'start': start,
                          'end': end,
                        });
                      }),
                child: const Text('Save period as farmer-reported history'),
              ),
              const Text(
                'History submissions are explicit and not retried automatically. Inspect saved history after a network error before submitting again.',
              ),
            ],
          ),
        ),
        if (_error != null)
          EvidenceNotice(title: 'Action could not complete', message: _error!),
        if (_validation != null) V03ResultPanel(result: _validation!),
        EvidenceDetails(
          title: 'Saved farmer-reported history',
          data: {'history': data.value?['history'] ?? []},
        ),
        if (decisions.hasError)
          Text('Decision history unavailable: ${decisions.error}'),
        for (final decision in decisions.value ?? <Map<String, dynamic>>[])
          SectionCard(
            title: 'Saved decision ${decision['id']}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                V03ResultPanel(
                  result: V03Result.decode(
                    Map<String, dynamic>.from(
                      decision['assessment']['result'] as Map,
                    ),
                  ),
                ),
                EvidenceDetails(
                  title: 'Persisted evidence gaps and source lineage',
                  data: decision,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
