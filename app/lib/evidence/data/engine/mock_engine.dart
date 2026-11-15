import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/farmer_input.dart';
import '../models/field_analysis.dart';
import 'engine_gateway.dart';

/// Reads the demo fixture so UI work never waits for the Rust bridge.
/// Run with `--dart-define=MOCK_FAIL=true` to test the error screen.
class MockEngine implements EngineGateway {
  MockEngine({
    this.fixture = 'assets/fixtures/field_analysis_demo.json',
    this.delay = const Duration(milliseconds: 900),
    AssetBundle? bundle,
  }) : _bundle = bundle ?? rootBundle;

  final String fixture;
  final Duration delay;
  final AssetBundle _bundle;

  static const _fail = bool.fromEnvironment('MOCK_FAIL');

  @override
  Future<FieldAnalysis> analyzeField(FarmerInput input) async {
    await Future<void>.delayed(delay);
    if (_fail) {
      throw const EngineError(
        code: 'server_unreachable',
        message: 'Could not reach the data server.',
        retryable: true,
        missingSources: ['field-context'],
      );
    }
    final raw = await _bundle.loadString(fixture);
    return FieldAnalysis.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<String> engineVersion() async => 'mock-engine (fixture)';
}
