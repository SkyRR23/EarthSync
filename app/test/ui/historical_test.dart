import 'dart:async';
import 'dart:convert';
import 'package:earthsync/data/farm_journal.dart';
import 'package:earthsync/data/models/home_profile.dart';
import 'package:earthsync/data/platform_farms.dart';
import 'package:earthsync/data/platform_transport.dart';
import 'package:earthsync/features/historical/historical_client.dart';
import 'package:earthsync/features/historical/historical_results.dart';
import 'package:earthsync/features/historical/historical_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'leap-day replay slider selects a real day, keyboard accessible',
    (tester) async {
      var selected = DateTime.utc(2024, 2, 1);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => HistoricalReplayControls(
                start: DateTime.utc(2024, 2, 1),
                end: DateTime.utc(2024, 2, 29),
                selected: selected,
                onChanged: (v) => setState(() => selected = v),
              ),
            ),
          ),
        ),
      );
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.divisions, 28);
      slider.onChanged!(28);
      await tester.pump();
      expect(find.textContaining('2024-02-29'), findsOneWidget);
      expect(slider.semanticFormatterCallback!(28), '2024-02-29');
      await tester.tap(find.text('Choose historical day'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
    },
  );
  testWidgets('partial ET0 explicitly keeps missing days, mobile and desktop', (
    tester,
  ) async {
    final summary = {
      'start': '2024-02-01',
      'end': '2024-02-29',
      'metrics': {
        'et0': {
          'value': 70.0,
          'unit': 'mm',
          'valid_days': 28,
          'missing_days': 1,
          'expected_days': 29,
          'status': 'partial',
        },
      },
    };
    for (final width in [390.0, 1300.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HistoricalMetrics(summary: summary),
            ),
          ),
        ),
      );
      expect(find.text('28/29 valid days · 1 missing'), findsOneWidget);
      expect(
        find.text('Accepted-day subtotal / statistic only'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  test('changing selection cancels a pending result and server job', () async {
    final submitted = Completer<http.Response>();
    final paths = <String>[];
    final platform = PlatformFarmClient(
      PlatformTransport(
        MockClient((request) async {
          paths.add('${request.method} ${request.url.path}');
          if (request.method == 'POST') return submitted.future;
          return http.Response(jsonEncode({'status': 'cancelled'}), 200);
        }),
        baseUri: Uri.parse('http://127.0.0.1:8771'),
      ),
    );
    final client = HistoricalClient(platform);
    final pending = client.run('historical', {'start': '2024-01-01'});
    await Future<void>.delayed(Duration.zero);
    client.cancel();
    submitted.complete(
      http.Response(jsonEncode({'id': 'stale-job', 'status': 'queued'}), 202),
    );
    expect(await pending, isNull);
    await Future<void>.delayed(Duration.zero);
    expect(paths, contains('DELETE /api/platform/v1/jobs/stale-job'));
    client.dispose();
  });
  test(
    'offline cache is origin and confirmed revision scoped; no writes replay',
    () async {
      SharedPreferences.setMockInitialValues({});
      final methods = <String>[];
      final client = PlatformFarmClient(
        PlatformTransport(
          MockClient((request) async {
            methods.add(request.method);
            throw Exception('offline');
          }),
          baseUri: Uri.parse('http://127.0.0.1:8771'),
        ),
      );
      final farm = ConfirmedFarm(
        id: 'fixture',
        point: GeoPoint(19.8, 96.27),
        confirmedAt: DateTime.utc(2026, 11, 14),
      );
      final cache = FarmJournalCache();
      await cache.save(historicalCacheKey(farm, client), {
        'farm_id': 'linked-fixture',
        'revision': farmRevision(farm),
        'windows': [],
        'simulations': [],
      });
      expect((await loadHistorical(farm, client, cache))!.cached, isTrue);
      expect(methods, everyElement('GET'));
      final revised = ConfirmedFarm(
        id: farm.id,
        point: farm.point,
        confirmedAt: DateTime.utc(2026, 11, 15),
      );
      expect(
        () => loadHistorical(revised, client, cache),
        throwsA(isA<PlatformFailure>()),
      );
    },
  );
  testWidgets('core Burmese controls fall back to English for source text', (
    tester,
  ) async {
    late String translated, fallback;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('my'),
        supportedLocales: const [Locale('en'), Locale('my')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(
          builder: (context) {
            translated = historicalText(context, 'Historical replay');
            fallback = historicalText(context, 'NASA POWER');
            return const SizedBox();
          },
        ),
      ),
    );
    expect(translated, 'အတိတ်ကာလ ပြန်လည်ကြည့်ရှုရန်');
    expect(fallback, 'NASA POWER');
  });
}
