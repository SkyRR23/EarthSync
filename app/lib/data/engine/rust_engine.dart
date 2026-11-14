import 'dart:convert';

import '../../src/rust/api/bridge.dart' as rust;
import '../../src/rust/frb_generated.dart';
import '../models/farmer_input.dart';
import '../models/field_analysis.dart';
import 'engine_envelope.dart';
import 'engine_gateway.dart';

/// Calls the team's on-device Rust engine (engine/) through the
/// field_shift_bridge crate (app/rust/).
///
/// Until P2's server exists, analysis uses the engine's synthetic request with
/// the farmer's own answers applied (`analyze_synthetic_demo_json`). Results
/// are labelled synthetic by the engine and shown with a demo banner.
/// Regenerate bindings after changing app/rust/src/api:
/// `flutter_rust_bridge_codegen generate`.
class RustEngine implements EngineGateway {
  static bool _ready = false;

  /// Call once before runApp when ENGINE=rust.
  static Future<void> init() async {
    if (_ready) return;
    await RustLib.init();
    _ready = true;
  }

  @override
  Future<FieldAnalysis> analyzeField(FarmerInput input) async {
    if (!_ready) {
      throw const EngineError(
        code: 'bridge_not_ready',
        message: 'The analysis engine did not start.',
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
