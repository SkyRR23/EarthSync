import 'dart:convert';
import 'package:earthsync/data/environment/platform_climate.dart';
import 'package:earthsync/data/models/home_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'local-only adapter rejects hosted endpoints before making requests',
    () {
      expect(
        () => PlatformClimateClient(
          http.Client(),
          baseUri: Uri.parse('https://example.com'),
        ),
        throwsArgumentError,
      );
    },
  );
  test(
    '202 climate jobs use reviewed daily contract without ownership fields',
    () async {
      final client = PlatformClimateClient(
        MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/platform/v1/climate/jobs');
          final body = jsonDecode(request.body) as Map;
          expect(body.keys, ['query']);
          expect(body['query']['contract_version'], 'power-daily-merra2.v1');
          expect(body['query']['lineage'], 'MERRA2');
          expect(body['query']['point'], {
            'latitude': -1.29,
            'longitude': 36.82,
          });
          return http.Response(
            jsonEncode({
              'id': 'test-job',
              'kind': 'climate',
              'status': 'queued',
              'result': null,
              'error': null,
              'retryable': false,
            }),
            202,
          );
        }),
        baseUri: Uri.parse('http://127.0.0.1:8021'),
      );
      final job = await client.submit(
        point: GeoPoint(-1.29, 36.82),
        start: DateTime(2024, 2, 1),
        end: DateTime(2024, 2, 29),
      );
      expect(job.pending, true);
      expect(job.records, isEmpty);
      await expectLater(
        client.submit(
          point: GeoPoint(0, 0),
          start: DateTime(2023, 1, 1),
          end: DateTime(2024, 2, 1),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'source failures stay typed and never become synthetic success',
    () async {
      final client = PlatformClimateClient(
        MockClient(
          (_) async => http.Response(
            '{"error":{"code":"ORIGIN_FORBIDDEN","retryable":false}}',
            403,
          ),
        ),
        baseUri: Uri.parse('http://localhost:8021'),
      );
      await expectLater(
        client.refresh('test-job'),
        throwsA(
          isA<PlatformFailure>().having(
            (e) => e.code,
            'code',
            'ORIGIN_FORBIDDEN',
          ),
        ),
      );
    },
  );
  test(
    'daily measurement preserves unknown values, source units and reason',
    () {
      final reading = DailyMeasurement.fromJson({
        'variable': 'T2M_MAX',
        'date': '2024-02-01',
        'value': null,
        'unit': 'deg_c',
        'original_value': null,
        'original_unit': 'C',
        'quality': 'missing',
        'missing_reason': 'Provider fill value',
      });
      expect(reading.value, null);
      expect(reading.originalValue, null);
      expect(reading.missingReason, 'Provider fill value');
      expect(reading.originalUnit, 'C');
      expect(
        () => DailyEvidence.fromJson({'schema_version': 'monthly'}),
        throwsFormatException,
      );
    },
  );
}
