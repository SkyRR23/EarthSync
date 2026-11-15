import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/environment/forecast.dart';
import '../data/environment/recent_conditions.dart';
import 'providers.dart';

/// Calendar day (local), used as the key for logs and marks.
DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);
String dayKey(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

final recentClientProvider = Provider<RecentClient>((ref) => RecentClient());

class RecentState {
  const RecentState({
    this.data,
    this.loading = false,
    this.failed = false,
    this.fromCache = false,
  });
  final RecentConditions? data;
  final bool loading;

  /// The last fetch failed (no signal, or NASA/backend down).
  final bool failed;

  /// [data] is the saved copy from an earlier visit.
  final bool fromCache;
}

/// NASA's last days at the farm. Keeps the last good copy on the phone, so
/// the Today tab still works with no signal (and says how old it is).
class RecentNotifier extends Notifier<RecentState> {
  static const _key = 'recent_conditions';
  static const _fresh = Duration(hours: 6);

  (double, double)? get _place {
    final d = ref.read(farmerDraftProvider);
    final lat = d.fieldLatitude, lon = d.fieldLongitude;
    return lat == null || lon == null ? null : (lat, lon);
  }

  bool _same((double, double) a, Object? lat, Object? lon) =>
      lat is num &&
      lon is num &&
      (a.$1 - lat).abs() < 1e-4 &&
      (a.$2 - lon).abs() < 1e-4;

  @override
  RecentState build() {
    // A new farm pin or shape starts again from that place's saved copy.
    ref.watch(
      farmerDraftProvider.select((d) => (d.fieldLatitude, d.fieldLongitude)),
    );
    final place = _place;
    final raw = ref.read(prefsProvider)?.getString(_key);
    if (place == null || raw == null) return const RecentState();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (!_same(place, j['lat'], j['lon'])) return const RecentState();
      final data = RecentConditions.fromJson(
        j['data'] as Map<String, dynamic>,
        fetchedAt: DateTime.parse(j['fetched_at'] as String),
      );
      return RecentState(data: data, fromCache: true);
    } catch (_) {
      return const RecentState();
    }
  }

  /// Fetch when there is no copy for today's place or it is over 6 hours old.
  Future<void> ensureFresh() async {
    final s = state;
    if (s.loading || _place == null) return;
    final d = s.data;
    if (d != null && DateTime.now().difference(d.fetchedAt) < _fresh) return;
    await refresh();
  }

  Future<void> refresh() async {
    final place = _place;
    if (place == null) return;
    state = RecentState(
      data: state.data,
      fromCache: state.fromCache,
      loading: true,
    );
    try {
      final (raw, data) = await ref
          .read(recentClientProvider)
          .fetch(place.$1, place.$2);
      if (!ref.mounted || _place != place) return;
      state = RecentState(data: data);
      await ref
          .read(prefsProvider)
          ?.setString(
            _key,
            jsonEncode({
              'lat': place.$1,
              'lon': place.$2,
              'fetched_at': data.fetchedAt.toIso8601String(),
              'data': raw,
            }),
          );
    } catch (_) {
      if (!ref.mounted) return;
      state = RecentState(
        data: state.data,
        fromCache: state.data != null,
        failed: true,
      );
    }
  }

  Future<void> forget() async {
    state = const RecentState();
    await ref.read(prefsProvider)?.remove(_key);
  }
}

final recentProvider = NotifierProvider<RecentNotifier, RecentState>(
  RecentNotifier.new,
);

/// Days the farmer said "I watered today" (newest first, last 90 kept).
class WaterLogNotifier extends Notifier<List<DateTime>> {
  static const _key = 'water_log';

  @override
  List<DateTime> build() {
    final days = ref.read(prefsProvider)?.getStringList(_key) ?? const [];
    return [for (final s in days) ?DateTime.tryParse(s)]
      ..sort((a, b) => b.compareTo(a));
  }

  void _save() => ref.read(prefsProvider)?.setStringList(_key, [
    for (final d in state) dayKey(d),
  ]);

  void logToday([DateTime? now]) {
    final day = dayOf(now ?? DateTime.now());
    if (state.contains(day)) return;
    state = [day, ...state].take(90).toList();
    _save();
    ref.read(cloudSyncProvider)
      ?..logWatering(dayKey(day))
      ..logEvent('watered');
  }

