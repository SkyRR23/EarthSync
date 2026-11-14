import 'dart:convert';

import '../../data/models/farmer_input.dart';
import '../../data/models/field_analysis.dart';
import 'assistant_models.dart';

/// The caller must decide the location role. Coordinates alone never confirm a farm.
/// Additional soil/vegetation/radar/photo records use AssistantEvidence directly.
AssistantContext assistantContextFromAnalysis({
  required String contextId,
  FieldAnalysis? analysis,
  AssistantPoint? approximateLocation,
  AssistantSelection? selectedArea,
  AssistantSelection? confirmedFarm,
  FarmerInput? farmerInput,
}) {
  final selection = confirmedFarm ?? selectedArea;
  final evidence = <AssistantEvidence>[];
  final sources = <AssistantSource>[];
  final limitations = <String>[];
  var decisions = <AssistantDecision>[];
  if (analysis != null) {
    // Reject evidence for a previous location; do not relabel its provenance.
    if (selection == null ||
        selection.point.latitude != analysis.location.latitude ||
        selection.point.longitude != analysis.location.longitude) {
      throw const FormatException(
        'Analysis does not match the explicit selection',
      );
    }
    final climate = analysis.climateSummary;
    final provenance = analysis.trace?.provenance;
    if (provenance != null) {
      final point = provenance['query_coordinates'] as Map<String, dynamic>?;
      final backend =
          jsonDecode(analysis.trace!.backendResponseJson)
              as Map<String, dynamic>;
      final environment = backend['environment'] as Map<String, dynamic>;
      if (point?['latitude'] != selection.point.latitude ||
          point?['longitude'] != selection.point.longitude ||
          provenance['data_kind'] != climate.dataKind ||
          environment['latitude'] != selection.point.latitude ||
          environment['longitude'] != selection.point.longitude) {
        throw const FormatException(
          'Climate provenance does not match the selection or kind',
        );
      }
    }
    final interval = provenance?['interval'] as Map<String, dynamic>?;
    final requests = (provenance?['source_requests'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final sourceIds = <String>[];
    for (var i = 0; i < requests.length; i++) {
      final request = requests[i];
      final endpoint = Uri.tryParse(request['endpoint'] as String? ?? '');
      final query = request['query'] as Map<String, dynamic>?;
      String? sourceUrl;
      if (endpoint != null &&
          endpoint.scheme == 'https' &&
          endpoint.host.isNotEmpty &&
          endpoint.userInfo.isEmpty) {
        sourceUrl = endpoint
            .replace(queryParameters: query?.map((k, v) => MapEntry(k, '$v')))
            .toString();
      }
      final id = 'climate-request-$i';
      sources.add(
        AssistantSource(
          id: id,
          provider: provenance?['provider'] as String? ?? 'Unknown provider',
          title: provenance?['product'] as String? ?? 'Climate evidence',
          url: sourceUrl,
        ),
      );
      sourceIds.add(id);
    }
    if (sourceIds.isEmpty) {
      final ref = analysis.reference(climate.sourceId);
      if (ref != null) {
        sources.add(
          AssistantSource(
            id: ref.id,
            provider: ref.title,
            title: ref.title,
            url: ref.url,
          ),
        );
        sourceIds.add(ref.id);
      }
    }
    final kind = switch (climate.dataKind) {
      'observed' => AssistantKind.observed,
      'modeled' => AssistantKind.modeled,
      'forecast' => AssistantKind.forecast,
      'hypothetical' || 'synthetic' => AssistantKind.synthetic,
      _ => AssistantKind.unavailable,
    };
    final quality = analysis.dataQuality.stale
        ? AssistantQuality.stale
        : AssistantQuality.available;
    final retrieved = requests.isEmpty
        ? null
        : requests.first['retrieved_at'] as String?;
    final notes = [
      ...climate.limitations,
      ...(provenance?['limitations'] as List? ?? const []).cast<String>(),
      if (analysis.trace != null)
        'Retrieval mode: ${analysis.trace!.retrievalMode}',
    ];
    AssistantEvidence climateRecord(
      String id,
      AssistantTopic topic,
      String metric,
      double? value,
      String unit,
      String? start,
      String? end,
    ) => AssistantEvidence(
      id: id,
      topic: topic,
      metric: metric,
      kind: kind,
      quality: value == null ? AssistantQuality.missing : quality,
      value: kind == AssistantKind.unavailable ? null : value,
      unit: unit,
      startDate: start,
      endDate: end,
      retrievedAt: retrieved,
      spatialSupport:
          provenance?['spatial_support'] as String? ?? climate.gridResolution,
      // A confirmed point does not turn gridded climate into a field measurement.
      scope: AssistantScope.regional,
      locationId: selection.id,
      sourceIds: sourceIds,
      limitations: notes,
      calculation: 'rust',
    );
    evidence.add(
      climateRecord(
        'climate-rain-total',
        AssistantTopic.rainfall,
        'rainfall_total',
        climate.totalRainMm,
        'mm',
        interval?['start'] as String?,
        interval?['end'] as String?,
      ),
    );
    evidence.add(
      climateRecord(
        'climate-temperature-mean',
        AssistantTopic.temperature,
        'mean_temperature',
        climate.meanTempC,
        'deg_c',
        interval?['start'] as String?,
        interval?['end'] as String?,
      ),
    );
    for (var i = 0; i < climate.months.length; i++) {
      final month = climate.months[i];
      // Yearless legacy demo months cannot become dated observations.
      final start = month.year == null
          ? null
          : _date(DateTime.utc(month.year!, month.month));
      final end = month.year == null
          ? null
          : _date(DateTime.utc(month.year!, month.month + 1, 0));
      evidence.add(
        climateRecord(
          'climate-rain-$i',
          AssistantTopic.rainfall,
          'rainfall_total',
          month.rainMm,
          'mm',
          start,
          end,
        ),
      );
    }
    limitations.addAll([
      ...analysis.assumptions,
      ...analysis.notices,
      ...analysis.dataGaps.map((g) => '${g.field}: ${g.reason}'),
    ]);
    // Preserve raw Rust status, including v0.2 distinctions. Never derive it from
    // the presentation enum, which collapses several engine states.
    if (analysis.trace != null) {
      final result = assistantFindingsFromRust(
        analysis.trace!.rustResultJson,
        expectedPoint: selection.point,
      );
      decisions = result.decisions;
      sources.addAll(
        result.sources.where(
          (s) => !sources.any((existing) => existing.id == s.id),
        ),
      );
    }
  }
  if (farmerInput != null) {
    if (selection == null ||
        selection.point.latitude != farmerInput.latitude ||
        selection.point.longitude != farmerInput.longitude) {
      throw const FormatException(
        'Farmer report does not match the explicit selection',
      );
    }
    sources.add(
      const AssistantSource(
        id: 'farmer-report',
        provider: 'Farmer',
        title: 'Farmer-reported inputs',
      ),
    );
    final reports = {
      'current_crop': farmerInput.currentCrop,
      'irrigation': farmerInput.irrigation.name,
      'drainage': farmerInput.drainage.name,
    };
    for (final report in reports.entries) {
      evidence.add(
        AssistantEvidence(
          id: 'farmer-${report.key}',
          topic: AssistantTopic.farmerInput,
          metric: report.key,
          kind: AssistantKind.farmerReported,
          quality: AssistantQuality.unverified,
          scope: confirmedFarm == null
              ? AssistantScope.regional
              : AssistantScope.field,
          locationId: selection.id,
          value: report.value,
          sourceIds: const ['farmer-report'],
        ),
      );
    }
  }
  return AssistantContext(
    contextId: contextId,
    approximateLocation: approximateLocation,
    selectedArea: selectedArea,
    confirmedFarm: confirmedFarm,
    evidence: evidence,
    sources: sources,
    decisions: decisions,
    limitations: limitations,
  );
}

String _date(DateTime value) => value.toIso8601String().substring(0, 10);

class AssistantRustFindings {
  const AssistantRustFindings(this.decisions, this.sources);
  final List<AssistantDecision> decisions;
  final List<AssistantSource> sources;
}

/// Read-only consumer of existing integration/v0.2 envelopes, no schema changes.
AssistantRustFindings assistantFindingsFromRust(
  String envelope, {
  AssistantPoint? expectedPoint,
}) {
  final root = jsonDecode(envelope) as Map<String, dynamic>;
  if (root['status'] != 'success') {
    throw const FormatException('Rust findings unavailable');
  }
  final data = root['data'] as Map<String, dynamic>;
  final v02 = data['schema_version'] == '0.2-provisional';
  if (data.containsKey('schema_version') && !v02) {
    throw const FormatException('Unsupported Rust finding schema');
  }
  final integration = v02 ? data['integration'] as Map<String, dynamic> : data;
  if (expectedPoint != null) {
    final environment = integration['environment'] as Map<String, dynamic>;
    final field = integration['field'] as Map<String, dynamic>;
    if (environment['latitude'] != expectedPoint.latitude ||
        environment['longitude'] != expectedPoint.longitude ||
        field['latitude'] != expectedPoint.latitude ||
        field['longitude'] != expectedPoint.longitude) {
      throw const FormatException(
        'Rust findings do not match the selected point',
      );
    }
  }
  final rotations = integration['rotations'] as Map<String, dynamic>;
  final sources = (rotations['sources'] as List? ?? const []).map((item) {
    final source = item as Map<String, dynamic>;
    return AssistantSource(
      id: source['id'] as String,
      provider: 'Supplied Rust reference',
      title: source['citation'] as String,
      // Current Rust references have no provider-URL field. Do not invent a link.
    );
  }).toList();
  final scenarios =
      (v02 ? data['scenarios'] : rotations['scenarios']) as List? ?? const [];
  final decisions = scenarios.map((item) {
    final scenario = item as Map<String, dynamic>;
    final id = v02
        ? scenario['scenario_id'] as String
        : scenario['scenario']['id'] as String;
    final factors = v02
        ? [
            ...(scenario['critical_constraints'] as List),
            ...(scenario['tradeoffs'] as List),
          ]
        : [
            ...(scenario['evidence'] as List? ?? const []),
            ...(scenario['missing_information'] as List? ?? const []),
          ];
    final refs = <String>{
      for (final f in factors)
        ...(f['source_refs'] as List? ?? const []).cast<String>(),
    };
    return AssistantDecision(
      id: 'rust-$id',
      scenarioId: id,
      status: (v02 ? scenario['status'] : scenario['eligibility']) as String,
      sourceIds: refs.toList(),
      limitations: [
        for (final f in factors)
          ...(f['limitations'] as List? ?? const []).cast<String>(),
        for (final f in factors)
          if (f['message'] is String) f['message'] as String,
      ],
      synthetic:
          integration['data_mode'] == 'synthetic_demo' ||
          rotations['contains_synthetic_references'] == true,
    );
  }).toList();
  return AssistantRustFindings(decisions, sources);
}
