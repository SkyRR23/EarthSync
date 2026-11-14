import 'dart:async';

import 'package:http/http.dart' as http;

import '../environment/nasa_power_client.dart';
import '../models/farmer_input.dart';
import '../models/field_analysis.dart';
import 'engine_gateway.dart';
import 'live_integration.dart';
import 'web_reference_candidates.dart';

/// The web demo runs the shared Rust engine on the local demo host.
class WebEngine implements EngineGateway {
  WebEngine({required this.window, Uri? baseUri, this.client})
    : baseUri = baseUri ?? Uri.base;
  final HistoricalWindow window;
  final Uri baseUri;
  final http.Client? client;

  @override
  Future<FieldAnalysis> analyzeField(FarmerInput input) async {
    final captured = baseUri.queryParameters['climate'] == 'captured';
    final requestClient = client ?? http.Client();
    try {
      final evidence = captured
          ? NasaPowerEvidence.parse(
              await _getCaptured(requestClient),
              input,
              window,
            )
          : await NasaPowerClient(
              baseUrl: baseUri.origin,
              client: requestClient,
            ).fetch(input, window);
      return await analyzeNasaEvidence(
        input: input,
        window: window,
        evidence: evidence,
        analyzeIntegration: (request) async {
          final response = await requestClient
              .post(
                baseUri.resolve('/api/engine/integration'),
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
        buildRequest: buildWebIntegrationRequest,
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
    } finally {
      if (client == null) requestClient.close();
    }
  }

  Future<String> _getCaptured(http.Client requestClient) async {
    final response = await requestClient
        .get(baseUri.resolve('/api/demo/captured-climate'))
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
