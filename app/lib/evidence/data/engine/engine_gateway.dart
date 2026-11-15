import '../models/farmer_input.dart';
import '../models/field_analysis.dart';

/// Analysis boundary: Flutter fetches Python climate; Rust calculates locally.
abstract interface class EngineGateway {
  /// Throws [EngineError] on failure.
  Future<FieldAnalysis> analyzeField(FarmerInput input);

  /// Used for the H2 bridge smoke test.
  Future<String> engineVersion();
}
