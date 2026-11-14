import 'dart:convert';

import '../environment/nasa_power_client.dart';
import '../models/farmer_input.dart';
import '../models/integration_trace.dart';
import '../models/field_analysis.dart';
import 'engine_envelope.dart';

/// No crop profiles or candidate rotations are supplied by the climate API.
/// Legacy FieldInput uses an empty string for unreported crop; no crop is invented.
Map<String, dynamic> buildLiveIntegrationRequest(FarmerInput input, NasaPowerEvidence evidence) => {
  'data_mode': 'supplied_data',
  'field': {
    'field_id': 'selected-field', 'latitude': input.latitude, 'longitude': input.longitude,
    'current_crop': input.currentCrop ?? '',
    'irrigation_available': switch (input.irrigation) {
      Irrigation.full => true,
      Irrigation.none => false,
      _ => null, // Seasonal/partial availability cannot establish a prerequisite.
    },
  },
  'soil': {'texture': null, 'drainage': switch (input.drainage) {
    Drainage.good => 'well', Drainage.unknown => null, _ => input.drainage.name,
  }},
  'environment': evidence.environment,
  'crop_references': {'sources': <Object>[], 'profiles': <Object>[]},
  'scenarios': <Object>[],
};

/// Both live HTTP and captured-real-response tests use this exact bridge path.
Future<FieldAnalysis> analyzeNasaEvidence({required FarmerInput input,
  required HistoricalWindow window, required NasaPowerEvidence evidence,
  required Future<String> Function(String) analyzeIntegration,
  required String retrievalMode}) async {
  // Revalidate at the boundary so a previously parsed response cannot be reused
  // accidentally for a different selected field/window.
  NasaPowerEvidence.parse(evidence.rawJson, input, window);
  final request = jsonEncode(buildLiveIntegrationRequest(input, evidence));
  final output = await analyzeIntegration(request);
  final trace = IntegrationTrace(backendResponseJson: evidence.rawJson,
    farmerInputJson: jsonEncode(input.toJson()), rustRequestJson: request,
    rustResultJson: output, retrievalMode: retrievalMode);
  return fieldAnalysisFromEnvelope(output, trace: trace);
}
