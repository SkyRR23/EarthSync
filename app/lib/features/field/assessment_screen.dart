import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/engine/v03_engine.dart';
import '../../state/integration_provider.dart';
import 'evidence_panels.dart';

class AssessmentScreen extends ConsumerStatefulWidget {
  const AssessmentScreen({super.key});
  @override
  ConsumerState<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends ConsumerState<AssessmentScreen> {
  String? _profile;
  final _start = TextEditingController(), _end = TextEditingController();
  String? _dateError;
  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  DateTime? _date(String text) {
    final value = DateTime.tryParse(text);
    return value != null && value.toIso8601String().substring(0, 10) == text
        ? value
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final assessment = ref.watch(assessmentProvider);
    final catalog = ref.watch(catalogProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Agricultural evidence assessment')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('Rust v0.3 · reference-only crop catalog'),
              const Text(
                'No catalog profile is eligible for a crop recommendation. Choose a research profile and declare your own planting and harvest dates to inspect gaps. This does not establish local applicability. NASA monthly climate cannot fill daily temperature, soil or ET0 requirements.',
              ),
              catalog.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => Column(
                  children: [
                    const Text('Crop catalog unavailable.'),
                    TextButton(
                      onPressed: () => ref.invalidate(catalogProvider),
                      child: const Text('Retry catalog'),
                    ),
                  ],
                ),
                data: (data) {
                  final profiles = (data['reference']['profiles'] as List)
                      .cast<Map<String, dynamic>>();
                  final selected = profiles
                      .where((p) => p['id'] == _profile)
                      .firstOrNull;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _profile,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Reference profile and region',
                        ),
                        items: [
                          for (final p in profiles)
                            DropdownMenuItem(
                              value: p['id'] as String,
                              child: Text(
                                '${p['common_name']} · ${p['pilot_id']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: assessment.running
                            ? null
                            : (v) => setState(() => _profile = v),
                      ),
                      if (selected != null) ...[
                        Text(
                          'Recommendation eligible: ${selected['recommendation_eligible']} · source review: ${selected['review_status']}',
                        ),
                        Text(
                          'Missing: ${(selected['unknown_properties'] as List).join(', ')}',
                        ),
                        EvidenceDetails(
                          title:
                              'Reference parameters and per-parameter citations',
                          data: selected,
                        ),
                      ],
                      EvidenceDetails(
                        title: 'Original sources and claim graph',
                        data: {
                          'sources': data['reference']['sources'],
                          'claims': data['reference']['claims'],
                        },
                      ),
                    ],
                  );
                },
              ),
              TextField(
                controller: _start,
                decoration: const InputDecoration(
                  labelText: 'Your declared planting date (YYYY-MM-DD)',
                ),
              ),
              TextField(
                controller: _end,
                decoration: const InputDecoration(
                  labelText: 'Your declared harvest date (YYYY-MM-DD)',
                ),
              ),
              if (_dateError != null) Text(_dateError!),
              FilledButton(
                onPressed: assessment.running
                    ? null
                    : () {
                        final start = _date(_start.text.trim()),
                            end = _date(_end.text.trim());
                        if (_profile == null ||
                            start == null ||
                            end == null ||
                            end.isBefore(start)) {
                          setState(
                            () => _dateError =
                                'Choose a profile and enter exact ordered dates.',
                          );
                          return;
                        }
                        setState(() => _dateError = null);
                        ref
                            .read(assessmentProvider.notifier)
                            .run(profileId: _profile, start: start, end: end);
                      },
                child: const Text(
                  'Run reference gap assessment with Rust v0.3',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Synthetic software demonstration: fictional crops, thresholds and evidence. It does not use your farm and cannot recommend a real crop.',
              ),
              OutlinedButton(
                onPressed: assessment.running
                    ? null
                    : () => ref
                          .read(assessmentProvider.notifier)
                          .run(synthetic: true),
                child: const Text('Run labeled synthetic v0.3 demonstration'),
              ),
              if (assessment.running)
                const LinearProgressIndicator(
                  semanticsLabel: 'Executing compiled Rust v0.3',
                ),
              if (assessment.error != null) Text(assessment.error!),
              if (assessment.reference != null)
                EvidenceDetails(
                  title: 'Catalog adapter mapping and missing inputs',
                  data: assessment.reference,
                ),
              if (assessment.result case final result?)
                V03ResultPanel(result: result),
              if (assessment.result != null)
                TextButton(
                  onPressed: () => context.push('/assistant'),
                  child: const Text('Ask about this assessment'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class V03ResultPanel extends StatelessWidget {
  const V03ResultPanel({super.key, required this.result});
  final V03Result result;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (result.synthetic)
        const Text('SYNTHETIC SOFTWARE TEST — not a real-world recommendation'),
      if (result.validation case final validation?)
        Text(
          'Input validation failed · ${validation['path']}: ${validation['message']}',
        ),
      for (final summary in result.summaries)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${summary['scenario_id']} · ${V03Status.decode(summary['status']).label}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Text(
                  'A supported comparison is not whole-crop suitability.',
                ),
                for (final finding in (summary['findings'] as List).take(3))
                  Text('${finding['plan_id']}: ${finding['message']}'),
                if ((summary['findings'] as List).length > 3)
                  Text(
                    '${(summary['findings'] as List).length - 3} more findings in details.',
                  ),
                EvidenceDetails(
                  title: 'All crop and rotation findings',
                  data: {
                    'summary': summary,
                    'findings': result.findings
                        .where(
                          (f) => f['scenario_id'] == summary['scenario_id'],
                        )
                        .toList(),
                  },
                ),
              ],
            ),
          ),
        ),
      for (final limitation in result.limitations) Text(limitation),
      EvidenceDetails(
        title: 'Full Rust evidence, source references and validation response',
        data: result.envelope,
      ),
    ],
  );
}
