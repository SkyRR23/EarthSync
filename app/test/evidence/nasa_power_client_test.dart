import 'dart:convert';
import 'dart:io';

import 'package:earthsync/evidence/data/engine/engine_envelope.dart';
import 'package:earthsync/evidence/data/engine/live_integration.dart';
import 'package:earthsync/evidence/data/environment/nasa_power_client.dart';
import 'package:earthsync/evidence/data/models/farmer_input.dart';
import 'package:earthsync/evidence/data/models/field_analysis.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const point = FarmerInput(latitude: 16.85, longitude: 96.15);
const window = HistoricalWindow();
void main() {
  final raw = File('assets/fixtures/nasa_power_real.json').readAsStringSync();
  Map<String, dynamic> capture() => jsonDecode(raw) as Map<String, dynamic>;

  test(
    'HTTP uses selected coordinates and explicit historical months; retains exact text',
    () async {
      final client = NasaPowerClient(
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/environment/season');
          expect(request.url.queryParameters, {
            'latitude': '16.85',
            'longitude': '96.15',
            'start_year': '2024',
            'start_month': '2',
            'end_year': '2024',
            'end_month': '2',
          });
          return http.Response(raw, 200);
        }),
      );
      final evidence = await client.fetch(point, window);
      expect(evidence.rawJson, raw);
      expect(evidence.provenance, capture()['provenance']);
      expect(
        evidence.environment['seasonal']['observations'][0]['rainfall_mm'],
        0.04,
      );
    },
  );

  test('HTTP errors differ from valid incomplete evidence', () async {
    final failure = NasaPowerClient(
      client: MockClient((_) async => http.Response('{"status":"error"}', 503)),
    );
    await expectLater(
      failure.fetch(point, window),
      throwsA(
        isA<EngineError>()
            .having((e) => e.code, 'code', 'backend_http_503')
            .having((e) => e.retryable, 'retry', true),
      ),
    );
    final partial = capture();
    partial['environment']['seasonal']['observations'] = [];
    final evidence = NasaPowerEvidence.parse(
      jsonEncode(partial),
      point,
      window,
    );
    expect(evidence.environment['seasonal']['observations'], isEmpty);
  });

  test(
    'unsupported NASA source is actionable and arbitrary error text is withheld',
    () async {
      final client = NasaPowerClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {
                'code': 'UPSTREAM_SOURCE_CHANGED',
                'message': 'private upstream diagnostic must not be shown',
              },
            }),
            502,
          ),
        ),
      );
      await expectLater(
        client.fetch(point, window),
        throwsA(
          isA<EngineError>()
              .having(
                (error) => error.message,
                'source explanation',
                contains('GEOS-IT'),
              )
              .having(
                (error) => error.message,
                'action',
                contains('older completed historical period'),
              )
              .having(
                (error) => error.message,
                'safe text',
                isNot(contains('private upstream')),
              ),
        ),
      );
    },
  );

  test('backend outage and timeout do not load a demo', () async {
    final outage = NasaPowerClient(
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    await expectLater(
      outage.fetch(point, window),
      throwsA(
        isA<EngineError>().having((e) => e.code, 'code', 'backend_unavailable'),
      ),
    );
    final timeout = NasaPowerClient(
      timeout: Duration.zero,
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return http.Response(raw, 200);
      }),
    );
    await expectLater(
      timeout.fetch(point, window),
      throwsA(
        isA<EngineError>().having((e) => e.code, 'code', 'backend_timeout'),
      ),
    );
  });

  test('invalid location and window are rejected before HTTP', () async {
    var calls = 0;
    final client = NasaPowerClient(
      client: MockClient((_) async {
        calls++;
        return http.Response(raw, 200);
      }),
    );
    for (final latitude in [91.0, double.nan, double.infinity]) {
      await expectLater(
        client.fetch(FarmerInput(latitude: latitude, longitude: 96.15), window),
        throwsA(isA<EngineError>()),
      );
    }
    await expectLater(
      client.fetch(point, const HistoricalWindow(startMonth: 3)),
      throwsA(isA<EngineError>()),
    );
    await expectLater(
      client.fetch(point, const HistoricalWindow(startYear: 2021)),
      throwsA(isA<EngineError>()),
    );
    expect(calls, 0);
  });

  test(
    'mismatched schema, status, field, period, or provenance cannot be attached',
    () {
      final mutations = <void Function(Map<String, dynamic>)>[
        (e) => e['schema_version'] = '2',
        (e) => e['status'] = 'error',
        (e) => e['environment']['latitude'] = 16.86,
        (e) => e['provenance']['query_coordinates']['longitude'] = 96.16,
        (e) => e['environment']['seasonal']['window']['end']['month'] = 3,
        (e) => e['provenance'] = {},
        (e) =>
            e['environment']['seasonal']['metadata']['data_kind'] = 'observed',
      ];
      for (final mutate in mutations) {
        final e = capture();
        mutate(e);
        expect(
          () => NasaPowerEvidence.parse(jsonEncode(e), point, window),
          throwsA(isA<EngineError>()),
        );
      }
    },
  );

  test('release-inappropriate HTTP host is rejected', () async {
    final client = NasaPowerClient(
      baseUrl: 'http://example.com',
      client: MockClient((_) async => http.Response(raw, 200)),
    );
    await expectLater(
      client.fetch(point, window),
      throwsA(
        isA<EngineError>().having(
          (e) => e.code,
          'code',
          'backend_configuration',
        ),
      ),
    );
  });

  test(
    'unknown crop builds climate-only request, never rice or synthetic profiles',
    () {
      final request = buildLiveIntegrationRequest(
        point,
        NasaPowerEvidence.parse(raw, point, window),
      );
      expect(request['field']['current_crop'], '');
      expect(request['field']['latitude'], request['environment']['latitude']);
      expect(request['scenarios'], isEmpty);
      expect(request['crop_references'], {'sources': [], 'profiles': []});
      expect(request['data_mode'], 'supplied_data');
    },
  );

  test('farmer crop and partial irrigation are faithfully represented', () {
    const farmer = FarmerInput(
      latitude: 16.85,
      longitude: 96.15,
      currentCrop: 'sesame',
      recentRotation: ['rice'],
      plantingMonth: 6,
      irrigation: Irrigation.partial,
      drainage: Drainage.good,
      priorities: [Priority.lessWater],
    );
    final request = buildLiveIntegrationRequest(
      farmer,
      NasaPowerEvidence.parse(raw, farmer, window),
    );
    expect(request['field']['current_crop'], 'sesame');
    expect(request['field']['irrigation_available'], isNull);
    expect(request['soil']['drainage'], 'well');
    expect(request['scenarios'], isEmpty);
    expect(farmer.toJson()['recent_rotation'], ['rice']);
  });

  test(
    'decoder preserves Rust scenario order and nullable crop identities',
    () {
      final output = jsonDecode(
        File('test/fixtures/engine_success_envelope.json').readAsStringSync(),
      );
      final scenarios = output['data']['rotations']['scenarios'] as List;
      final baseline = scenarios.firstWhere(
        (s) => s['scenario']['is_baseline'] == true,
      );
      scenarios.remove(baseline);
      scenarios.add(baseline);
      scenarios[0]['scenario']['steps'][0]['crop_id'] = null;
      final analysis = fieldAnalysisFromEnvelope(jsonEncode(output));
      expect(analysis.scenarios.last.isBaseline, true);
      expect(analysis.scenarios.first.steps.first.cropId, isNull);
      expect(Crops.label(null), 'Unknown crop');
    },
  );

  test('real modeled climate never removes synthetic crop label', () {
    final output = jsonDecode(
      File('test/fixtures/engine_success_envelope.json').readAsStringSync(),
    );
    output['data']['data_mode'] = 'supplied_data';
    output['data']['environment']['seasonal']['metadata']['data_kind'] =
        'modeled';
    final analysis = fieldAnalysisFromEnvelope(jsonEncode(output));
    expect(analysis.climateSummary.dataKind, 'modeled');
    expect(analysis.dataQuality.syntheticCropReferences, true);
    expect(analysis.dataQuality.isDemo, true);
  });
}
