/// Mirrors contract v1 `FieldAnalysis` (master plan §07).
/// Field names follow snake_case JSON from the Rust engine / fixtures.
library;

/// supported   = matches supplied crop facts (engine: supported_by_supplied_evidence)
/// conflicts   = conflicts with supplied crop facts
/// constrained = partly limited (mock data only)
/// unknown     = not enough information
enum Feasibility { supported, constrained, conflicts, unknown }

enum RiskLevel { high, medium, low, unknown }

enum EvidenceType { observation, model, imagery, reference, unverified }

T _enum<T extends Enum>(List<T> values, Object? raw, T fallback) {
  for (final v in values) {
    if (v.name == raw) return v;
  }
  return fallback;
}

List<String> _strings(Object? raw) =>
    (raw as List<dynamic>? ?? const []).map((e) => e.toString()).toList();

double? _num(Object? raw) => raw is num ? raw.toDouble() : null;

class FieldAnalysis {
  const FieldAnalysis({
    required this.location,
    required this.climateSummary,
    required this.scenarios,
    required this.alerts,
    required this.assumptions,
    required this.dataGaps,
    required this.references,
    required this.dataQuality,
    this.notices = const [],
  });

  final FieldLocation location;
  final ClimateSummary climateSummary;

  /// scenarios[0] is the baseline (farmer's current practice).
  final List<RotationScenario> scenarios;
  final List<Alert> alerts;
  final List<String> assumptions;
  final List<DataGap> dataGaps;
  final List<Reference> references;
  final DataQuality dataQuality;

  /// Plain-language notes from the engine that must be shown with results
  /// (e.g. "synthetic data", "rotation rules unavailable").
  final List<String> notices;

  RotationScenario? get baseline =>
      scenarios.where((s) => s.isBaseline).firstOrNull ?? scenarios.firstOrNull;

  Reference? reference(String id) =>
      references.where((r) => r.id == id).firstOrNull;

  factory FieldAnalysis.fromJson(Map<String, dynamic> j) => FieldAnalysis(
    location: FieldLocation.fromJson(j['location'] as Map<String, dynamic>),
    climateSummary: ClimateSummary.fromJson(
      j['climate_summary'] as Map<String, dynamic>,
    ),
    scenarios: (j['scenarios'] as List<dynamic>)
        .map((e) => RotationScenario.fromJson(e as Map<String, dynamic>))
        .toList(),
    alerts: (j['alerts'] as List<dynamic>? ?? const [])
        .map((e) => Alert.fromJson(e as Map<String, dynamic>))
        .toList(),
    assumptions: _strings(j['assumptions']),
    dataGaps: (j['data_gaps'] as List<dynamic>? ?? const [])
        .map((e) => DataGap.fromJson(e as Map<String, dynamic>))
        .toList(),
    references: (j['references'] as List<dynamic>? ?? const [])
        .map((e) => Reference.fromJson(e as Map<String, dynamic>))
        .toList(),
    dataQuality: DataQuality.fromJson(
      j['data_quality'] as Map<String, dynamic>? ?? const {},
    ),
  );
}

class FieldLocation {
  const FieldLocation({
    required this.latitude,
    required this.longitude,
    this.name,
  });
  final double latitude;
  final double longitude;
  final String? name;

  factory FieldLocation.fromJson(Map<String, dynamic> j) => FieldLocation(
    latitude: (j['latitude'] as num).toDouble(),
    longitude: (j['longitude'] as num).toDouble(),
    name: j['name'] as String?,
  );
}

class ClimateSummary {
  const ClimateSummary({
    required this.months,
    required this.period,
    required this.sourceId,
    this.totalRainMm,
    this.meanTempC,
    this.dataKind,
    this.limitations = const [],
    this.gridResolution,
  });

  /// Always 12 entries Jan..Dec; values may be null (missing, never zero).
  final List<MonthlyClimate> months;
  final String period;
  final String sourceId;
  final String? gridResolution;

  /// Season totals computed by the engine (not by Flutter).
  final double? totalRainMm;
  final double? meanTempC;

  /// observed | modeled | forecast | hypothetical
  final String? dataKind;
  final List<String> limitations;

  factory ClimateSummary.fromJson(Map<String, dynamic> j) => ClimateSummary(
    months: (j['monthly'] as List<dynamic>)
        .map((e) => MonthlyClimate.fromJson(e as Map<String, dynamic>))
        .toList(),
    period: j['period'] as String? ?? '',
    sourceId: j['source_id'] as String? ?? '',
    gridResolution: j['grid_resolution'] as String?,
  );
}

class MonthlyClimate {
  const MonthlyClimate({
    required this.month,
    this.year,
    this.rainMm,
    this.tempMeanC,
  });
  final int? year;
  final int month;
  final double? rainMm;
  final double? tempMeanC;

  factory MonthlyClimate.fromJson(Map<String, dynamic> j) => MonthlyClimate(
    month: j['month'] as int,
    rainMm: _num(j['rain_mm']),
    tempMeanC: _num(j['temp_mean_c']),
  );
}

