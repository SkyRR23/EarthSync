import 'dart:convert';
import 'dart:io';

import 'package:earthsync/data/cache/last_result.dart';
import 'package:earthsync/data/engine/engine_envelope.dart';
import 'package:earthsync/data/engine/engine_gateway.dart';
import 'package:earthsync/data/models/farmer_input.dart';
import 'package:earthsync/data/models/field_analysis.dart';
import 'package:earthsync/data/models/integration_trace.dart';
import 'package:earthsync/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A real-shaped (non-demo) result with a trace, like the live NASA path.
FieldAnalysis _liveResult() {
  final env =
      jsonDecode(
            File(
              'test/fixtures/engine_success_envelope.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  // Make the shared fixture look like a live, non-synthetic result.
  final data = env['data'] as Map<String, dynamic>;
  data['data_mode'] = 'supplied_data';
  (data['rotations'] as Map<String, dynamic>)['contains_synthetic_references'] =
      false;
  void real(Object? o) {
    if (o is Map<String, dynamic>) {
      if (o['data_kind'] == 'hypothetical') o['data_kind'] = 'modeled';
      o.values.forEach(real);
    } else if (o is List) {
      o.forEach(real);
    }
  }

  real(data);
  final out = jsonEncode(env);
  final trace = IntegrationTrace(
    backendResponseJson: File(
      'assets/fixtures/nasa_power_real.json',
    ).readAsStringSync(),
    farmerInputJson: '{}',
    rustRequestJson: '{}',
    rustResultJson: out,
    retrievalMode: 'live_http',
  );
  return fieldAnalysisFromEnvelope(out, trace: trace);
}

/// Engine that is offline (or returns a fixed result).
class _FakeEngine implements EngineGateway {
  _FakeEngine({this.result});
  final FieldAnalysis? result;
  int calls = 0;

  @override
  Future<FieldAnalysis> analyzeField(FarmerInput input) async {
    calls++;
    if (result != null) return result!;
    throw const EngineError(
      code: 'backend_unreachable',
      message: 'No internet',
      retryable: true,
    );
  }

  @override
  Future<String> engineVersion() async => 'fake';
}

const _draft = FarmerDraft(
  latitude: 16.85,
  longitude: 96.15,
  currentCrop: 'rice',
  irrigation: Irrigation.none,
  drainage: Drainage.poor,
);

Future<ProviderContainer> _container({
  required SharedPreferences prefs,
  required _FakeEngine engine,
}) async => ProviderContainer(
  overrides: [
    prefsProvider.overrideWithValue(prefs),
    engineProvider.overrideWithValue(engine),
  ],
);

void main() {
  late FieldAnalysis live;

  setUp(() async {
    live = _liveResult();
    SharedPreferences.setMockInitialValues({
      'farmer_draft_v1': jsonEncode(_draft.toJson()),
    });
  });

  test('a live result is saved and comes back the same', () async {
    final prefs = await SharedPreferences.getInstance();
    expect(live.dataQuality.isDemo, isFalse);
    final at = saveLastResult(
      prefs,
      live,
      _draft.toInput(),
      now: DateTime.utc(2026, 11, 14, 9),
    );
    expect(at, DateTime.utc(2026, 11, 14, 9));

    final saved = loadLastResult(prefs)!;
    expect(saved.matches(_draft.toInput()), isTrue);
    final back = saved.restore()!;
    expect(back.climateSummary.totalRainMm, live.climateSummary.totalRainMm);
    expect(back.scenarios.length, live.scenarios.length);
    expect(back.trace!.retrievalMode, 'live_http');
  });

  test('demo results are never saved', () async {
    final prefs = await SharedPreferences.getInstance();
    final demo = fieldAnalysisFromEnvelope(
      File('test/fixtures/engine_success_envelope.json').readAsStringSync(),
    );
    expect(demo.dataQuality.isDemo, isTrue);
    expect(saveLastResult(prefs, demo, _draft.toInput()), isNull);
    expect(loadLastResult(prefs), isNull);
  });

  test(
    'opening the app offline shows the saved result with a no-internet flag',
    () async {
      final prefs = await SharedPreferences.getInstance();
      saveLastResult(prefs, live, _draft.toInput());
      final engine = _FakeEngine();
      final c = await _container(prefs: prefs, engine: engine);
      addTearDown(c.dispose);

      final first = c.read(analysisProvider);
      expect(first, isA<AnalysisReady>());
      expect((first as AnalysisReady).fromCache, isTrue);

      c.read(analysisProvider.notifier).ensureFor(c.read(farmerDraftProvider));
      expect((c.read(analysisProvider) as AnalysisReady).refreshing, isTrue);
      await Future<void>.delayed(Duration.zero);

      final after = c.read(analysisProvider) as AnalysisReady;
      expect(engine.calls, 1);
      expect(after.refreshFailed, isTrue);
      expect(
        after.analysis.climateSummary.totalRainMm,
        live.climateSummary.totalRainMm,
      );
    },
  );

  test('a saved result is not reused for different answers', () async {
    final prefs = await SharedPreferences.getInstance();
    saveLastResult(prefs, live, _draft.toInput());
    final c = await _container(prefs: prefs, engine: _FakeEngine());
    addTearDown(c.dispose);

    final changed = FarmerDraft(
      latitude: _draft.latitude,
      longitude: _draft.longitude,
      currentCrop: 'maize',
      irrigation: _draft.irrigation,
      drainage: _draft.drainage,
    );
    await c.read(analysisProvider.notifier).run(changed.toInput());
    final s = c.read(analysisProvider);
    expect(s, isA<AnalysisFailed>());
    expect(
      (s as AnalysisFailed).lastGood,
      isNotNull,
    ); // still offered, by choice
  });

  test('a fresh online check replaces and re-saves the result', () async {
    final prefs = await SharedPreferences.getInstance();
    final c = await _container(
      prefs: prefs,
      engine: _FakeEngine(result: live),
    );
    addTearDown(c.dispose);

    await c.read(analysisProvider.notifier).run(_draft.toInput());
    final s = c.read(analysisProvider) as AnalysisReady;
    expect(s.fromCache, isFalse);
    expect(loadLastResult(prefs), isNotNull);
  });

  test('start over forgets the saved result', () async {
    final prefs = await SharedPreferences.getInstance();
    saveLastResult(prefs, live, _draft.toInput());
    final c = await _container(prefs: prefs, engine: _FakeEngine());
    addTearDown(c.dispose);

    c.read(analysisProvider.notifier).forget();
    expect(loadLastResult(prefs), isNull);
    expect(c.read(analysisProvider), isA<AnalysisIdle>());
  });
}
