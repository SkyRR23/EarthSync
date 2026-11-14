import 'dart:convert';
import 'dart:io';

import 'package:earthsync/data/engine/live_integration.dart';
import 'package:earthsync/data/engine/rust_engine.dart';
import 'package:earthsync/data/environment/nasa_power_client.dart';
import 'package:earthsync/data/models/farmer_input.dart';
import 'package:earthsync/data/models/field_analysis.dart';
import 'package:earthsync/features/home/weather_tab.dart';
import 'package:earthsync/features/results/climate_provenance.dart';
import 'package:earthsync/src/rust/api/bridge.dart' as rust;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WeatherTab(analysis: a)),
        ),
      );
      await tester.pumpAndSettle();
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
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WeatherTab(analysis: a)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Precipitation: unknown'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WeatherTab(analysis: a)),
        ),
      );
      await tester.pumpAndSettle();
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
