import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/cloud/cloud_sync.dart';
import '../data/environment/nasa_power_client.dart';
import '../data/engine/engine_gateway.dart';
import '../data/engine/mock_engine.dart';
import '../data/engine/rust_engine.dart';
import '../data/models/farm_boundary.dart';
import '../data/engine/web_engine.dart';
import '../data/models/farmer_input.dart';
import '../data/models/field_analysis.dart';
import '../data/models/field_note.dart';

const _engineDefine = String.fromEnvironment('ENGINE');

/// Native apps use FRB; browsers call the shared Rust engine on the demo host.
/// Fixture presentation requires an explicit ENGINE=mock selection.
final kEngine = _engineDefine.isNotEmpty
    ? _engineDefine
    : (kIsWeb ? (Uri.base.queryParameters['engine'] ?? 'web') : 'rust');

final engineProvider = Provider<EngineGateway>(
  (ref) => switch (kEngine) {
    'rust' => RustEngine(window: ref.watch(historicalWindowProvider)),
    'web' => WebEngine(window: ref.watch(historicalWindowProvider)),
    'mock' => MockEngine(),
    _ => throw StateError(
      'Unsupported ENGINE value. Choose rust, web or mock.',
    ),
  },
);

/// Device storage. Overridden in main(); null in tests = memory only.
/// Farmer answers and notes never leave the phone (master plan §13).
final prefsProvider = Provider<SharedPreferences?>((ref) => null);

/// Firebase cloud copy. Null when Firebase did not start (tests, no config)
/// — the app then works fully offline. Overridden in main().
/// Team decision (Nov 2026): signed-in farmers' farm, answers, notes and
/// check results upload automatically to their own Google account space.
final cloudSyncProvider = Provider<CloudSync?>((ref) => null);

/// The last 12 completed months — a full year of weather for the strip.
HistoricalWindow lastTwelveMonths([DateTime? now]) {
  final n = (now ?? DateTime.now()).toUtc();
  final end = DateTime.utc(n.year, n.month - 1);
  final start = DateTime.utc(end.year, end.month - 11);
  return HistoricalWindow(
    startYear: start.year,
    startMonth: start.month,
    endYear: end.year,
    endMonth: end.month,
  );
}

class HistoricalWindowNotifier extends Notifier<HistoricalWindow> {
  /// Farmers see a whole year by default (the team's class default is one
  /// verified month, kept for its captured-data tests).
  @override
  HistoricalWindow build() => lastTwelveMonths();
  void setWindow(HistoricalWindow window) => state = window;
}

