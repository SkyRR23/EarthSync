import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/providers.dart';
import 'simulation_clock.dart';

// Simulation checks are local to a field and historical day. They must not
// become real watering records or be uploaded as actual field activities.
final simulationObservationKeyProvider = Provider<String>((ref) {
  final date = ref.watch(simulationClockProvider);
  final field = ref.watch(farmerDraftProvider);
  return jsonEncode({
    'date': date.toIso8601String().substring(0, 10),
    'field': [field.fieldLatitude, field.fieldLongitude],
    'boundary': field.farm?.toJson(),
  });
});

class SimulationChecks extends Notifier<Map<String, bool>> {
  static const _storage = 'simulation.checks.v1';
  @override
  Map<String, bool> build() {
    final raw = ref.read(prefsProvider)?.getString(_storage);
    if (raw == null) return {};
    try {
      return Map<String, bool>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  void mark(String contextKey, String check, bool done) {
    final key = '$contextKey::$check';
    final updated = {...state};
    if (done) {
      updated[key] = true;
    } else {
      updated.remove(key);
    }
    state = updated;
    ref.read(prefsProvider)?.setString(_storage, jsonEncode(state));
  }

  void clearAll() {
    state = {};
    ref.read(prefsProvider)?.remove(_storage);
  }
}

final simulationChecksProvider =
    NotifierProvider<SimulationChecks, Map<String, bool>>(SimulationChecks.new);

bool simulationChecked(Map<String, bool> checks, String contextKey, String id) =>
    checks['$contextKey::$id'] == true;
