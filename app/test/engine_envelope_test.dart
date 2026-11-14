import 'dart:io';

import 'package:earthsync/data/engine/engine_envelope.dart';
import 'package:earthsync/data/models/field_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

/// test/fixtures/engine_success_envelope.json is real output of
/// engine `analyze_integration_json` on engine/tests/fixtures/
/// synthetic_integration_request.json. Regenerate if the engine contract changes.
void main() {
  final success = File('test/fixtures/engine_success_envelope.json').readAsStringSync();

  test('success envelope maps to baseline-first scenarios', () {
    final a = fieldAnalysisFromEnvelope(success);
    expect(a.scenarios, hasLength(3));
    expect(a.scenarios.first.isBaseline, isTrue);
    expect(a.scenarios.first.id, 'existing');
  });

  test('engine eligibility is kept, never upgraded', () {
    final a = fieldAnalysisFromEnvelope(success);
    // Whole rotations are insufficient_information in the engine.
    expect(a.scenarios.every((s) => s.eligibility == Feasibility.unknown), isTrue);
    // Per-step categorical checks pass in the synthetic fixture.
    expect(a.scenarios.first.steps.first.feasibility, Feasibility.supported);
  });

  test('synthetic data is flagged and notices are carried', () {
    final a = fieldAnalysisFromEnvelope(success);
    expect(a.dataQuality.isDemo, isTrue);
    expect(a.notices, isNotEmpty);
    expect(a.climateSummary.totalRainMm, 100);
    expect(a.climateSummary.months.map((m) => m.month), [11, 12, 1, 2]);
  });

  test('error envelope becomes EngineError with the engine message', () {
    const err =
        '{"status":"error","error":{"code":"INVALID_ROTATIONS","message":"Crop references are invalid.","component":"rotations","detail":null,"retryable":false}}';
    expect(
      () => fieldAnalysisFromEnvelope(err),
      throwsA(isA<EngineError>()
          .having((e) => e.code, 'code', 'INVALID_ROTATIONS')
          .having((e) => e.retryable, 'retryable', false)),
    );
  });

  test('garbage output is an error, not a silent success', () {
    expect(() => fieldAnalysisFromEnvelope('nope'), throwsA(isA<EngineError>()));
  });
}
