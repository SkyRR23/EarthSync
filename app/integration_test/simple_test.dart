import 'dart:convert';

import 'package:earthsync/data/engine/engine_envelope.dart';
import 'package:earthsync/src/rust/api/bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test_support/nasa_bridge_checks.dart';

/// On-device check that Flutter -> bridge -> team engine works.
///   flutter test integration_test/simple_test.dart -d PHONE_ID
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerNasaBridgeChecks();

  test('Flutter can call the team engine on device', () {
    expect(engineVersion(), contains('field_shift_engine'));
  });

  test(
    'farmer answers reach the engine and come back as an analysis',
    () async {
      final out = await analyzeSyntheticDemoJson(
        farmerJson: jsonEncode({
          'current_crop': 'rice',
          'irrigation': 'none',
          'drainage': 'poor',
        }),
      );
      final env = jsonDecode(out) as Map<String, dynamic>;
      expect(env['status'], 'success');
      expect(env['data']['soil']['drainage'], 'poor');
      final a = fieldAnalysisFromEnvelope(out);
      expect(a.scenarios.where((s) => s.isBaseline), hasLength(1));
      expect(a.dataQuality.isDemo, isTrue);
    },
  );

  test('invalid request returns an error envelope, not success', () async {
    final out = await analyzeIntegrationJson(requestJson: '{}');
    expect(jsonDecode(out)['status'], 'error');
  });
}
