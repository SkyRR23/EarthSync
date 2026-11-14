import 'package:earthsync/data/environment/platform_climate.dart';
import 'package:earthsync/data/models/home_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test(
    'actual local 7I job retains live daily evidence and quality',
    () async {
      final httpClient = http.Client();
      addTearDown(httpClient.close);
      final client = PlatformClimateClient(
        httpClient,
        baseUri: Uri.parse('http://127.0.0.1:8021'),
      );
      var job = await client.submit(
        point: GeoPoint(42.03, -93.62),
        start: DateTime(2024, 2, 1),
        end: DateTime(2024, 2, 29),
      );
      for (var i = 0; job.pending && i < 40; i++) {
        await Future<void>.delayed(const Duration(seconds: 3));
        job = await client.refresh(job.id);
      }
      expect(job.status, ClimateJobStatus.succeeded);
      expect(job.gaps, isEmpty);
      expect(job.records, hasLength(3));
      for (final evidence in job.records) {
        expect(evidence.provider, 'NASA POWER');
        expect(evidence.raw['data_type'], 'modeled');
        expect(evidence.measurements, hasLength(29));
        expect(
          evidence.raw['source_metadata']['policy'],
          'power-daily-merra2.v1',
        );
        expect(evidence.sourceUrl, startsWith('https://power.larc.nasa.gov/'));
      }
    },
    skip: !const bool.fromEnvironment('RUN_LIVE_PLATFORM'),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
