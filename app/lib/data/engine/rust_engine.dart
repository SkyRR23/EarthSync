import 'dart:convert';

import '../../src/rust/api/bridge.dart' as rust;
import '../../src/rust/frb_generated.dart';
import '../environment/nasa_power_client.dart';
import 'live_integration.dart';
import '../models/farmer_input.dart';
import '../models/field_analysis.dart';
import 'engine_envelope.dart';
import 'engine_gateway.dart';

/// Fetches climate from Python, then calls the existing on-device JSON bridge.
/// Synthetic mode is an explicit developer choice, never an outage fallback.
class RustEngine implements EngineGateway {
  RustEngine({
    NasaPowerClient? climateClient,
    this.window = const HistoricalWindow(),
  }) : _climateClient = climateClient ?? NasaPowerClient();
  final NasaPowerClient _climateClient;
  final HistoricalWindow window;
  static const syntheticDemo =
      String.fromEnvironment('CLIMATE_MODE', defaultValue: 'live') ==
      'synthetic_demo';
  static bool _ready = false;
  static Future<void>? _initializing;

  /// Load on demand so browsing climate never depends on native engine startup.
  static Future<void> init() async {
    if (_ready) return;
    try {
      await (_initializing ??= RustLib.init());
      _ready = true;
    } catch (_) {
      _initializing = null;
      rethrow;
    }
  }

  @override
  Future<FieldAnalysis> analyzeField(FarmerInput input) async {
    try {
      await init();
    } catch (_) {
      throw const EngineError(
        code: 'bridge_not_ready',
        message:
            'The analysis engine did not start. You can still explore climate on the dashboard.',
        retryable: true,
      );
    }
    if (!syntheticDemo) {
      final evidence = await _climateClient.fetch(input, window);
      return analyzeNasaEvidence(
        input: input,
        window: window,
        evidence: evidence,
        analyzeIntegration: (request) =>
            rust.analyzeIntegrationJson(requestJson: request),
        retrievalMode: 'live_http',
      );
    }
    final farmer = jsonEncode({
      'current_crop': input.currentCrop,
      'irrigation': input.irrigation.name,
      'drainage': input.drainage.name,
    });
    final envelope = await rust.analyzeSyntheticDemoJson(farmerJson: farmer);
    return fieldAnalysisFromEnvelope(envelope);
  }

  @override
  Future<String> engineVersion() async =>
      _ready ? rust.engineVersion() : 'rust-engine (not started)';
}
