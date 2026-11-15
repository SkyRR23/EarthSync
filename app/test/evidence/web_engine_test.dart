import 'dart:convert';
import 'dart:io';

import 'package:earthsync/evidence/data/engine/rust_engine.dart';
import 'package:earthsync/evidence/data/engine/web_engine.dart';
import 'package:earthsync/evidence/data/environment/nasa_power_client.dart';
import 'package:earthsync/evidence/data/models/farmer_input.dart';
import 'package:earthsync/evidence/data/models/field_analysis.dart';
import 'package:earthsync/evidence/design/theme.dart';
import 'package:earthsync/evidence/features/results/results_screen.dart';
import 'package:earthsync/evidence/src/rust/api/bridge.dart' as rust;
import 'package:earthsync/evidence/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const rice = FarmerInput(
  latitude: 16.85,
  longitude: 96.15,
  currentCrop: 'rice',
  drainage: Drainage.good,
  irrigation: Irrigation.partial,
);

class _LiveHttp extends HttpOverrides {}

class _ReadyAnalysis extends AnalysisNotifier {
  _ReadyAnalysis(this.result);
  final FieldAnalysis result;
  @override
  AnalysisState build() => AnalysisReady(result);
}

void main() {
  late FieldAnalysis result, noCrop;
  FieldAnalysis? liveResult;
  final captured = File(
    'assets/fixtures/nasa_power_real.json',
  ).readAsStringSync();

  setUpAll(() async {
    await RustEngine.init();
    final client = MockClient((request) async {
      if (request.url.path == '/api/demo/captured-climate') {
        return http.Response(captured, 200);
      }
      expect(request.url.path, '/api/engine/integration');
      expect(request.method, 'POST');
      // Mock only HTTP transport; the result comes from the compiled team engine.
      return http.Response(
        await rust.analyzeIntegrationJson(requestJson: request.body),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final engine = WebEngine(
      window: const HistoricalWindow(),
      baseUri: Uri.parse('http://127.0.0.1:8080/?climate=captured'),
      client: client,
    );
    result = await engine.analyzeField(rice);
    noCrop = await engine.analyzeField(
      const FarmerInput(latitude: 16.85, longitude: 96.15),
    );
    if (const bool.fromEnvironment('RUN_WEB_DEMO')) {
      liveResult = await HttpOverrides.runWithHttpOverrides(
        () => WebEngine(
          window: const HistoricalWindow(
            startYear: 2025,
            startMonth: 1,
            endYear: 2025,
            endMonth: 12,
          ),
          baseUri: Uri.parse(
            const String.fromEnvironment(
              'WEB_DEMO_URL',
              defaultValue: 'http://127.0.0.1:8080/',
            ),
          ),
        ).analyzeField(rice),
        _LiveHttp(),
      );
    }
  });

  test(
    'web reference options use actual Rust and cannot become verified advice',
    () {
      expect(result.climateSummary.totalRainMm, 0.04);
      expect(result.scenarios, hasLength(3));
      expect(
        result.scenarios.every((s) => s.eligibility == Feasibility.unknown),
        true,
      );
      expect(result.dataQuality.isDemo, false);
      final request = jsonDecode(result.trace!.rustRequestJson);
      expect(
        request['crop_references']['sources'].single['status'],
        'reference_only',
      );
      expect(request['scenarios'][1]['steps'][1]['growing_window'], isNull);
      expect(result.trace!.retrievalMode, 'captured_real_response');
      expect(noCrop.scenarios, isEmpty);
      expect(noCrop.climateSummary.totalRainMm, 0.04);
    },
  );

  test('live failure never requests captured data or invokes Rust', () async {
    final paths = <String>[];
    final engine = WebEngine(
      window: const HistoricalWindow(),
      baseUri: Uri.parse('http://127.0.0.1:8080/'),
      client: MockClient((request) async {
        paths.add(request.url.path);
        return http.Response('NASA unavailable', 503);
      }),
    );
    await expectLater(engine.analyzeField(rice), throwsA(isA<EngineError>()));
    expect(paths, ['/api/v1/environment/season']);
  });

  Future<void> mount(WidgetTester tester, FieldAnalysis a) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [analysisProvider.overrideWith(() => _ReadyAnalysis(a))],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: fsTheme(), home: const ResultsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'phone results show Rust values, crop options and monthly coverage',
    (tester) async {
      await mount(tester, result);
      expect(find.text('Rainfall total: 0.04 mm'), findsOneWidget);
      expect(find.text('Mean temperature: 28.04 °C'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('Captured NASA POWER'),
        150,
      );
      expect(find.textContaining('Captured NASA POWER'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Rotations').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Rice → Mung bean · reference option'),
        200,
      );
      expect(find.text('Rice → Mung bean · reference option'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Climate').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('29 expected days'),
        200,
      );
      expect(
        find.textContaining('missing rain: 0, temperature: 0'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'no crop shows climate and an actionable empty recommendation state',
    (tester) async {
      await mount(tester, noCrop);
      expect(find.text('Rainfall total: 0.04 mm'), findsOneWidget);
      await tester.tap(find.text('Rotations').last);
      await tester.pumpAndSettle();
      expect(
        find.text('No crop recommendation is available for this field yet.'),
        findsOneWidget,
      );
      expect(find.text('Evidence still needed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'live web HTTP to Python to Rust returns and displays twelve months',
    (tester) async {
      final a = liveResult!;
      expect(a.trace!.retrievalMode, 'live_http');
      expect(a.climateSummary.months, hasLength(12));
      expect(a.climateSummary.totalRainMm, isNotNull);
      expect(a.scenarios, hasLength(3));
      await mount(tester, a);
      expect(
        find.text(
          'Rainfall total: ${a.climateSummary.totalRainMm!.toStringAsFixed(2)} mm',
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.textContaining('Live NASA POWER'),
        150,
      );
      expect(
        find.text('Live NASA POWER · modeled historical data'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    skip: !const bool.fromEnvironment('RUN_WEB_DEMO'),
  );
}
