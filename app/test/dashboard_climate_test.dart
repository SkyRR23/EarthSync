import 'dart:convert';
import 'dart:io';
import 'package:earthsync/data/environment/area_climate.dart';
import 'package:earthsync/data/environment/nasa_power_client.dart';
import 'package:earthsync/data/models/farmer_input.dart';
import 'package:earthsync/data/models/home_profile.dart';
import 'package:earthsync/features/dashboard/climate_panel.dart';
import 'package:earthsync/state/dashboard_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final raw = File('assets/fixtures/nasa_power_real.json').readAsStringSync();
  const input = FarmerInput(latitude: 16.85, longitude: 96.15);
  const window = HistoricalWindow();
  final query = ClimateQuery(GeoPoint(16.85, 96.15), window);
  test(
    'monthly context retains complete values and never fills missing data',
    () {
      final json = jsonDecode(raw);
      final row = json['environment']['seasonal']['observations'][0];
      row['rainfall_mm'] = 123;
      row['rainfall_complete'] = false;
      final climate = AreaClimate(
        NasaPowerEvidence.parse(jsonEncode(json), input, window),
        window,
      );
      expect(climate.readings.single.rainMm, null);
      expect(climate.readings.single.temperatureC, closeTo(28.03655, .00001));
      json['environment']['seasonal']['observations'] = [];
      final empty = AreaClimate(
        NasaPowerEvidence.parse(jsonEncode(json), input, window),
        window,
      );
      expect(empty.readings.single.rainMm, null);
      expect(empty.readings.single.temperatureC, null);
    },
  );
  test(
    'API failure is an error, with no synthetic or captured fallback',
    () async {
      var calls = 0;
      final container = ProviderContainer(
        overrides: [
          dashboardClimateClientProvider.overrideWithValue(
            NasaPowerClient(
              client: MockClient((_) async {
                calls++;
                return http.Response('', 503);
              }),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        dashboardClimateProvider(query),
        (_, _) {},
      );
      addTearDown(subscription.close);
      await expectLater(
        container.read(dashboardClimateProvider(query).future),
        throwsA(isA<Exception>()),
      );
      expect(calls, 1);
      expect(container.read(dashboardClimateProvider(query)).hasError, true);
      expect(container.read(dashboardClimateProvider(query)).hasValue, false);
    },
  );
  test('query identity includes the exact point and month window', () {
    expect(query, ClimateQuery(GeoPoint(16.85, 96.15), window));
    expect(query, isNot(ClimateQuery(GeoPoint(17, 96.15), window)));
    expect(
      query,
      isNot(
        ClimateQuery(
          GeoPoint(16.85, 96.15),
          const HistoricalWindow(endMonth: 3),
        ),
      ),
    );
  });
  testWidgets('missing climate renders unknown values and no fake charts', (
    t,
  ) async {
    final json = jsonDecode(raw);
    json['environment']['seasonal']['observations'] = [];
    final climate = AreaClimate(
      NasaPowerEvidence.parse(jsonEncode(json), input, window),
      window,
    );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ClimateReadings(climate: climate)),
        ),
      ),
    );
    expect(find.text('Rainfall unavailable for this period.'), findsOneWidget);
    expect(
      find.text('Temperature unavailable for this period.'),
      findsOneWidget,
    );
    expect(find.textContaining('Unknown mm'), findsOneWidget);
    expect(find.textContaining('Gaps are unknown, not zero.'), findsOneWidget);
  });
  testWidgets('refresh failure labels last-known data for the same query', (
    t,
  ) async {
    var fail = false;
    final client = NasaPowerClient(
      client: MockClient(
        (_) async => http.Response(fail ? '' : raw, fail ? 503 : 200),
      ),
    );
    final container = ProviderContainer(
      overrides: [dashboardClimateClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: ClimatePanel(query: query)),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Monthly readings · accessible table'));
    await t.pumpAndSettle();
    await t.tap(find.text('Monthly readings · accessible table'));
    await t.pumpAndSettle();
    expect(find.textContaining('0.04 mm'), findsOneWidget);
    fail = true;
    container.invalidate(dashboardClimateProvider(query));
    await t.pumpAndSettle();
    expect(
      find.textContaining('Last-known data for this same point'),
      findsOneWidget,
    );
    expect(
      find.textContaining('No example or synthetic climate was substituted.'),
      findsOneWidget,
    );
  });
}
