import '../models/farmer_input.dart';
import '../models/field_analysis.dart';

/// The only way the app gets analysis data. Flutter never calls the server
/// or NASA POWER directly — that is the Rust engine's job (master plan §05).
abstract interface class EngineGateway {
  /// Throws [EngineError] on failure.
  Future<FieldAnalysis> analyzeField(FarmerInput input);

  /// Used for the H2 bridge smoke test.
  Future<String> engineVersion();
}
