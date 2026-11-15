import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/cache/last_result.dart';
import '../data/cloud/cloud_sync.dart';
import '../data/environment/nasa_power_client.dart';
import '../data/engine/engine_gateway.dart';
import '../data/engine/mock_engine.dart';
import '../data/engine/rust_engine.dart';
import '../data/models/farm_boundary.dart';
import '../data/engine/web_engine.dart';
import '../data/models/farmer_input.dart';
import '../data/models/soil_texture.dart';
import '../data/photos/photo_store.dart';
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

/// The app's photo folder. Null on web and in tests (no photos there).
final photoStoreProvider = Provider<PhotoStore?>((ref) => null);

/// Last full calendar year (Jan–Dec). NASA POWER's newest months arrive
/// late and the backend refuses incomplete ones, so in Jan–Feb we step back
/// one more year. Jan–Dec also reads naturally on the month strip.
HistoricalWindow lastFullYear([DateTime? now]) {
  final n = (now ?? DateTime.now()).toUtc();
  final y = n.month <= 2 ? n.year - 2 : n.year - 1;
  return HistoricalWindow(
    startYear: y,
    startMonth: 1,
    endYear: y,
    endMonth: 12,
  );
}

class HistoricalWindowNotifier extends Notifier<HistoricalWindow> {
  /// Farmers see a whole year by default (the team's class default is one
  /// verified month, kept for its captured-data tests).
  @override
  HistoricalWindow build() => lastFullYear();
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
    this.soilTexture,
    this.soilCheckedOn,
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

