/// Opt-in assistant.v1-proposal; independent of NASA and engine v0.2 payloads.
library;

const assistantVersion = 'assistant.v1-proposal';

enum AssistantKind {
  observed('observed'), modeled('modeled'), forecast('forecast'),
  farmerReported('farmer_reported'), synthetic('synthetic'), unavailable('unavailable');
  const AssistantKind(this.wire);
  final String wire;
}
enum AssistantTopic {
  climate, rainfall, temperature, soil, vegetation, radar, photo, farmerInput;
  String get wire => this == farmerInput ? 'farmer_input' : name;
}
enum AssistantQuality { available, missing, partial, stale, contradictory, unavailable, unverified }
enum AssistantScope { regional, field, unlocated }
enum AssistantCategory {
  retrievedFact('retrieved_fact'), deterministicCalculation('deterministic_calculation'),
  generalKnowledge('general_knowledge'), unavailableEvidence('unavailable_evidence');
  const AssistantCategory(this.wire);
  final String wire;
}

T _enum<T extends Enum>(List<T> values, Object? value) =>
    values.firstWhere((e) => e.name == value, orElse: () => throw const FormatException('Unknown assistant enum'));
List<String> _strings(Object? value) => List<String>.from(value as List? ?? const []);
List<Map<String, dynamic>> _maps(Object? value) =>
    (value as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

class AssistantPoint {
  const AssistantPoint(this.latitude, this.longitude);
  final double latitude, longitude;
  Map<String, dynamic> toJson() => {'latitude': latitude, 'longitude': longitude};
  factory AssistantPoint.fromJson(Map<String, dynamic> j) => AssistantPoint(
    (j['latitude'] as num).toDouble(), (j['longitude'] as num).toDouble());
}

class AssistantSelection {
  AssistantSelection({required this.id, required this.point, List<AssistantPoint> boundary = const []})
      : boundary = List.unmodifiable(boundary);
  final String id;
  final AssistantPoint point;
  final List<AssistantPoint> boundary;
  Map<String, dynamic> toJson() => {'id': id, 'point': point.toJson(),
    'boundary': boundary.map((p) => p.toJson()).toList()};
  factory AssistantSelection.fromJson(Map<String, dynamic> j) => AssistantSelection(
    id: j['id'] as String, point: AssistantPoint.fromJson(j['point'] as Map<String, dynamic>),
    boundary: _maps(j['boundary']).map(AssistantPoint.fromJson).toList());
}

class AssistantSource {
  const AssistantSource({required this.id, required this.provider, required this.title, this.url});
  final String id, provider, title;
  final String? url;
  Map<String, dynamic> toJson() => {'id': id, 'provider': provider, 'title': title, 'url': url};
  factory AssistantSource.fromJson(Map<String, dynamic> j) => AssistantSource(
    id: j['id'] as String, provider: j['provider'] as String,
    title: j['title'] as String, url: j['url'] as String?);
}

class AssistantEvidence {
  AssistantEvidence({required this.id, required this.topic, required this.metric,
    required this.kind, required this.quality, required this.scope,
    this.value, this.unit, this.startDate, this.endDate, this.retrievedAt,
    this.spatialSupport, this.locationId, List<String> sourceIds = const [],
    List<String> limitations = const [], this.calculation = 'none'})
      : sourceIds = List.unmodifiable(sourceIds), limitations = List.unmodifiable(limitations) {
    if (value != null && value is! num && value is! String) {
      throw const FormatException('Evidence value must be numeric, text or null');
    }
  }
  final String id, metric;
  final AssistantTopic topic;
  final AssistantKind kind;
  final AssistantQuality quality;
  final AssistantScope scope;
  final Object? value;
  final String? unit, startDate, endDate, retrievedAt, spatialSupport, locationId;
  final String calculation;
  final List<String> sourceIds, limitations;
  Map<String, dynamic> toJson() => {'id': id, 'topic': topic.wire, 'metric': metric,
    'kind': kind.wire, 'quality': quality.name, 'scope': scope.name, 'value': value,
    'unit': unit, 'start_date': startDate, 'end_date': endDate, 'retrieved_at': retrievedAt,
    'spatial_support': spatialSupport, 'location_id': locationId,
    'source_ids': sourceIds, 'limitations': limitations, 'calculation': calculation};
  factory AssistantEvidence.fromJson(Map<String, dynamic> j) => AssistantEvidence(
    id: j['id'] as String, topic: AssistantTopic.values.firstWhere((t) => t.wire == j['topic']), metric: j['metric'] as String,
    kind: AssistantKind.values.firstWhere((k) => k.wire == j['kind']),
    quality: _enum(AssistantQuality.values, j['quality']), scope: _enum(AssistantScope.values, j['scope']),
    value: j['value'], unit: j['unit'] as String?, startDate: j['start_date'] as String?,
    endDate: j['end_date'] as String?, retrievedAt: j['retrieved_at'] as String?,
    spatialSupport: j['spatial_support'] as String?, locationId: j['location_id'] as String?,
    sourceIds: _strings(j['source_ids']), limitations: _strings(j['limitations']),
    calculation: j['calculation'] as String? ?? 'none');
}

/// Exact supplied Rust status. No local eligibility mapping or crop ranking.
class AssistantDecision {
  AssistantDecision({required this.id, required this.scenarioId, required this.status,
    List<String> sourceIds = const [], List<String> evidenceIds = const [],
    List<String> limitations = const [], this.synthetic = false})
      : sourceIds = List.unmodifiable(sourceIds), evidenceIds = List.unmodifiable(evidenceIds),
        limitations = List.unmodifiable(limitations);
  final String id, scenarioId, status;
  final List<String> sourceIds, evidenceIds, limitations;
  final bool synthetic;
  Map<String, dynamic> toJson() => {'id': id, 'scenario_id': scenarioId, 'status': status,
    'source_ids': sourceIds, 'evidence_ids': evidenceIds, 'limitations': limitations, 'synthetic': synthetic};
  factory AssistantDecision.fromJson(Map<String, dynamic> j) => AssistantDecision(
    id: j['id'] as String, scenarioId: j['scenario_id'] as String, status: j['status'] as String,
    sourceIds: _strings(j['source_ids']), evidenceIds: _strings(j['evidence_ids']),
    limitations: _strings(j['limitations']), synthetic: j['synthetic'] as bool? ?? false);
}

class AssistantContext {
  AssistantContext({required this.contextId, this.approximateLocation, this.selectedArea,
    this.confirmedFarm, List<AssistantEvidence> evidence = const [],
    List<AssistantDecision> decisions = const [], List<AssistantSource> sources = const [],
    List<String> limitations = const []})
      : evidence = List.unmodifiable(evidence), decisions = List.unmodifiable(decisions),
        sources = List.unmodifiable(sources), limitations = List.unmodifiable(limitations);
  final String contextId;
  final AssistantPoint? approximateLocation;
  final AssistantSelection? selectedArea, confirmedFarm;
  final List<AssistantEvidence> evidence;
  final List<AssistantDecision> decisions;
  final List<AssistantSource> sources;
  final List<String> limitations;
  Map<String, dynamic> toJson() => {'schema_version': assistantVersion, 'context_id': contextId,
    'approximate_location': approximateLocation?.toJson(), 'selected_area': selectedArea?.toJson(),
    'confirmed_farm': confirmedFarm?.toJson(), 'evidence': evidence.map((e) => e.toJson()).toList(),
    'decisions': decisions.map((d) => d.toJson()).toList(), 'sources': sources.map((s) => s.toJson()).toList(),
    'limitations': limitations};
  factory AssistantContext.fromJson(Map<String, dynamic> j) {
    if ((j['schema_version'] ?? assistantVersion) != assistantVersion) {
      throw const FormatException('Unsupported assistant context');
    }
    return AssistantContext(contextId: j['context_id'] as String,
      approximateLocation: j['approximate_location'] == null ? null : AssistantPoint.fromJson(j['approximate_location'] as Map<String, dynamic>),
      selectedArea: j['selected_area'] == null ? null : AssistantSelection.fromJson(j['selected_area'] as Map<String, dynamic>),
      confirmedFarm: j['confirmed_farm'] == null ? null : AssistantSelection.fromJson(j['confirmed_farm'] as Map<String, dynamic>),
      evidence: _maps(j['evidence']).map(AssistantEvidence.fromJson).toList(),
      decisions: _maps(j['decisions']).map(AssistantDecision.fromJson).toList(),
      sources: _maps(j['sources']).map(AssistantSource.fromJson).toList(), limitations: _strings(j['limitations']));
  }
}

class AssistantClaim {
  AssistantClaim({required this.category, required this.text, List<String> evidenceIds = const [], List<String> sourceIds = const []})
      : evidenceIds = List.unmodifiable(evidenceIds), sourceIds = List.unmodifiable(sourceIds);
  final AssistantCategory category;
  final String text;
  final List<String> evidenceIds, sourceIds;
  factory AssistantClaim.fromJson(Map<String, dynamic> j) => AssistantClaim(
    category: AssistantCategory.values.firstWhere((c) => c.wire == j['category']), text: j['text'] as String,
    evidenceIds: _strings(j['evidence_ids']), sourceIds: _strings(j['source_ids']));
}

class AssistantAnswer {
  AssistantAnswer({required this.contextId, required this.language, required this.intent,
    required List<AssistantClaim> claims, List<AssistantSource> citations = const [],
    List<AssistantEvidence> evidence = const [], List<AssistantDecision> decisions = const [],
    List<String> limitations = const [], List<String> warnings = const [], List<String> suggestions = const []})
      : claims = List.unmodifiable(claims), citations = List.unmodifiable(citations),
        evidence = List.unmodifiable(evidence), decisions = List.unmodifiable(decisions),
        limitations = List.unmodifiable(limitations), warnings = List.unmodifiable(warnings),
        suggestions = List.unmodifiable(suggestions);
  final String contextId, language, intent;
  final List<AssistantClaim> claims;
  final List<AssistantSource> citations;
  final List<AssistantEvidence> evidence;
  final List<AssistantDecision> decisions;
  final List<String> limitations, warnings, suggestions;
  factory AssistantAnswer.fromJson(Map<String, dynamic> j) {
    if (j['schema_version'] != assistantVersion) throw const FormatException('Unsupported assistant response');
    final answer = AssistantAnswer(contextId: j['context_id'] as String, language: j['language'] as String,
      intent: j['intent'] as String, claims: _maps(j['claims']).map(AssistantClaim.fromJson).toList(),
      citations: _maps(j['citations']).map(AssistantSource.fromJson).toList(),
      evidence: _maps(j['evidence']).map(AssistantEvidence.fromJson).toList(),
      decisions: _maps(j['decisions']).map(AssistantDecision.fromJson).toList(),
      limitations: _strings(j['limitations']), warnings: _strings(j['warnings']), suggestions: _strings(j['suggested_questions']));
    final ids = answer.citations.map((s) => s.id).toSet();
    if (ids.length != answer.citations.length || answer.claims.any((c) => c.sourceIds.any((id) => !ids.contains(id)))) {
      throw const FormatException('Unresolved assistant citation');
    }
    return answer;
  }
}
