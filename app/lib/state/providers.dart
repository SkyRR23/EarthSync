import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/environment/nasa_power_client.dart';
import '../data/engine/engine_gateway.dart';
import '../data/engine/mock_engine.dart';
import '../data/engine/rust_engine.dart';
import '../data/models/farmer_input.dart';
import '../data/models/field_analysis.dart';

const _engineDefine = String.fromEnvironment('ENGINE');

/// `rust` (team engine via bridge) on phones by default; `mock` on web,
/// where the Rust bridge is not built. Override with --dart-define=ENGINE=...
final kEngine = _engineDefine.isNotEmpty ? _engineDefine : (kIsWeb ? 'mock' : 'rust');

final engineProvider = Provider<EngineGateway>(
  (ref) => kEngine == 'rust' ? RustEngine(window: ref.watch(historicalWindowProvider)) : MockEngine(),
);

class HistoricalWindowNotifier extends Notifier<HistoricalWindow> {
  @override
  HistoricalWindow build() => const HistoricalWindow();
  void setWindow(HistoricalWindow window) => state = window;
}
final historicalWindowProvider = NotifierProvider<HistoricalWindowNotifier, HistoricalWindow>(HistoricalWindowNotifier.new);

// ---------------------------------------------------------------------------
// Questionnaire draft
// ---------------------------------------------------------------------------

/// Sentinel used by choice questions for "I don't know".
const kUnknown = 'unknown';

/// null field = not answered yet. [kUnknown] / 0 / `.unknown` = "I don't know".
class FarmerDraft {
  const FarmerDraft({
    this.latitude,
    this.longitude,
    this.currentCrop,
    this.previousCrop,
    this.plantingMonth,
    this.irrigation,
    this.drainage,
    this.priorities,
  });

  final double? latitude;
  final double? longitude;
  final String? currentCrop;
  final String? previousCrop;
  final int? plantingMonth; // 0 = unknown
  final Irrigation? irrigation;
  final Drainage? drainage;
  final Set<Priority>? priorities; // empty set = "I don't know"

  bool get hasLocation => latitude != null && longitude != null;

  FarmerDraft copyWith({
    double? latitude,
    double? longitude,
    String? currentCrop,
    String? previousCrop,
    int? plantingMonth,
    Irrigation? irrigation,
    Drainage? drainage,
    Set<Priority>? priorities,
  }) => FarmerDraft(
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    currentCrop: currentCrop ?? this.currentCrop,
    previousCrop: previousCrop ?? this.previousCrop,
    plantingMonth: plantingMonth ?? this.plantingMonth,
    irrigation: irrigation ?? this.irrigation,
    drainage: drainage ?? this.drainage,
    priorities: priorities ?? this.priorities,
  );

  FarmerInput toInput() {
    String? crop(String? v) => (v == null || v == kUnknown) ? null : v;
    return FarmerInput(
      latitude: latitude!,
      longitude: longitude!,
      currentCrop: crop(currentCrop),
      recentRotation: [if (crop(previousCrop) != null) previousCrop!],
      plantingMonth: (plantingMonth == null || plantingMonth == 0)
          ? null
          : plantingMonth,
      irrigation: irrigation ?? Irrigation.unknown,
      drainage: drainage ?? Drainage.unknown,
      priorities: (priorities ?? const {}).toList(),
    );
  }
}

class FarmerDraftNotifier extends Notifier<FarmerDraft> {
  @override
  FarmerDraft build() => const FarmerDraft();

  void setLocation(double lat, double lon) =>
      state = state.copyWith(latitude: lat, longitude: lon);
  void setCurrentCrop(String v) => state = state.copyWith(currentCrop: v);
  void setPreviousCrop(String v) => state = state.copyWith(previousCrop: v);
  void setPlantingMonth(int v) => state = state.copyWith(plantingMonth: v);
  void setIrrigation(Irrigation v) => state = state.copyWith(irrigation: v);
  void setDrainage(Drainage v) => state = state.copyWith(drainage: v);
  void setPriorities(Set<Priority> v) => state = state.copyWith(priorities: v);

  /// Back to "not answered" (e.g. user unticked every priority).
  void clearPriorities() => state = FarmerDraft(
    latitude: state.latitude,
    longitude: state.longitude,
    currentCrop: state.currentCrop,
    previousCrop: state.previousCrop,
    plantingMonth: state.plantingMonth,
    irrigation: state.irrigation,
    drainage: state.drainage,
  );
}

final farmerDraftProvider = NotifierProvider<FarmerDraftNotifier, FarmerDraft>(
  FarmerDraftNotifier.new,
);

// ---------------------------------------------------------------------------
// Analysis state machine: Idle -> Analyzing -> Ready | Failed
// ---------------------------------------------------------------------------

sealed class AnalysisState {
  const AnalysisState();
}

class AnalysisIdle extends AnalysisState {
  const AnalysisIdle();
}

class AnalysisRunning extends AnalysisState {
  const AnalysisRunning();
}

class AnalysisReady extends AnalysisState {
  const AnalysisReady(this.analysis, {this.fromCache = false});
  final FieldAnalysis analysis;
  final bool fromCache;
}

class AnalysisFailed extends AnalysisState {
  const AnalysisFailed(this.error, {this.lastGood});
  final EngineError error;
  final FieldAnalysis? lastGood;
}

class AnalysisNotifier extends Notifier<AnalysisState> {
  FieldAnalysis? _lastGood;
  int _generation = 0;

  @override
  AnalysisState build() => const AnalysisIdle();

  Future<void> run(FarmerInput input) async {
    final generation = ++_generation;
    state = const AnalysisRunning();
    try {
      final result = await ref.read(engineProvider).analyzeField(input);
      if (generation != _generation) return;
      _lastGood = result;
      state = AnalysisReady(result);
    } on EngineError catch (e) {
      if (generation != _generation) return;
      state = AnalysisFailed(e, lastGood: _lastGood);
    } catch (e) {
      if (generation != _generation) return;
      state = AnalysisFailed(
        EngineError(code: 'unexpected', message: e.toString()),
        lastGood: _lastGood,
      );
    }
  }

  /// Fallback for outages: the bundled demo fixture (master plan §12, H28).
  Future<void> runDemo() async {
    ++_generation;
    state = const AnalysisRunning();
    try {
      state = AnalysisReady(
        await MockEngine(delay: Duration.zero).analyzeField(_demoInput),
      );
    } on EngineError catch (e) {
      state = AnalysisFailed(e);
    }
  }

  void showLastGood() {
    ++_generation;
    if (_lastGood != null) state = AnalysisReady(_lastGood!, fromCache: true);
  }
}

final analysisProvider = NotifierProvider<AnalysisNotifier, AnalysisState>(
  AnalysisNotifier.new,
);

/// Sample field near Yangon used by "Use sample field" and the demo fallback.
const kSampleLat = 16.85;
const kSampleLon = 96.15;
const _demoInput = FarmerInput(latitude: kSampleLat, longitude: kSampleLon);
