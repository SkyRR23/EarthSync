import 'dart:convert';

import '../models/field_analysis.dart';

/// Maps the team engine's `analyze_integration_json` envelope
/// (engine/src/integration.rs, docs/INTEGRATION_READINESS.md) onto the
/// app's display models. Pure translation: no thresholds, scores or
/// agricultural rules are added here.
///
/// Throws [EngineError] for `status: "error"` or unreadable output.
FieldAnalysis fieldAnalysisFromEnvelope(String envelopeJson) {
  final Map<String, dynamic> env;
  try {
    env = jsonDecode(envelopeJson) as Map<String, dynamic>;
  } catch (_) {
    throw const EngineError(
      code: 'bad_engine_output',
      message: 'The engine returned data the app could not read.',
    );
  }

  if (env['status'] == 'error') {
    final e = env['error'] as Map<String, dynamic>? ?? const {};
    throw EngineError(
      code: e['code'] as String? ?? 'ENGINE_ERROR',
      message:
          e['message'] as String? ?? 'The engine could not analyse this field.',
      retryable: e['retryable'] as bool? ?? false,
      missingSources: [if (e['component'] is String) e['component'] as String],
    );
  }
  if (env['status'] != 'success' || env['data'] is! Map) {
    throw const EngineError(
      code: 'bad_engine_output',
      message: 'The engine returned an unexpected response.',
    );
  }

  try {
    return _fromData(env['data'] as Map<String, dynamic>);
  } on EngineError {
    rethrow;
  } catch (e) {
    throw EngineError(
      code: 'bad_engine_output',
      message: 'The engine result did not match the expected format.',
      missingSources: [e.toString()],
    );
  }
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _ym(Map<String, dynamic>? p) =>
    p == null ? '?' : '${_months[(p['month'] as int) - 1]} ${p['year']}';

List<Map<String, dynamic>> _list(Object? raw) =>
    (raw as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();

List<String> _messages(Object? explanations) => [
  for (final e in _list(explanations)) e['message'] as String? ?? '',
];

Feasibility _eligibility(Object? raw) => switch (raw) {
  'supported_by_supplied_evidence' => Feasibility.supported,
  'conflicts_with_supplied_evidence' => Feasibility.conflicts,
  _ => Feasibility.unknown,
};

EvidenceType _sourceType(Object? status) => switch (status) {
  'verified_for_supplied_context' || 'reference_only' => EvidenceType.reference,
  _ => EvidenceType.unverified, // synthetic_test or anything unknown
};

EvidenceType _dataKindType(Object? kind) => switch (kind) {
  'observed' => EvidenceType.observation,
  'modeled' || 'forecast' => EvidenceType.model,
  _ => EvidenceType.unverified, // hypothetical
};

const _envRefId = 'environment-series';

FieldAnalysis _fromData(Map<String, dynamic> d) {
  final field = d['field'] as Map<String, dynamic>;
  final envr = d['environment'] as Map<String, dynamic>;
  final seasonal = envr['seasonal'] as Map<String, dynamic>;
  final meta = seasonal['metadata'] as Map<String, dynamic>? ?? const {};
  final climate = d['climate'] as Map<String, dynamic>? ?? const {};
  final rotations = d['rotations'] as Map<String, dynamic>? ?? const {};
  final window =
      climate['window'] as Map<String, dynamic>? ??
      seasonal['window'] as Map<String, dynamic>?;
  final period = window == null
      ? ''
      : '${_ym(window['start'] as Map<String, dynamic>?)} – '
            '${_ym(window['end'] as Map<String, dynamic>?)}';

  // Climate: incomplete months are shown as gaps (null), never zero.
  final months = <MonthlyClimate>[
    for (final o in _list(seasonal['observations']))
      MonthlyClimate(
        month: (o['period'] as Map<String, dynamic>)['month'] as int,
        year: (o['period'] as Map<String, dynamic>)['year'] as int?,
        rainMm: o['rainfall_complete'] == true
            ? (o['rainfall_mm'] as num?)?.toDouble()
            : null,
        tempMeanC: o['temperature_complete'] == true
            ? (o['mean_temperature_c'] as num?)?.toDouble()
            : null,
      ),
  ];

  final dataGaps = <DataGap>[
    for (final m in _list(climate['rainfall_gap_months']))
      DataGap(
        field: 'rain_mm.${_ym(m)}',
        reason: 'Month incomplete in supplied data.',
      ),
    for (final m in _list(climate['temperature_gap_months']))
      DataGap(
        field: 'temp_mean_c.${_ym(m)}',
        reason: 'Month incomplete in supplied data.',
      ),
    if (field['current_crop'] == null)
      const DataGap(field: 'current_crop', reason: 'Not reported by farmer.'),
    if (field['irrigation_available'] == null)
      const DataGap(field: 'irrigation', reason: 'Not reported by farmer.'),
    if ((d['soil'] as Map<String, dynamic>?)?['drainage'] == null)
      const DataGap(field: 'drainage', reason: 'Not reported by farmer.'),
  ];

  final scenarios = <RotationScenario>[];
  for (final a in _list(rotations['scenarios'])) {
    final sc = a['scenario'] as Map<String, dynamic>;
    final crops = _list(a['crops']);
    final steps = <RotationStep>[];
    final rawSteps = _list(sc['steps']);
    for (var i = 0; i < rawSteps.length; i++) {
      final st = rawSteps[i];
      final w = st['growing_window'] as Map<String, dynamic>?;
      steps.add(
        RotationStep(
          cropId: st['crop_id'] as String,
          startMonth: (w?['start'] as Map<String, dynamic>?)?['month'] as int?,
          endMonth: (w?['end'] as Map<String, dynamic>?)?['month'] as int?,
          feasibility: i < crops.length
              ? _eligibility(crops[i]['eligibility'])
              : Feasibility.unknown,
        ),
      );
    }
    final evidence = [
      ..._list(a['evidence']),
      for (final c in crops) ..._list(c['evidence']),
    ];
    scenarios.add(
      RotationScenario(
        id: sc['id'] as String,
        title: sc['label'] as String? ?? sc['id'] as String,
        isBaseline: sc['is_baseline'] as bool? ?? false,
        steps: steps,
        eligibility: _eligibility(a['eligibility']),
        likelyBenefits: _messages(a['possible_benefits']),
        risks: [
          for (final r in [
            ..._list(a['risks']),
            for (final c in crops) ..._list(c['risks']),
          ])
            ScenarioRisk(
              hazard: r['code'] as String? ?? 'risk',
              level: null,
              note: r['message'] as String? ?? '',
            ),
        ],
        limitations: {
          ..._messages(a['missing_information']),
          for (final c in crops) ..._messages(c['missing_information']),
        }.toList(),
        evidenceIds: {
          for (final e in evidence)
            for (final r in (e['source_refs'] as List<dynamic>? ?? const []))
              r as String,
        }.toList(),
      ),
    );
  }
  // Baseline first, keep engine order otherwise.
  scenarios.sort((a, b) => (b.isBaseline ? 1 : 0) - (a.isBaseline ? 1 : 0));

  final references = <Reference>[
    Reference(
      id: _envRefId,
      title: meta['source'] as String? ?? 'Environmental series',
      type: _dataKindType(meta['data_kind']),
      period: period,
      note: [
        if (meta['dataset'] != null) 'Dataset: ${meta['dataset']}',
        if (meta['data_kind'] != null) 'Kind: ${meta['data_kind']}',
      ].join(' · '),
    ),
    for (final s in _list(rotations['sources']))
      Reference(
        id: s['id'] as String,
        title: s['citation'] as String? ?? s['id'] as String,
        type: _sourceType(s['status']),
        note: s['scope'] as String?,
      ),
  ];

  final synthetic =
      d['data_mode'] == 'synthetic_demo' ||
      rotations['contains_synthetic_references'] == true ||
      meta['data_kind'] == 'hypothetical';

  return FieldAnalysis(
    location: FieldLocation(
      latitude: (envr['latitude'] as num).toDouble(),
      longitude: (envr['longitude'] as num).toDouble(),
      name: synthetic ? 'Synthetic demo field' : field['field_id'] as String?,
    ),
    climateSummary: ClimateSummary(
      months: months,
      period: period,
      sourceId: _envRefId,
      totalRainMm: (climate['rainfall_total_mm'] as num?)?.toDouble(),
      meanTempC: (climate['calendar_day_weighted_mean_temperature_c'] as num?)
          ?.toDouble(),
      dataKind: meta['data_kind'] as String?,
      limitations: [
        for (final l in climate['limitations'] as List<dynamic>? ?? const [])
          l as String,
      ],
    ),
    scenarios: scenarios,
    alerts: const [],
    assumptions: [
      for (final l in rotations['limitations'] as List<dynamic>? ?? const [])
        l as String,
    ],
    dataGaps: dataGaps,
    references: references,
    dataQuality: DataQuality(isDemo: synthetic),
    notices: [
      for (final n in _list(d['notices'])) n['message'] as String? ?? '',
    ],
  );
}
