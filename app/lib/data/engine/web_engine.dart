import 'dart:async';

import 'package:http/http.dart' as http;

import '../environment/nasa_power_client.dart';
import '../models/farmer_input.dart';
import '../models/field_analysis.dart';
import 'engine_gateway.dart';
import 'live_integration.dart';

/// The web demo runs the shared Rust engine on the local demo host.
class WebEngine implements EngineGateway {
  WebEngine({required this.window});
  final HistoricalWindow window;

  @override
  Future<FieldAnalysis> analyzeField(FarmerInput input) async {
    final captured = Uri.base.queryParameters['climate'] == 'captured';
    try {
      final evidence = captured
          ? NasaPowerEvidence.parse(await _getCaptured(), input, window)
          : await NasaPowerClient(
              baseUrl: Uri.base.origin,
            ).fetch(input, window);
      return await analyzeNasaEvidence(
        input: input,
        window: window,
        evidence: evidence,
        analyzeIntegration: (request) async {
          final response = await http
              .post(
                Uri.base.resolve('/api/engine/integration'),
                headers: {'Content-Type': 'application/json'},
                body: request,
              )
              .timeout(const Duration(seconds: 30));
          if (response.statusCode != 200) {
            throw const EngineError(
              code: 'web_engine_unavailable',
              message:
                  'The local Rust engine failed. No demo data were substituted.',
              retryable: true,
            );
          }
          return response.body;
        },
        retrievalMode: captured ? 'captured_real_response' : 'live_http',
      );
    } on EngineError {
      rethrow;
    } on TimeoutException {
      throw const EngineError(
        code: 'web_timeout',
        message: 'The demo service timed out.',
        retryable: true,
      );
    } on http.ClientException {
      throw const EngineError(
        code: 'web_unavailable',
        message: 'Could not reach the local demo service.',
        retryable: true,
      );
    }
  }

  Future<String> _getCaptured() async {
    final response = await http
        .get(Uri.base.resolve('/api/demo/captured-climate'))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw const EngineError(
        code: 'capture_unavailable',
        message: 'The captured NASA response is unavailable.',
      );
    }
    return response.body;
  }

  @override
  Future<String> engineVersion() async =>
      'Shared Rust engine · local web service';
}
