import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/platform_farms.dart';
import '../../design/components/product.dart';
import '../../state/journal_provider.dart';
import '../../state/platform_provider.dart';
import 'companion_copy.dart';

/// Server-owned evidence eligibility. Private farm context is never cached here.
class CropIntelligencePanel extends ConsumerStatefulWidget {
  const CropIntelligencePanel({super.key, required this.cropId});
  final String cropId;
  @override
  ConsumerState<CropIntelligencePanel> createState() =>
      _CropIntelligenceState();
}

class _CropIntelligenceState extends ConsumerState<CropIntelligencePanel> {
  final _question = TextEditingController();
  final _region = TextEditingController();
  final _cultivar = TextEditingController();
  Map<String, dynamic>? _packet, _context;
  String? _error;
  bool _busy = false;
  String tr(String value) => CompanionCopy.text(context, value);
  @override
  void dispose() {
    _question.dispose();
    _region.dispose();
    _cultivar.dispose();
    super.dispose();
  }

  Future<void> _retrieve({bool farm = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client = ref.read(platformFarmClientProvider);
      if (client == null) throw StateError('Local service unavailable');
      final snapshot = ref.read(journalProvider).asData?.value;
      if (farm) {
        if (snapshot == null || snapshot.cached) {
          throw StateError(
            'Connect the current farm to retrieve private context.',
          );
        }
        final result = await client.transport.request(
          'GET',
          '${PlatformFarmClient.prefix}/farms/${snapshot.farmId}/soil-context',
          expectedStatus: 200,
        );
        if (mounted &&
            ref.read(journalProvider).asData?.value?.farmId == snapshot.farmId) {
          setState(() => _context = Map<String, dynamic>.from(result as Map));
        }
      } else {
        final result = await client.transport.request(
          'POST',
          '${PlatformFarmClient.prefix}/crop-intelligence',
          expectedStatus: 200,
          body: {
            'crop': widget.cropId,
            'question': _question.text.trim(),
            if (_region.text.trim().isNotEmpty) 'region': _region.text.trim(),
            if (_cultivar.text.trim().isNotEmpty)
              'cultivar': _cultivar.text.trim(),
          },
        );
        if (mounted) {
          setState(() => _packet = Map<String, dynamic>.from(result as Map));
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Evidence unavailable. Check the local service and documented scope.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Do not display private context from a different farm after a provider change.
    ref.listen(journalProvider, (previous, next) {
      if (previous?.asData?.value?.farmId != next.asData?.value?.farmId &&
          mounted) {
        setState(() => _context = null);
      }
    });
    return ExpansionTile(
      title: Text(tr('Crop intelligence')),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr('Known requirements')),
        const Text(
          'Retrieve exact source claims. An empty scope shows reference evidence; an explicit scope requires an exact documented match.',
        ),
        TextField(
          controller: _question,
          maxLength: 1000,
          decoration: const InputDecoration(
            labelText: 'Question (for example: soil pH, drainage or water)',
          ),
          onSubmitted: _busy ? null : (_) => _retrieve(),
        ),
        TextField(
          controller: _region,
          maxLength: 150,
          decoration: const InputDecoration(
            labelText: 'Documented region ID or scope (optional)',
          ),
        ),
        TextField(
          controller: _cultivar,
          maxLength: 150,
          decoration: const InputDecoration(
            labelText: 'Exact cultivar (optional; unknown does not match)',
          ),
        ),
        FilledButton(
          onPressed: _busy ? null : () => _retrieve(),
          child: Text(tr('Retrieve evidence')),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        if (_packet != null) ...[
          Text('${_packet!['answer']}'),
          for (final claim in _packet!['claims'] as List? ?? [])
            ExpansionTile(
              title: Text('${claim['parameter']}'.replaceAll('_', ' ')),
              subtitle: Text(
                '${claim['source_id']} · ${claim['evidence_status']}',
              ),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelectableText(
                  '${claim['claim'] ?? claim['statistic']}\n${jsonEncode(claim['value'])} ${claim['unit'] ?? ''}',
                ),
                Text(
                  'Region: ${claim['region'] ?? 'Global reference; local applicability unknown'}\nSystem: ${claim['production_system'] ?? 'Unknown'}\nCultivar: ${claim['cultivar'] ?? 'Unknown'}\nLocator: ${claim['locator']}',
                ),
                for (final limitation in claim['limitations'] as List? ?? [])
                  Text('• $limitation'),
              ],
            ),
          Text(tr('Unresolved questions')),
          for (final question
              in _packet!['local_review_questions'] as List? ?? [])
            Text('• $question'),
          for (final limit in _packet!['contradictions'] as List? ?? [])
            Text('• $limit'),
          ExpansionTile(
            title: Text(tr('Scientific eligibility')),
            children: [
              const Text(
                'Reference information available. Farm-specific validation pending. Executable crop recommendation unavailable.',
              ),
              for (final candidate
                  in _packet!['blocked_candidates'] as List? ?? [])
                ListTile(
                  title: Text('${candidate['domain']} · blocked'),
                  subtitle: Text(
                    '${candidate['block_reason']}\n${(candidate['required_evidence'] as List).join('\n')}',
                  ),
                ),
            ],
          ),
          ExpansionTile(
            title: Text(tr('References')),
            children: [
              for (final source in _packet!['sources'] as List? ?? [])
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: SelectableText(
                    '${source['id']} · ${source['publisher']}\n${source['title']}\n${source['url']}\nPublished: ${source['publication_date'] ?? 'Unknown'}\nRetrieved: ${source['retrieved_at'] ?? source['retrieval_date'] ?? 'Unknown'}\n${source['rights_note'] ?? source['rights'] ?? ''}',
                  ),
                ),
            ],
          ),
        ],
        TextButton(
          onPressed: _busy ? null : () => _retrieve(farm: true),
          child: Text(tr('Available farm evidence')),
        ),
        if (_context != null) ...[
          for (final category in [
            'modeled_regional_reference',
            'farmer_reported',
            'laboratory_sample_transcriptions',
          ])
            ExpansionTile(
              title: Text(category.replaceAll('_', ' ')),
              children: [
                if ((_context![category] as List).isEmpty)
                  const Text('No saved evidence in this category.'),
                for (final value in _context![category] as List)
                  SelectableText(
                    const JsonEncoder.withIndent('  ').convert(value),
                  ),
              ],
            ),
          const EvidenceNotice(
            title: 'Field applicability unresolved',
            message:
                'Depth, method, date and spatial support must be reconciled by an independent reviewer. The service does not calculate a suitability score.',
          ),
        ],
      ],
    );
  }
}