class RotationScenario {
  const RotationScenario({
    required this.id,
    required this.title,
    required this.isBaseline,
    required this.steps,
    required this.eligibility,
    required this.likelyBenefits,
    required this.risks,
    required this.limitations,
    required this.evidenceIds,
  });

  final String id;
  final String title;
  final bool isBaseline;
  final List<RotationStep> steps;
  final Feasibility eligibility;
  final List<String> likelyBenefits;
  final List<ScenarioRisk> risks;
  final List<String> limitations;
  final List<String> evidenceIds;

  factory RotationScenario.fromJson(Map<String, dynamic> j) => RotationScenario(
    id: j['id'] as String,
    title: j['title'] as String,
    isBaseline: j['is_baseline'] as bool? ?? false,
    steps: (j['steps'] as List<dynamic>)
        .map((e) => RotationStep.fromJson(e as Map<String, dynamic>))
        .toList(),
    eligibility: _enum(
      Feasibility.values,
      j['eligibility'],
      Feasibility.unknown,
    ),
    likelyBenefits: _strings(j['likely_benefits']),
    risks: (j['risks'] as List<dynamic>? ?? const [])
        .map((e) => ScenarioRisk.fromJson(e as Map<String, dynamic>))
        .toList(),
    limitations: _strings(j['limitations']),
    evidenceIds: _strings(j['evidence_ids']),
  );
}

class RotationStep {
  const RotationStep({
    required this.cropId,
    this.startMonth,
    this.endMonth,
    this.feasibility = Feasibility.unknown,
  });

  final String cropId;

  /// 1–12. null = window unknown.
  final int? startMonth;
  final int? endMonth;
  final Feasibility feasibility;

  factory RotationStep.fromJson(Map<String, dynamic> j) => RotationStep(
    cropId: j['crop_id'] as String,
    startMonth: j['start_month'] as int?,
    endMonth: j['end_month'] as int?,
    feasibility: _enum(
      Feasibility.values,
      j['feasibility'],
      Feasibility.unknown,
    ),
  );
}

class ScenarioRisk {
  const ScenarioRisk({
    required this.hazard,
    required this.level,
    required this.note,
  });
  final String hazard; // drought | heat | waterlogging | ...
  /// null = engine flagged a risk but gave no level.
  final RiskLevel? level;
  final String note;

  factory ScenarioRisk.fromJson(Map<String, dynamic> j) => ScenarioRisk(
    hazard: j['hazard'] as String,
    level: _enum(RiskLevel.values, j['level'], RiskLevel.unknown),
    note: j['note'] as String? ?? '',
  );
}

class Alert {
  const Alert({
    required this.hazard,
    required this.level,
    required this.message,
    this.evidenceIds = const [],
  });
  final String hazard;
  final RiskLevel level;
  final String message;
  final List<String> evidenceIds;

  factory Alert.fromJson(Map<String, dynamic> j) => Alert(
    hazard: j['hazard'] as String,
    level: _enum(RiskLevel.values, j['level'], RiskLevel.unknown),
    message: j['message'] as String? ?? '',
    evidenceIds: _strings(j['evidence_ids']),
  );
}

class DataGap {
  const DataGap({required this.field, required this.reason});
  final String field;
  final String reason;

  factory DataGap.fromJson(Map<String, dynamic> j) => DataGap(
    field: j['field'] as String,
    reason: j['reason'] as String? ?? '',
  );
}

class Reference {
  const Reference({
    required this.id,
    required this.title,
    required this.type,
    this.period,
    this.spatialScale,
    this.url,
    this.note,
  });

  final String id;
  final String title;
  final EvidenceType type;
  final String? period;
  final String? spatialScale;
  final String? url;
  final String? note;

  factory Reference.fromJson(Map<String, dynamic> j) => Reference(
    id: j['id'] as String,
    title: j['title'] as String,
    type: _enum(EvidenceType.values, j['type'], EvidenceType.unverified),
    period: j['period'] as String?,
    spatialScale: j['spatial_scale'] as String?,
    url: j['url'] as String?,
    note: j['note'] as String?,
  );
}

class DataQuality {
  const DataQuality({this.isDemo = false, this.fetchedAt, this.stale = false});
  final bool isDemo;
  final DateTime? fetchedAt;
  final bool stale;

  factory DataQuality.fromJson(Map<String, dynamic> j) => DataQuality(
    isDemo: j['is_demo'] as bool? ?? false,
    fetchedAt: DateTime.tryParse(j['fetched_at'] as String? ?? ''),
    stale: j['stale'] as bool? ?? false,
  );
}

/// Mirrors contract v1 API error. Rust surfaces these instead of silent success.
class EngineError implements Exception {
  const EngineError({
    required this.code,
    required this.message,
    this.retryable = false,
    this.missingSources = const [],
  });

  final String code;
  final String message;
  final bool retryable;
  final List<String> missingSources;

  @override
  String toString() => 'EngineError($code): $message';
}
