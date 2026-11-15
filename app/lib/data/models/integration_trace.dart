import 'dart:convert';

/// Keeps exact backend provenance and all farmer answers beside the exact Rust
/// request/result. In-memory association, not a cryptographic evidence ID.
class IntegrationTrace {
  const IntegrationTrace({
    required this.backendResponseJson,
    required this.farmerInputJson,
    required this.rustRequestJson,
    required this.rustResultJson,
    required this.retrievalMode,
  });
  final String backendResponseJson,
      farmerInputJson,
      rustRequestJson,
      rustResultJson;
  final String retrievalMode; // live_http | captured_real_response
  /// For saving the last result on the phone (offline viewing).
  Map<String, dynamic> toJson() => {
    'backend_response_json': backendResponseJson,
    'farmer_input_json': farmerInputJson,
    'rust_request_json': rustRequestJson,
    'rust_result_json': rustResultJson,
    'retrieval_mode': retrievalMode,
  };

  factory IntegrationTrace.fromJson(Map<String, dynamic> j) => IntegrationTrace(
    backendResponseJson: j['backend_response_json'] as String,
    farmerInputJson: j['farmer_input_json'] as String,
    rustRequestJson: j['rust_request_json'] as String,
    rustResultJson: j['rust_result_json'] as String,
    retrievalMode: j['retrieval_mode'] as String,
  );

  Map<String, dynamic> get provenance =>
      (jsonDecode(backendResponseJson) as Map<String, dynamic>)['provenance']
          as Map<String, dynamic>;
}
