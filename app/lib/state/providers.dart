import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/engine/engine_gateway.dart';
import '../data/engine/mock_engine.dart';
import '../data/engine/rust_engine.dart';
import '../data/models/farmer_input.dart';
import '../data/models/field_analysis.dart';
import '../data/models/field_note.dart';

const _engineDefine = String.fromEnvironment('ENGINE');

/// `rust` (team engine via bridge) on phones by default; `mock` on web,
/// where the Rust bridge is not built. Override with --dart-define=ENGINE=...
final kEngine = _engineDefine.isNotEmpty
    ? _engineDefine
    : (kIsWeb ? 'mock' : 'rust');

final engineProvider = Provider<EngineGateway>(
  (ref) => kEngine == 'rust' ? RustEngine() : MockEngine(),
);

/// Device storage. Overridden in main(); null in tests = memory only.
/// Farmer answers and notes never leave the phone (master plan §13).
final prefsProvider = Provider<SharedPreferences?>((ref) => null);

// ---------------------------------------------------------------------------
// The farmer's field and answers (saved on the phone)
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

  /// Setup is complete once the field and the three questions are answered.
  bool get isComplete =>
      hasLocation &&
      currentCrop != null &&
      irrigation != null &&
      drainage != null;

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

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'current_crop': currentCrop,
    'previous_crop': previousCrop,
    'planting_month': plantingMonth,
    'irrigation': irrigation?.name,
    'drainage': drainage?.name,
    'priorities': priorities?.map((p) => p.name).toList(),
  };

  factory FarmerDraft.fromJson(Map<String, dynamic> j) {
    T? e<T extends Enum>(List<T> values, Object? raw) =>
        values.where((v) => v.name == raw).firstOrNull;
    final pr = j['priorities'] as List<dynamic>?;
    return FarmerDraft(
      latitude: (j['latitude'] as num?)?.toDouble(),
      longitude: (j['longitude'] as num?)?.toDouble(),
      currentCrop: j['current_crop'] as String?,
      previousCrop: j['previous_crop'] as String?,
      plantingMonth: j['planting_month'] as int?,
      irrigation: e(Irrigation.values, j['irrigation']),
      drainage: e(Drainage.values, j['drainage']),
      priorities: pr == null
          ? null
          : {for (final p in pr) ?e(Priority.values, p)},
    );
  }
}

const _draftKey = 'farmer_draft_v1';

FarmerDraft loadSavedDraft(SharedPreferences? prefs) {
  final raw = prefs?.getString(_draftKey);
  if (raw == null) return const FarmerDraft();
  try {
    return FarmerDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    return const FarmerDraft();
  }
}

class FarmerDraftNotifier extends Notifier<FarmerDraft> {
  @override
  FarmerDraft build() => loadSavedDraft(ref.read(prefsProvider));

  void _set(FarmerDraft d) {
    state = d;
    ref.read(prefsProvider)?.setString(_draftKey, jsonEncode(d.toJson()));
  }

  void setLocation(double lat, double lon) =>
      _set(state.copyWith(latitude: lat, longitude: lon));
  void setCurrentCrop(String v) => _set(state.copyWith(currentCrop: v));
  void setPreviousCrop(String v) => _set(state.copyWith(previousCrop: v));
  void setPlantingMonth(int v) => _set(state.copyWith(plantingMonth: v));
  void setIrrigation(Irrigation v) => _set(state.copyWith(irrigation: v));
  void setDrainage(Drainage v) => _set(state.copyWith(drainage: v));
  void setPriorities(Set<Priority> v) => _set(state.copyWith(priorities: v));

  /// Back to "not answered" (e.g. user unticked every priority).
  void clearPriorities() => _set(
    FarmerDraft(
      latitude: state.latitude,
      longitude: state.longitude,
      currentCrop: state.currentCrop,
      previousCrop: state.previousCrop,
      plantingMonth: state.plantingMonth,
      irrigation: state.irrigation,
      drainage: state.drainage,
    ),
  );

  /// Forget the field and answers (notes are kept).
  void reset() {
    state = const FarmerDraft();
    ref.read(prefsProvider)?.remove(_draftKey);
  }
}

final farmerDraftProvider = NotifierProvider<FarmerDraftNotifier, FarmerDraft>(
  FarmerDraftNotifier.new,
);

// ---------------------------------------------------------------------------
// Field notes (OpenFarm "scouting" idea) — stored on the phone only
// ---------------------------------------------------------------------------

const _notesKey = 'field_notes_v1';

class NotesNotifier extends Notifier<List<FieldNote>> {
  @override
  List<FieldNote> build() {
    final raw = ref.read(prefsProvider)?.getString(_notesKey);
    if (raw == null) return const [];
    try {
      return [
        for (final j in jsonDecode(raw) as List<dynamic>)
          FieldNote.fromJson(j as Map<String, dynamic>),
      ];
    } catch (_) {
      return const [];
    }
  }

  void _save(List<FieldNote> notes) {
    state = notes;
    ref
        .read(prefsProvider)
        ?.setString(_notesKey, jsonEncode([for (final n in notes) n.toJson()]));
  }

  void add(NoteKind kind, String text) {
    final now = DateTime.now();
    _save([
      FieldNote(
        id: now.microsecondsSinceEpoch.toString(),
        createdAt: now,
        kind: kind,
        text: text.trim(),
      ),
      ...state,
    ]);
  }

  void remove(String id) => _save([
    for (final n in state)
      if (n.id != id) n,
  ]);

  /// Undo for a just-removed note.
  void restore(FieldNote note) {
    final next = [...state, note]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _save(next);
  }
}

final notesProvider = NotifierProvider<NotesNotifier, List<FieldNote>>(
  NotesNotifier.new,
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

  @override
  AnalysisState build() => const AnalysisIdle();

  Future<void> run(FarmerInput input) async {
    state = const AnalysisRunning();
    try {
      final result = await ref.read(engineProvider).analyzeField(input);
      _lastGood = result;
      state = AnalysisReady(result);
    } on EngineError catch (e) {
      state = AnalysisFailed(e, lastGood: _lastGood);
    } catch (e) {
      state = AnalysisFailed(
        EngineError(code: 'unexpected', message: e.toString()),
        lastGood: _lastGood,
      );
    }
  }

  /// Run for the saved field if nothing has run yet (app reopened).
  void ensureFor(FarmerDraft draft) {
    if (state is AnalysisIdle && draft.hasLocation) run(draft.toInput());
  }

  /// Fallback for outages: the bundled demo fixture (master plan §12, H28).
  Future<void> runDemo() async {
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
    if (_lastGood != null) state = AnalysisReady(_lastGood!, fromCache: true);
  }
}

final analysisProvider = NotifierProvider<AnalysisNotifier, AnalysisState>(
  AnalysisNotifier.new,
);

/// Sample field near Yangon used by "Use sample field" and the demo fallback.
const kSampleLat = 16.8661;
const kSampleLon = 96.1951;
const _demoInput = FarmerInput(latitude: kSampleLat, longitude: kSampleLon);
