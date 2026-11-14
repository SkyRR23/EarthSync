import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/platform_farms.dart';
import '../../data/platform_transport.dart';
import '../../design/components/product.dart';
import '../../state/journal_provider.dart';
import '../../state/platform_provider.dart';
import '../field/evidence_panels.dart';
import 'companion_copy.dart';

/// Read-only crop facts. No scoring, ranking, extrapolation or rule promotion.
class CropExplorer extends ConsumerStatefulWidget {
  const CropExplorer({super.key});
  @override
  ConsumerState<CropExplorer> createState() => _CropExplorerState();
}

class _CropExplorerState extends ConsumerState<CropExplorer> {
  final _search = TextEditingController();
  final _selected = <String, Map<String, dynamic>>{};
  List<Map<String, dynamic>> _options = [];
  bool _busy = false, _cached = false;
  String? _error, _retrieved;
  String tr(String s) => CompanionCopy.text(context, s);
  String key(String query) =>
      'earthsync.crop-reference.v1.${ref.read(platformFarmClientProvider)?.transport.baseUri.origin}.${Uri.encodeComponent(query)}';
  @override
  void initState() {
    super.initState();
    _lookupOptions('');
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _act(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Map<String, dynamic>> _get(
    String query,
    Future<Map<String, dynamic>> Function(PlatformFarmClient) request,
  ) async {
    final cache = ref.read(journalCacheProvider);
    try {
      final client = ref.read(platformFarmClientProvider);
      if (client == null) throw const PlatformFailure('NETWORK_UNAVAILABLE');
      final result = await request(client);
      final saved = {
        'retrieved_at': DateTime.now().toUtc().toIso8601String(),
        'result': result,
      };
      // Public reference metadata only. This cache never stores private farm records.
      await cache.save(key(query), saved);
      if (mounted) {
        setState(() {
          _cached = false;
          _retrieved = saved['retrieved_at'] as String;
        });
      }
      return result;
    } on PlatformFailure catch (e) {
      if (e.code != 'NETWORK_UNAVAILABLE' && !e.code.startsWith('HTTP_5')) {
        rethrow;
      }
      final saved = await cache.read(key(query));
      if (saved == null) rethrow;
      if (mounted) {
        setState(() {
          _cached = true;
          _retrieved = saved['retrieved_at'] as String;
        });
      }
      return Map<String, dynamic>.from(saved['result'] as Map);
    }
  }

  Future<void> _lookupOptions(String query) => _act(() async {
    final result = await _get(
      'options:$query',
      (c) async => Map<String, dynamic>.from(
        await c.transport.request(
              'GET',
              '${PlatformFarmClient.prefix}/crop-options?${Uri(queryParameters: {'q': query}).query}',
              expectedStatus: 200,
            )
            as Map,
      ),
    );
    if (mounted) {
      setState(
        () =>
            _options = List<Map<String, dynamic>>.from(result['crops'] as List),
      );
    }
  });
  Future<void> _select(Map<String, dynamic> crop) => _act(() async {
    if (_selected.length >= 4 && !_selected.containsKey(crop['id'])) {
      throw StateError('Compare up to four crops at a time.');
    }
    final query = crop['id'] as String;
    final result = await _get('facts:$query', (c) => c.references(query));
    if (mounted) setState(() => _selected[crop['id'] as String] = result);
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Crop references'))),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            PageHeader(
              title: tr('Crop references'),
              subtitle:
                  'Explore 7P source profiles and compare reference facts. Regional applicability, cultivar and management remain separate. Scientific source text is retained in English.',
            ),
            EvidenceNotice(
              title: tr('Recommendation unavailable'),
              message:
                  '7V accepted zero executable suitability rules. No option is ranked as best for your field. Missing soil, water, cultivar and management information remains unknown.',
            ),
            TextField(
              controller: _search,
              maxLength: 150,
              decoration: InputDecoration(
                labelText: tr('Search crops or aliases'),
                suffixIcon: IconButton(
                  tooltip: tr('Search'),
                  onPressed: _busy
                      ? null
                      : () => _lookupOptions(_search.text.trim()),
                  icon: const Icon(Icons.search),
                ),
              ),
              onSubmitted: _busy ? null : _lookupOptions,
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) Text('References unavailable: $_error'),
            if (_retrieved != null)
              Text(
                '${_cached ? tr('Cached copy · may be stale') : tr('Last retrieved')}: $_retrieved',
              ),
            Wrap(
              spacing: 8,
              children: [
                for (final result in _selected.entries)
                  InputChip(
                    label: Text(
                      '${result.value['crop']?['scientific_name'] ?? result.key}',
                    ),
                    onDeleted: () =>
                        setState(() => _selected.remove(result.key)),
                  ),
              ],
            ),
            if (_selected.isNotEmpty)
              LayoutBuilder(
                builder: (_, box) => Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final result in _selected.values)
                      SizedBox(
                        width: box.maxWidth >= 720
                            ? (box.maxWidth - 16) / 2
                            : box.maxWidth,
                        child: _ReferenceCard(result: result),
                      ),
                  ],
                ),
              ),
            if (_options.isEmpty && !_busy)
              const Text(
                'No matching catalog entries. Try a common or scientific name.',
              ),
            SectionCard(
              title: tr('Crop'),
              child: Column(
                children: [
                  for (final crop in _options)
                    ListTile(
                      title: Text(
                        (crop['aliases'] as List).take(3).join(' · '),
                      ),
                      subtitle: Text(
                        '${crop['scientific_name']} · ${crop['profile_coverage']}',
                      ),
                      trailing: IconButton(
                        tooltip: 'Add to reference comparison',
                        onPressed: _busy ? null : () => _select(crop),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                      onTap: _busy ? null : () => _select(crop),
                    ),
                ],
              ),
            ),
            FilledButton(
              onPressed: () => context.push('/rotations'),
              child: Text(tr('Compare alternatives')),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ReferenceCard extends StatelessWidget {
  const _ReferenceCard({required this.result});
  final Map<String, dynamic> result;
  @override
  Widget build(BuildContext context) => SectionCard(
    title: '${result['crop']?['scientific_name'] ?? 'Identity unresolved'}',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Aliases: ${(result['crop']?['aliases'] as List? ?? []).join(', ')}',
        ),
        if ((result['profiles'] as List? ?? []).isEmpty)
          const Text(
            'No source profile available. Identity alone cannot support an assessment.',
          ),
        for (final profile in result['profiles'] as List? ?? [])
          ExpansionTile(
            title: Text(
              '${profile['region_id'] ?? 'Global reference'} · ${profile['production_system']}',
            ),
            subtitle: Text(
              '${profile['cultivar'] ?? 'Cultivar unknown'} · reference only',
            ),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(profile['source_context'] as String),
              for (final fact in (profile['parameters'] as Map).entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${fact.key.toString().replaceAll('_', ' ')}: ${fact.value['state'] == 'available' ? '${fact.value['value']} ${fact.value['unit'] ?? ''}' : 'Unknown'}',
                      ),
                      Text(
                        '${fact.value['state'] == 'available' ? fact.value['statistic'] : fact.value['missing_reason']}',
                      ),
                      if ((fact.value['claim_ids'] as List).isNotEmpty)
                        Text(
                          'Claims: ${(fact.value['claim_ids'] as List).join(', ')}',
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ExpansionTile(
          title: Text(CompanionCopy.text(context, 'Source details (English)')),
          children: [
            for (final source in result['sources'] as List? ?? [])
              Padding(
                padding: const EdgeInsets.all(8),
                child: SelectableText(
                  '${source['publisher']} · ${source['title']}\n${source['url']}\nSource version: ${source['version']}\nRetrieved: ${source['retrieved_at'] ?? source['retrieval_date'] ?? 'Unknown'}\n${source['rights_note']}',
                ),
              ),
            EvidenceDetails(
              title: 'Exact source sidecars & catalog hash',
              data: result,
            ),
          ],
        ),
      ],
    ),
  );
}
