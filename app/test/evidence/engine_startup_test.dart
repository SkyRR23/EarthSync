import 'dart:io';
import 'package:earthsync/evidence/data/engine/rust_engine.dart';
import 'package:earthsync/evidence/data/environment/nasa_power_client.dart';
import 'package:earthsync/evidence/data/models/farmer_input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'native analysis initializes on demand using the unchanged NASA/Rust contract',
    () async {
      final capture = File(
        'assets/fixtures/nasa_power_real.json',
      ).readAsStringSync();
      final engine = RustEngine(
        climateClient: NasaPowerClient(
          client: MockClient((_) async => http.Response(capture, 200)),
        ),
      );
      // Deliberately do not call RustEngine.init before analyzing.
      final result = await engine.analyzeField(
        const FarmerInput(latitude: 16.85, longitude: 96.15),
      );
      expect(result.climateSummary.totalRainMm, .04);
      expect(result.scenarios, isEmpty);
    },
  );
}