  /// Farmer's soil feel test (engine name, e.g. `clay_loam`); kUnknown = not sure.
  final String? soilTexture;
  final DateTime? soilCheckedOn;

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
    String? soilTexture,
    DateTime? soilCheckedOn,
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
    soilTexture: soilTexture ?? this.soilTexture,
    soilCheckedOn: soilCheckedOn ?? this.soilCheckedOn,
  );

  FarmerInput toInput() {
    String? crop(String? v) => (v == null || v == kUnknown) ? null : v;
    return FarmerInput(
      latitude: fieldLatitude!,
      longitude: fieldLongitude!,
      boundary: farm?.toJson() ?? const [],
      soilTexture: (soilTexture == null || soilTexture == kUnknown)
          ? null
          : soilTexture,
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
    'soil_texture': soilTexture,
    'soil_checked_on': soilCheckedOn?.toIso8601String(),
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
      soilTexture: j['soil_texture'] as String?,
      soilCheckedOn: DateTime.tryParse(j['soil_checked_on'] as String? ?? ''),
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
          soilTexture: d.soilTexture,
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
      soilTexture: answers['soil_texture'] as String?,
    );
    state = restored;
    ref
        .read(prefsProvider)
        ?.setString(_draftKey, jsonEncode(restored.toJson()));
  }

  /// Moving the setup pin far away means a different farm: forget the old shape.
  void setLocation(double lat, double lon) {
    final keepSoil =
        state.hasLocation &&
        const Distance().as(
              LengthUnit.Kilometer,
              LatLng(state.latitude!, state.longitude!),
              LatLng(lat, lon),
            ) <
            2;
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
        // Soil belongs to the place: keep it only for a nearby pin.
        soilTexture: keepSoil ? state.soilTexture : null,
        soilCheckedOn: keepSoil ? state.soilCheckedOn : null,
      ),
    );
  }

  /// Result of the soil feel test (null = farmer not sure).
  void setSoil(SoilTexture? t) => _set(
    state.copyWith(
      soilTexture: t?.engineName ?? kUnknown,
      soilCheckedOn: DateTime.now(),
    ),
  );

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
      soilTexture: state.soilTexture,
      soilCheckedOn: state.soilCheckedOn,
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
      soilTexture: state.soilTexture,
      soilCheckedOn: state.soilCheckedOn,
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

  /// "Delete my data": forget every note on this phone (no cloud calls).
  void clearAll() {
    state = const [];
    ref.read(prefsProvider)?.remove(_notesKey);
  }

  void _save(List<FieldNote> notes) {
    state = notes;
    ref
        .read(prefsProvider)
        ?.setString(_notesKey, jsonEncode([for (final n in notes) n.toJson()]));
  }

  FieldNote add(NoteKind kind, String text, {String? photo, String? id}) {
    final now = DateTime.now();
    final note = FieldNote(
      id: id ?? now.microsecondsSinceEpoch.toString(),
      createdAt: now,
      kind: kind,
      text: text.trim(),
      photo: photo,
    );
    _save([note, ...state]);
    ref.read(cloudSyncProvider)
      ?..saveNote(note)
      ..logEvent(photo == null ? 'note_added' : 'photo_note_added');
    if (photo != null) _uploadPhoto(note);
    return note;
  }

  /// Copies the note's photo to Firebase Storage, then records its path.
  Future<void> _uploadPhoto(FieldNote note) async {
    final sync = ref.read(cloudSyncProvider);
    final store = ref.read(photoStoreProvider);
    if (sync == null || store == null || note.photo == null) return;
    final path = await sync.uploadPhoto(note.id, store.file(note.photo!));
    if (path == null) return;
    final updated = note.withCloudPhoto(path);
    if (!state.any((n) => n.id == note.id)) return; // deleted meanwhile
    _save([for (final n in state) n.id == note.id ? updated : n]);
    sync.saveNote(updated);
  }

  /// Removes a note now; its photo is deleted a little later unless the
  /// farmer taps Undo first.
  void remove(String id) {
    final gone = state.where((n) => n.id == id).firstOrNull;
    _save([
      for (final n in state)
        if (n.id != id) n,
    ]);
    Future<void>.delayed(const Duration(seconds: 10), () {
      if (state.any((n) => n.id == id)) return; // undone
      ref.read(cloudSyncProvider)?.deleteNote(id);
      ref.read(photoStoreProvider)?.delete(gone?.photo);
    });
  }

  /// Adds cloud notes this phone does not have yet (new phone / reinstall),
  /// and uploads notes written here before signing in.
  void mergeCloud(List<FieldNote> cloud) {
    final have = {for (final n in state) n.id};
    final cloudIds = {for (final n in cloud) n.id};
    final sync = ref.read(cloudSyncProvider);
    for (final n in state) {
      if (!cloudIds.contains(n.id)) sync?.saveNote(n);
      if (n.photo != null && n.cloudPhoto == null) _uploadPhoto(n);
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
  const AnalysisReady(
    this.analysis, {
    this.fromCache = false,
    this.savedAt,
    this.refreshing = false,
    this.refreshFailed = false,
  });
  final FieldAnalysis analysis;

  /// Shown from the phone's saved copy, not a fresh check.
  final bool fromCache;

  /// When the saved copy was made (null for in-memory results).
  final DateTime? savedAt;

  /// A fresh check is running quietly behind the saved result.
  final bool refreshing;

  /// The latest fresh check failed (e.g. no internet); still showing saved.
  final bool refreshFailed;
}

class AnalysisFailed extends AnalysisState {
  const AnalysisFailed(this.error, {this.lastGood});
  final EngineError error;
  final FieldAnalysis? lastGood;
}

class AnalysisNotifier extends Notifier<AnalysisState> {
  FieldAnalysis? _lastGood;
  String? _lastGoodKey;
  DateTime? _lastGoodAt;
  int _generation = 0;

  /// App opened: show the saved result for this farm and answers at once.
  @override
  AnalysisState build() {
    final draft = ref.read(farmerDraftProvider);
    final saved = loadLastResult(ref.read(prefsProvider));
    if (saved == null || !draft.hasLocation) return const AnalysisIdle();
    final restored = saved.restore();
    if (restored == null) return const AnalysisIdle();
    _lastGood = restored;
    _lastGoodKey = saved.inputKey;
    _lastGoodAt = saved.savedAt;
    if (!saved.matches(draft.toInput())) return const AnalysisIdle();
    return AnalysisReady(restored, fromCache: true, savedAt: saved.savedAt);
  }

  /// [quiet]: keep showing the current result while checking again.
  Future<void> run(FarmerInput input, {bool quiet = false}) async {
    final generation = ++_generation;
    final current = state;
    state = quiet && current is AnalysisReady
        ? AnalysisReady(
            current.analysis,
            fromCache: current.fromCache,
            savedAt: current.savedAt,
            refreshing: true,
          )
        : const AnalysisRunning();
    try {
      final result = await ref.read(engineProvider).analyzeField(input);
      if (generation != _generation) return;
      _lastGood = result;
      _lastGoodKey = inputKeyOf(input);
      _lastGoodAt =
          saveLastResult(ref.read(prefsProvider), result, input) ?? _lastGoodAt;
      state = AnalysisReady(result);
      ref.read(cloudSyncProvider)
        ?..saveCheck(result)
        ..logEvent('check_run');
    } catch (e) {
      if (generation != _generation) return;
      final error = e is EngineError
          ? e
          : EngineError(code: 'unexpected', message: e.toString());
      // Same farm and answers as the saved result: keep showing it.
      if (_lastGood != null && _lastGoodKey == inputKeyOf(input)) {
        state = AnalysisReady(
          _lastGood!,
          fromCache: true,
          savedAt: _lastGoodAt,
          refreshFailed: true,
        );
      } else {
        state = AnalysisFailed(error, lastGood: _lastGood);
      }
    }
  }

  /// App reopened with a saved farm: check it (quietly if a result shows).
  void ensureFor(FarmerDraft draft) {
    if (!draft.hasLocation) return;
    final s = state;
    if (s is AnalysisIdle) {
      run(draft.toInput());
    } else if (s is AnalysisReady && s.fromCache && !s.refreshing) {
      run(draft.toInput(), quiet: true);
    }
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
    if (_lastGood != null) {
      state = AnalysisReady(_lastGood!, fromCache: true, savedAt: _lastGoodAt);
    }
  }

  /// Start over: forget the saved result too (it belongs to the old farm).
  void forget() {
    ++_generation;
    _lastGood = null;
    _lastGoodKey = null;
    _lastGoodAt = null;
    clearLastResult(ref.read(prefsProvider));
    state = const AnalysisIdle();
  }
}

final analysisProvider = NotifierProvider<AnalysisNotifier, AnalysisState>(
  AnalysisNotifier.new,
);

/// Sample field near Yangon used by "Use sample field" and the demo fallback.
const kSampleLat = 16.85;
const kSampleLon = 96.15;
const _demoInput = FarmerInput(latitude: kSampleLat, longitude: kSampleLon);
