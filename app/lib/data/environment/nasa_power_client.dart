import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/farmer_input.dart';
import '../models/field_analysis.dart';

/// Inclusive, completed NASA LST months, independent of planting month.
class HistoricalWindow {
  const HistoricalWindow({
    this.startYear = 2024,
    this.startMonth = 2,
    this.endYear = 2024,
    this.endMonth = 2,
  });
  final int startYear, startMonth, endYear, endMonth;

  Map<String, dynamic> get json => {
    'start': {'year': startYear, 'month': startMonth},
    'end': {'year': endYear, 'month': endMonth},
  };

  void validate() {
    final start = startYear * 12 + startMonth - 1;
    final end = endYear * 12 + endMonth - 1;
    final now = DateTime.now().toUtc();
    if (startYear < 1981 || endYear > 9998 ||
        startMonth < 1 || startMonth > 12 || endMonth < 1 || endMonth > 12 ||
        end < start || end - start >= 24 || end >= now.year * 12 + now.month - 1) {
      throw const EngineError(code: 'invalid_window',
          message: 'Choose completed historical months, in order, up to 24 months.');
    }
  }
}

void validateFieldLocation(FarmerInput input) {
  if (!input.latitude.isFinite || !input.longitude.isFinite ||
      input.latitude < -90 || input.latitude > 90 ||
      input.longitude < -180 || input.longitude > 180) {
    throw const EngineError(code: 'invalid_location',
        message: 'Select a valid field latitude and longitude.');
  }
}

/// The exact response text is the provenance sidecar. Never send its extra
/// fields into Rust structs, and never attach it to another field/window.
class NasaPowerEvidence {
  NasaPowerEvidence._(this.rawJson);
  final String rawJson;
  Map<String, dynamic> get envelope => jsonDecode(rawJson) as Map<String, dynamic>;
  Map<String, dynamic> get environment => envelope['environment'] as Map<String, dynamic>;
  Map<String, dynamic> get provenance => envelope['provenance'] as Map<String, dynamic>;

  factory NasaPowerEvidence.parse(String raw, FarmerInput input, HistoricalWindow window) {
    validateFieldLocation(input);
    window.validate();
    try {
      final e = jsonDecode(raw) as Map<String, dynamic>;
      final env = e['environment'] as Map<String, dynamic>;
      final season = env['seasonal'] as Map<String, dynamic>;
      final meta = season['metadata'] as Map<String, dynamic>;
      final p = e['provenance'] as Map<String, dynamic>;
      final point = p['query_coordinates'] as Map<String, dynamic>;
      final interval = p['interval'] as Map<String, dynamic>;
      final start = DateTime.utc(window.startYear, window.startMonth);
      final end = DateTime.utc(window.endYear, window.endMonth + 1, 0);
      String date(DateTime d) => d.toIso8601String().substring(0, 10);
      if (e['schema_version'] != '1.0-proposal' || e['status'] != 'success' ||
          env['latitude'] != input.latitude || env['longitude'] != input.longitude ||
          point['latitude'] != input.latitude || point['longitude'] != input.longitude ||
          (season['window']['start']['year'] != window.startYear ||
              season['window']['start']['month'] != window.startMonth ||
              season['window']['end']['year'] != window.endYear ||
              season['window']['end']['month'] != window.endMonth) ||
          interval['start'] != date(start) || interval['end'] != date(end) ||
          meta['source'] != 'NASA POWER' || meta['data_kind'] != 'modeled' ||
          meta['dataset'] != 'POWER daily meteorology / MERRA-2' ||
          meta['rainfall_unit'] != 'mm' || meta['temperature_unit'] != 'deg_c' ||
          p['provider'] != 'NASA POWER' || p['data_kind'] != 'modeled' ||
          p['time_standard'] != 'LST' || p['spatial_support'] is! String ||
          p['product'] is! String || p['aggregation'] is! String ||
          p['original_units']['T2M'] != 'C' || p['original_units']['PRECTOTCORR'] != 'mm/day' ||
          p['normalized_units']['mean_temperature_c'] != 'deg_c' ||
          p['normalized_units']['rainfall_mm'] != 'mm' ||
          p['limitations'] is! List || p['documentation'] is! List ||
          p['coverage'] is! List || (p['source_requests'] as List).isEmpty ||
          (p['source_requests'] as List).any((r) =>
              DateTime.tryParse(r['retrieved_at'] as String? ?? '') == null) ||
          e['cache'] is! Map || season['observations'] is! List) {
        throw const FormatException();
      }
      return NasaPowerEvidence._(raw);
    } catch (_) {
      throw const EngineError(code: 'invalid_backend_response',
          message: 'Climate response does not match the NASA schema, selected field, period or provenance.');
    }
  }
}

class NasaPowerClient {
  NasaPowerClient({http.Client? client, this.baseUrl = const String.fromEnvironment(
    'BACKEND_URL', defaultValue: 'http://127.0.0.1:8000'),
    this.timeout = const Duration(seconds: 90)}) : _client = client;
  final http.Client? _client;
  final String baseUrl;
  final Duration timeout;

  Future<NasaPowerEvidence> fetch(FarmerInput input, HistoricalWindow window) async {
    validateFieldLocation(input);
    window.validate();
    final base = Uri.tryParse(baseUrl);
    final local = base != null && ['127.0.0.1', 'localhost', '10.0.2.2'].contains(base.host);
    if (base == null || !base.hasAuthority || base.userInfo.isNotEmpty ||
        base.query.isNotEmpty || base.fragment.isNotEmpty ||
        !(base.scheme == 'https' || (kDebugMode && local && base.scheme == 'http'))) {
      throw const EngineError(code: 'backend_configuration',
          message: 'Configure an HTTPS backend URL, or a debug localhost URL for USB testing.');
    }
    final uri = base.resolve('/api/v1/environment/season').replace(queryParameters: {
      'latitude': '${input.latitude}', 'longitude': '${input.longitude}',
      'start_year': '${window.startYear}', 'start_month': '${window.startMonth}',
      'end_year': '${window.endYear}', 'end_month': '${window.endMonth}',
    });
    final client = _client ?? http.Client();
    try {
      final response = await client.get(uri, headers: {'Accept': 'application/json'}).timeout(timeout);
      if (response.statusCode != 200) {
        throw EngineError(code: 'backend_http_${response.statusCode}',
            message: 'Climate server returned HTTP ${response.statusCode}. No climate data were substituted.',
            retryable: response.statusCode >= 500);
      }
      return NasaPowerEvidence.parse(response.body, input, window);
    } on EngineError {
      rethrow;
    } on TimeoutException {
      throw const EngineError(code: 'backend_timeout',
          message: 'Climate server timed out. Retry when it is available.', retryable: true);
    } on http.ClientException {
      throw const EngineError(code: 'backend_unavailable',
          message: 'Could not reach the climate server. Check the URL and USB connection.', retryable: true);
    } finally {
      if (_client == null) client.close();
    }
  }
}