final historicalWindowProvider =
    NotifierProvider<HistoricalWindowNotifier, HistoricalWindow>(
      HistoricalWindowNotifier.new,
    );

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
    this.farm,
  });

  /// The pin from setup (one tap or GPS).
  final double? latitude;
  final double? longitude;
  final String? currentCrop;
  final String? previousCrop;
  final int? plantingMonth; // 0 = unknown
  final Irrigation? irrigation;
  final Drainage? drainage;
  final Set<Priority>? priorities; // empty set = "I don't know"

  /// The whole farm (4 corners), marked later on the Field tab.
  final FarmBoundary? farm;

  bool get hasLocation => latitude != null && longitude != null;
  bool get hasFarm => farm?.isComplete ?? false;

  /// Where the analysis is calculated: the farm centre once the farm is
  /// marked, otherwise the setup pin.
  double? get fieldLatitude => hasFarm ? farm!.center.latitude : latitude;
  double? get fieldLongitude => hasFarm ? farm!.center.longitude : longitude;

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
    FarmBoundary? farm,
  }) => FarmerDraft(
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    currentCrop: currentCrop ?? this.currentCrop,
    previousCrop: previousCrop ?? this.previousCrop,
    plantingMonth: plantingMonth ?? this.plantingMonth,
    irrigation: irrigation ?? this.irrigation,
    drainage: drainage ?? this.drainage,
    priorities: priorities ?? this.priorities,
    farm: farm ?? this.farm,
  );

  FarmerInput toInput() {
    String? crop(String? v) => (v == null || v == kUnknown) ? null : v;
    return FarmerInput(
      latitude: fieldLatitude!,
      longitude: fieldLongitude!,
      boundary: farm?.toJson() ?? const [],
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
    'farm': farm?.toJson(),
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
      farm: FarmBoundary.fromJson(j['farm']),
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
    pushToCloud();
  }

  /// Uploads the farm and answers (no-op when signed out / offline build).
  void pushToCloud() {
    final d = state;
    ref
        .read(cloudSyncProvider)
        ?.saveFarm(
          pinLat: d.latitude,
          pinLon: d.longitude,
          farm: d.farm,
          currentCrop: d.currentCrop,
          irrigation: d.irrigation?.name,
          drainage: d.drainage?.name,
        );
  }

  /// New phone: take the saved farm from the cloud if this phone has none.
  void restoreFromCloud(Map<String, dynamic> farm) {
    if (state.isComplete) return;
    final pin = farm['pin'];
    final answers = (farm['answers'] as Map?) ?? const {};
    final corners = farm['corners'] as List? ?? const [];
    T? e<T extends Enum>(List<T> values, Object? raw) =>
        values.where((v) => v.name == raw).firstOrNull;
    final boundary = corners.length == FarmBoundary.cornerCount
        ? FarmBoundary([
            for (final c in corners)
              LatLng(
                ((c as Map)['lat'] as num).toDouble(),
                (c['lon'] as num).toDouble(),
              ),
          ])
        : null;
    final restored = FarmerDraft(
      latitude: (pin is Map) ? (pin['lat'] as num?)?.toDouble() : null,
      longitude: (pin is Map) ? (pin['lon'] as num?)?.toDouble() : null,
      currentCrop: answers['current_crop'] as String?,
      irrigation: e(Irrigation.values, answers['irrigation']),
      drainage: e(Drainage.values, answers['drainage']),
      farm: boundary,
    );
    state = restored;
    ref
        .read(prefsProvider)
        ?.setString(_draftKey, jsonEncode(restored.toJson()));
  }

  /// Moving the setup pin far away means a different farm: forget the old shape.
  void setLocation(double lat, double lon) {
    final keepFarm =
        state.farm != null &&
        const Distance().as(
              LengthUnit.Kilometer,
              state.farm!.center,
              LatLng(lat, lon),
            ) <
            2;
    _set(
      FarmerDraft(
        latitude: lat,
        longitude: lon,
        currentCrop: state.currentCrop,
        previousCrop: state.previousCrop,
        plantingMonth: state.plantingMonth,
        irrigation: state.irrigation,
        drainage: state.drainage,
        priorities: state.priorities,
        farm: keepFarm ? state.farm : null,
      ),
    );
  }

  void setFarm(FarmBoundary farm) {
    _set(state.copyWith(farm: farm));
    ref.read(cloudSyncProvider)?.logEvent('farm_marked');
  }

  void clearFarm() => _set(
    FarmerDraft(
      latitude: state.latitude,
      longitude: state.longitude,
      currentCrop: state.currentCrop,
      previousCrop: state.previousCrop,
      plantingMonth: state.plantingMonth,
      irrigation: state.irrigation,
      drainage: state.drainage,
      priorities: state.priorities,
    ),
  );
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
      farm: state.farm,
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
    final note = FieldNote(
      id: now.microsecondsSinceEpoch.toString(),
      createdAt: now,
      kind: kind,
      text: text.trim(),
    );
    _save([note, ...state]);
    ref.read(cloudSyncProvider)
      ?..saveNote(note)
      ..logEvent('note_added');
  }

  void remove(String id) {
    _save([
      for (final n in state)
        if (n.id != id) n,
    ]);
    ref.read(cloudSyncProvider)?.deleteNote(id);
  }

  /// Adds cloud notes this phone does not have yet (new phone / reinstall),
  /// and uploads notes written here before signing in.
  void mergeCloud(List<FieldNote> cloud) {
    final have = {for (final n in state) n.id};
    final cloudIds = {for (final n in cloud) n.id};
    final sync = ref.read(cloudSyncProvider);
    for (final n in state) {
      if (!cloudIds.contains(n.id)) sync?.saveNote(n);
    }
    final extra = [
      for (final n in cloud)
        if (!have.contains(n.id)) n,
    ];
    if (extra.isEmpty) return;
    _save(
      [...state, ...extra]..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
    );
  }

  /// Undo for a just-removed note.
  void restore(FieldNote note) {
    final next = [...state, note]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _save(next);
    ref.read(cloudSyncProvider)?.saveNote(note);
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
      ref.read(cloudSyncProvider)
        ?..saveCheck(result)
        ..logEvent('check_run');
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

  /// Run for the saved field if nothing has run yet (app reopened).
  void ensureFor(FarmerDraft draft) {
    if (state is AnalysisIdle && draft.hasLocation) run(draft.toInput());
  }

  /// Fallback for outages: the bundled demo fixture (master plan §12, H28).
  Future<void> runDemo() async {
    final generation = ++_generation;
    state = const AnalysisRunning();
    try {
      final result = await MockEngine(
        delay: Duration.zero,
      ).analyzeField(_demoInput);
      if (generation != _generation) return;
      state = AnalysisReady(result);
    } on EngineError catch (e) {
      if (generation != _generation) return;
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
