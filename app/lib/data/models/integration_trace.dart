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
  Map<String, dynamic> get provenance =>
      (jsonDecode(backendResponseJson) as Map<String, dynamic>)['provenance']
          as Map<String, dynamic>;
}
