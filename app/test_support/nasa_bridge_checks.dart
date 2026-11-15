import 'dart:convert';
import 'dart:io';

import 'package:earthsync/data/engine/live_integration.dart';
import 'package:earthsync/data/engine/rust_engine.dart';
import 'package:earthsync/data/environment/nasa_power_client.dart';
import 'package:earthsync/data/models/farmer_input.dart';
import 'package:earthsync/data/models/field_analysis.dart';
import 'package:earthsync/design/theme.dart';
import 'package:earthsync/features/home/climate_history.dart';
import 'package:earthsync/features/results/climate_provenance.dart';
import 'package:earthsync/src/rust/api/bridge.dart' as rust;
import 'package:earthsync/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _point = FarmerInput(
  latitude: 16.85,
  longitude: 96.15,
  recentRotation: ['rice'],
  plantingMonth: 6,
  drainage: Drainage.good,
  priorities: [Priority.lessWater],
);
const _window = HistoricalWindow();

// Only explicit opt-in network tests use real HTTP; keep normal tests offline.
class _LiveHttp extends HttpOverrides {}

/// The app's Weather tab as the farmer sees it, with the phone storage the
/// app always has (the tab's saved-result banner reads it). Host tests
/// install mock storage first; device tests use the real one.
Future<void> _pumpWeather(WidgetTester tester, FieldAnalysis a) async {
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        theme: fsLightTheme(),
        home: ClimateHistoryPage(analysis: a),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void registerNasaBridgeChecks() {
  late String originalCapture;
  late FieldAnalysis capturedResult, missingResult;
  FieldAnalysis? liveResult;

  Future<FieldAnalysis> captured({bool missing = false}) async {
    var raw = await rootBundle.loadString(
      'assets/fixtures/nasa_power_real.json',
    );
    if (missing) {
      final e = jsonDecode(raw);
      e['environment']['seasonal']['observations'] = [];
      raw = jsonEncode(e);
    }
    return analyzeNasaEvidence(
      input: _point,
      window: _window,
      evidence: NasaPowerEvidence.parse(raw, _point, _window),
      analyzeIntegration: (request) =>
          rust.analyzeIntegrationJson(requestJson: request),
      retrievalMode: 'captured_real_response',
    );
  }

  setUpAll(() async {
    debugPrint('Initializing the actual native Rust bridge.');
    await RustEngine.init().timeout(const Duration(seconds: 30));
    debugPrint(
      'Native bridge initialized; analyzing the captured NASA response.',
    );
    originalCapture = await rootBundle.loadString(
      'assets/fixtures/nasa_power_real.json',
    );
    capturedResult = await captured().timeout(const Duration(seconds: 30));
    missingResult = await captured(
      missing: true,
    ).timeout(const Duration(seconds: 30));
    if (const bool.fromEnvironment('RUN_LIVE_NASA')) {
      liveResult = await HttpOverrides.runWithHttpOverrides(
        () => RustEngine().analyzeField(_point),
        _LiveHttp(),
      );
    }
  });

  testWidgets(
    'captured real NASA -> actual FRB -> Rust -> Flutter climate display',
    (tester) async {
      final a = capturedResult;
      expect(a.climateSummary.totalRainMm, 0.04);
      expect(a.climateSummary.meanTempC, closeTo(28.03655172413793, 1e-12));
      expect(a.location.latitude, _point.latitude);
      expect(a.location.longitude, _point.longitude);
      expect(a.scenarios, isEmpty);
      expect(a.dataQuality.isDemo, false);
      final trace = a.trace!;
      expect(trace.backendResponseJson, originalCapture);
      expect(jsonDecode(trace.farmerInputJson)['recent_rotation'], ['rice']);
      expect(jsonDecode(trace.farmerInputJson)['planting_month'], 6);
      expect(jsonDecode(trace.farmerInputJson)['priorities'], ['less_water']);
      expect(jsonDecode(trace.rustRequestJson)['field']['current_crop'], '');
      expect(jsonDecode(trace.rustResultJson)['status'], 'success');
      await _pumpWeather(tester, a);
      expect(find.textContaining('0.04 mm'), findsWidgets);
      expect(find.textContaining('28.0366'), findsOneWidget);
      expect(
        find.text('Captured real NASA POWER climate · offline replay'),
        findsOneWidget,
      );
      expect(find.textContaining('Crop suitability: unknown'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing historical months return unknown values and render safely',
    (tester) async {
      final a = missingResult;
      expect(a.climateSummary.totalRainMm, isNull);
      expect(a.climateSummary.meanTempC, isNull);
      expect(a.climateSummary.months, hasLength(1));
      expect(a.climateSummary.months.single.rainMm, isNull);
      expect(a.dataGaps.any((g) => g.field.startsWith('rain_mm')), true);
      await _pumpWeather(tester, a);
      expect(find.textContaining('Precipitation: unknown'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('engine FAO-56 ET0 on a real NASA week, through actual FRB', () async {
    // NASA POWER daily values for Yangon, 5-11 Nov 2026 (11 Nov: sunlight
    // not published yet). Same fields the backend sends as et0_request.
    Map<String, dynamic> day(int d, double? solar, List<double> v) => {
      'date': {'year': 2026, 'month': 11, 'day': d},
      'tmin_c': v[0],
      'tmax_c': v[1],
      'dewpoint_c': v[2],
      'wind_2m_m_s': v[3],
      'pressure_kpa': v[4],
      'solar_mj_m2_day': solar,
      'rainfall_mm': v[5],
    };
    final request = {
      'method': 'fao56-daily-pm.v1',
      'latitude': 16.85,
      'elevation_m': 10.91,
      'day_basis': 'NASA_POWER_LST',
      'days': [
        day(5, 14.95, [24.94, 33.13, 24.72, 0.8, 101.03, 4.95]),
        day(6, 4.8, [25.96, 31.8, 24.78, 0.7, 101.0, 7.76]),
        day(7, 13.38, [25.3, 29.38, 24.73, 1.63, 101.03, 14.79]),
        day(8, 17.67, [24.68, 28.4, 24.37, 1.42, 101.15, 10.43]),
        day(9, 19.41, [24.04, 30.16, 24.23, 1.74, 101.24, 2.2]),
        day(10, 11.35, [23.32, 25.88, 22.53, 2.13, 101.28, 1.49]),
        day(11, null, [21.16, 23.27, 20.69, 2.9, 101.29, 16.35]),
      ],
    };
    final out = jsonDecode(
      await rust.referenceEt0Json(requestJson: jsonEncode(request)),
    );
    expect(out['status'], 'success');
    final d = out['data'];
    expect(d['expected_days'], 7);
    // Withheld, never guessed: 11 Nov has no sunlight value yet, and the very
    // cloudy 6 Nov is outside the FAO-56 radiation method's supported range.
    expect(d['et0_usable_days'], 5);
    expect(d['et0_total_mm'], isNull);
    expect(d['days'][6]['et0_mm'], isNull);
    expect(
      d['days'][1]['missing_reason'],
      'RADIATION_METHOD_OUTSIDE_SUPPORTED_DOMAIN',
    );
    final partial = (d['et0_partial_sum_mm'] as num).toDouble();
    expect(partial, closeTo(15.88, 0.01)); // 2.4-3.9 mm/day
    expect(d['rainfall_total_mm'], closeTo(57.97, 1e-9));
  });

  test(
    'Rust rejects mismatched field/environment coordinates through actual FRB',
    () async {
      final a = capturedResult;
      final request = jsonDecode(a.trace!.rustRequestJson);
      request['field']['latitude'] = 16.86;
      final result = jsonDecode(
        await rust.analyzeIntegrationJson(requestJson: jsonEncode(request)),
      );
      expect(result['status'], 'error');
      expect(result['error']['code'], 'LOCATION_MISMATCH');
    },
  );

  testWidgets(
    'live Python -> NASA -> actual FRB -> Rust -> Flutter',
    (tester) async {
      final a = liveResult!;
      expect(a.trace!.retrievalMode, 'live_http');
      expect(a.climateSummary.dataKind, 'modeled');
      expect(a.climateSummary.totalRainMm, closeTo(0.04, 1e-9));
      expect(a.climateSummary.meanTempC, closeTo(28.03655172413793, 1e-9));
      expect(a.scenarios, isEmpty);
      await _pumpWeather(tester, a);
      expect(
        find.text('Real NASA POWER climate · modeled data'),
        findsOneWidget,
      );
      expect(find.textContaining('28.0366'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    skip: !const bool.fromEnvironment('RUN_LIVE_NASA'),
  );

  testWidgets('synthetic crop warning stays visible with modeled climate', (
    tester,
  ) async {
    const analysis = FieldAnalysis(
      location: FieldLocation(latitude: 16.85, longitude: 96.15),
      climateSummary: ClimateSummary(
        months: [],
        period: 'Feb 2024',
        sourceId: 'nasa',
        dataKind: 'modeled',
      ),
      scenarios: [],
      alerts: [],
      assumptions: [],
      dataGaps: [],
      references: [],
      dataQuality: DataQuality(syntheticCropReferences: true),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ClimateProvenance(analysis: analysis)),
      ),
    );
    expect(find.textContaining('Synthetic crop profiles'), findsOneWidget);
    expect(find.text('Climate: modeled'), findsOneWidget);
  });
}
