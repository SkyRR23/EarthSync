import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../engine/engine_envelope.dart';
import '../models/farmer_input.dart';
import '../models/field_analysis.dart';
import '../models/integration_trace.dart';

/// The last real check, kept on the phone so the farmer can still see it with
/// no internet. Only results with a full trace (live NASA → Rust) are saved,
/// and they are rebuilt from the exact Rust output — nothing is recalculated.
/// A saved result is reused only for the same farm and the same answers.
class SavedResult {
  const SavedResult({
    required this.trace,
    required this.inputKey,
    required this.savedAt,
  });

  final IntegrationTrace trace;

  /// The exact engine input it was checked for (JSON text).
  final String inputKey;
  final DateTime savedAt;

  FieldAnalysis? restore() {
    try {
      return fieldAnalysisFromEnvelope(trace.rustResultJson, trace: trace);
    } catch (_) {
      return null; // stored by an older app version: ignore it
    }
  }

  bool matches(FarmerInput input) => inputKey == inputKeyOf(input);
}

const _key = 'last_result_v1';

String inputKeyOf(FarmerInput input) => jsonEncode(input.toJson());

/// Saves [a] if it is a real (traced, non-demo) result. Returns the save time.
DateTime? saveLastResult(
  SharedPreferences? prefs,
  FieldAnalysis a,
  FarmerInput input, {
  DateTime? now,
}) {
  final trace = a.trace;
  if (prefs == null || trace == null || a.dataQuality.isDemo) return null;
  final at = (now ?? DateTime.now()).toUtc();
  prefs.setString(
    _key,
    jsonEncode({
      'trace': trace.toJson(),
      'input': inputKeyOf(input),
      'saved_at': at.toIso8601String(),
    }),
  );
  return at;
}

SavedResult? loadLastResult(SharedPreferences? prefs) {
  final raw = prefs?.getString(_key);
  if (raw == null) return null;
  try {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return SavedResult(
      trace: IntegrationTrace.fromJson(j['trace'] as Map<String, dynamic>),
      inputKey: j['input'] as String,
      savedAt: DateTime.parse(j['saved_at'] as String),
    );
  } catch (_) {
    return null;
  }
}

void clearLastResult(SharedPreferences? prefs) => prefs?.remove(_key);
