import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earthsync/evidence/data/platform_farms.dart';
import 'package:earthsync/evidence/data/platform_transport.dart';
import 'package:earthsync/evidence/features/field/agricultural_intelligence_panel.dart';

void main() {
  testWidgets(
    'farm key preserves entered dates when refresh inserts loading UI',
    (tester) async {
      final loading = ValueNotifier(false);
      final farm = PlatformFarm.fromJson({
        'id': 'owned-farm',
        'confirmed_point': {'latitude': 42.0308, 'longitude': -93.6319},
        'production_system': 'rainfed',
      });
      final client = PlatformFarmClient(
        PlatformTransport(
          MockClient((_) async => http.Response('{}', 500)),
          baseUri: Uri.parse('http://127.0.0.1:8021'),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ValueListenableBuilder<bool>(
                valueListenable: loading,
                builder: (_, busy, _) => Column(
                  children: [
                    if (busy) const LinearProgressIndicator(),
                    AgriculturalIntelligencePanel(
                      key: ValueKey('water:${farm.id}'),
                      farm: farm,
                      client: client,
                      records: const [],
                      onSaved: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final field = find.widgetWithText(
        TextField,
        'Water / first crop start (YYYY-MM-DD)',
      );
      await tester.enterText(field, '2024-07-03');
      loading.value = true;
      await tester.pump();
      expect(find.text('2024-07-03'), findsOneWidget);
      loading.value = false;
      await tester.pump();
      expect(find.text('2024-07-03'), findsOneWidget);
      expect(tester.takeException(), isNull);
      loading.dispose();
    },
  );
  testWidgets(
    'real partial calculation keeps period ET0 unknown and exposes reasons',
    (tester) async {
      final record =
          jsonDecode(
                File(
                  '../docs/integration/7w/evidence/cached-real-water-calculation.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WaterCalculationView(record: record),
            ),
          ),
        ),
      );
      expect(
        find.textContaining('Reference ET0 total: Unknown'),
        findsOneWidget,
      );
      expect(find.textContaining('59.97'), findsOneWidget);
      expect(
        find.textContaining('RADIATION_METHOD_OUTSIDE_SUPPORTED_DOMAIN'),
        findsOneWidget,
      );
      expect(find.textContaining('ETc: Unknown'), findsOneWidget);
      expect(find.textContaining('ET0 total: 0'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'water submission sends exact confirmed point and dates once without mutation replay',
    () async {
      var calls = 0;
      final client = PlatformFarmClient(
        PlatformTransport(
          MockClient((request) async {
            calls++;
            expect(request.url.path, '/api/platform/v1/water/jobs');
            expect(request.method, 'POST');
            final body = jsonDecode(request.body) as Map;
            expect(body['farm_id'], 'owned-farm');
            expect(body['query']['point'], {
              'latitude': 42.0308,
              'longitude': -93.6319,
            });
            expect(body['query']['start'], '2024-07-03');
            return http.Response(
              '{"error":{"code":"PROVIDER_UNAVAILABLE","retryable":true}}',
              503,
            );
          }),
          baseUri: Uri.parse('http://127.0.0.1:8021'),
        ),
      );
      final farm = PlatformFarm.fromJson({
        'id': 'owned-farm',
        'confirmed_point': {'latitude': 42.0308, 'longitude': -93.6319},
        'production_system': 'rainfed',
      });
      await expectLater(
        client.water(farm.id, farm.point, '2024-07-03', '2024-07-07'),
        throwsA(isA<PlatformFailure>()),
      );
      expect(calls, 1);
    },
  );
}