  void undoToday([DateTime? now]) {
    final day = dayOf(now ?? DateTime.now());
    if (!state.contains(day)) return;
    state = [
      for (final d in state)
        if (d != day) d,
    ];
    _save();
    ref.read(cloudSyncProvider)?.deleteWatering(dayKey(day));
  }

  void clearAll() {
    state = const [];
    ref.read(prefsProvider)?.remove(_key);
  }
}

final waterLogProvider = NotifierProvider<WaterLogNotifier, List<DateTime>>(
  WaterLogNotifier.new,
);

/// Small "done" marks for tasks that are not a log: e.g. `water_ok` = the
/// day the farmer said the soil was still wet, `heavy_checked` = the rain day
/// they checked for standing water.
class TaskMarksNotifier extends Notifier<Map<String, String>> {
  static const _key = 'task_marks';

  @override
  Map<String, String> build() {
    final raw = ref.read(prefsProvider)?.getString(_key);
    if (raw == null) return const {};
    try {
      return (jsonDecode(raw) as Map).cast<String, String>();
    } catch (_) {
      return const {};
    }
  }

  void mark(String id, String value) {
    state = {...state, id: value};
    ref.read(prefsProvider)?.setString(_key, jsonEncode(state));
    ref.read(cloudSyncProvider)?.logEvent('task_$id');
  }

  void clearAll() {
    state = const {};
    ref.read(prefsProvider)?.remove(_key);
  }
}

final taskMarksProvider =
    NotifierProvider<TaskMarksNotifier, Map<String, String>>(
      TaskMarksNotifier.new,
    );

final forecastClientProvider = Provider<ForecastClient>(
  (ref) => ForecastClient(),
);

class ForecastState {
  const ForecastState({this.data, this.loading = false, this.failed = false});
  final Forecast? data;
  final bool loading, failed;
}

/// 5-day forecast for the farm, with the last good copy kept for offline.
class ForecastNotifier extends Notifier<ForecastState> {
  static const _key = 'forecast_cache';
  static const _fresh = Duration(minutes: 30);

  (double, double)? get _place {
    final d = ref.read(farmerDraftProvider);
    final lat = d.fieldLatitude, lon = d.fieldLongitude;
    return lat == null || lon == null ? null : (lat, lon);
  }

  @override
  ForecastState build() {
    ref.watch(
      farmerDraftProvider.select((d) => (d.fieldLatitude, d.fieldLongitude)),
    );
    final place = _place;
    final raw = ref.read(prefsProvider)?.getString(_key);
    if (place == null || raw == null) return const ForecastState();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final lat = j['lat'], lon = j['lon'];
      if (lat is! num ||
          lon is! num ||
          (lat - place.$1).abs() > 1e-3 ||
          (lon - place.$2).abs() > 1e-3) {
        return const ForecastState();
      }
      return ForecastState(
        data: Forecast.fromJson(
          (j['data'] as Map).cast<String, dynamic>(),
          fetchedAt: DateTime.parse(j['fetched_at'] as String),
        ),
      );
    } catch (_) {
      return const ForecastState();
    }
  }

  Future<void> ensureFresh() async {
    if (state.loading || _place == null) return;
    final d = state.data;
    if (d != null && DateTime.now().difference(d.fetchedAt) < _fresh) return;
    await refresh();
  }

  Future<void> refresh() async {
    final place = _place;
    if (place == null) return;
    state = ForecastState(data: state.data, loading: true);
    try {
      final (raw, data) = await ref
          .read(forecastClientProvider)
          .fetch(place.$1, place.$2);
      if (!ref.mounted || _place != place) return;
      state = ForecastState(data: data);
      await ref
          .read(prefsProvider)
          ?.setString(
            _key,
            jsonEncode({
              'lat': place.$1,
              'lon': place.$2,
              'fetched_at': data.fetchedAt.toIso8601String(),
              'data': raw,
            }),
          );
    } catch (_) {
      if (!ref.mounted) return;
      state = ForecastState(data: state.data, failed: true);
    }
  }

  Future<void> forget() async {
    state = const ForecastState();
    await ref.read(prefsProvider)?.remove(_key);
  }
}

final forecastProvider = NotifierProvider<ForecastNotifier, ForecastState>(
  ForecastNotifier.new,
);
