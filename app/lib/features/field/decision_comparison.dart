import 'package:flutter/material.dart';
import '../../data/engine/v03_engine.dart';
import '../../design/components/product.dart';
import 'assessment_screen.dart';
import 'evidence_panels.dart';

/// Compare immutable assessments without ranking crops or recomputing findings.
class DecisionComparison extends StatefulWidget {
  const DecisionComparison({super.key, required this.decisions});
  final List<Map<String, dynamic>> decisions;

  @override
  State<DecisionComparison> createState() => _DecisionComparisonState();
}

class _DecisionComparisonState extends State<DecisionComparison> {
  String? _first, _second;

  @override
  Widget build(BuildContext context) {
    if (widget.decisions.length < 2) return const SizedBox.shrink();
    final ids = widget.decisions.map((d) => d['id'] as String).toSet();
    final first = ids.contains(_first) ? _first : null;
    final second = ids.contains(_second) ? _second : null;
    Widget choice(String label, String? value, ValueChanged<String?> changed) =>
        DropdownButtonFormField<String>(
          key: ValueKey('$label:$value'),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final decision in widget.decisions)
              DropdownMenuItem(
                value: decision['id'] as String,
                child: Text(
                  '${decision['id']}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: changed,
        );
    final selected = [
      for (final id in [first, second])
        if (id != null) widget.decisions.firstWhere((d) => d['id'] == id),
    ];
    return SectionCard(
      title: 'Compare two saved assessments',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Save each alternative sequence separately above, then select its saved decision. Compare declared dates, Rust chronology, reference scope, sources and missing requirements. No preferred crop or rotation benefit is inferred. Different snapshots and history can affect results.',
          ),
          choice(
            'Alternative A saved decision',
            first,
            (v) => setState(() => _first = v),
          ),
          choice(
            'Alternative B saved decision',
            second,
            (v) => setState(() => _second = v),
          ),
          if (first != null && first == second)
            const Text('Choose two different saved decisions to compare.'),
          if (selected.length == 2 && first != second)
            LayoutBuilder(
              builder: (context, constraints) {
                final panels = [
                  for (var i = 0; i < selected.length; i++)
                    SizedBox(
                      width: constraints.maxWidth < 700
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 16) / 2,
                      child: _SavedAlternative(
                        label: i == 0 ? 'Alternative A' : 'Alternative B',
                        decision: selected[i],
                      ),
                    ),
                ];
                return Wrap(spacing: 16, runSpacing: 16, children: panels);
              },
            ),
        ],
      ),
    );
  }
}

class _SavedAlternative extends StatelessWidget {
  const _SavedAlternative({required this.label, required this.decision});
  final String label;
  final Map<String, dynamic> decision;

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
        for (final scenario in (contextData?['scenarios'] as List?) ?? [])
          for (final plan in scenario['plans'] as List)
            Text(
              '${plan['profile_id']} · ${date(plan['period']['start'] as Map)} → ${date(plan['period']['end'] as Map)} · declared ${plan['system']}',
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
