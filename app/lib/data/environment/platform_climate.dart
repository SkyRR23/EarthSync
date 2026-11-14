import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/home_profile.dart';

const platformUrl = String.fromEnvironment('PLATFORM_URL');

class PlatformFailure implements Exception {
  const PlatformFailure(this.code, {this.retryable = false});
  final String code;
  final bool retryable;
  @override
  String toString() => code;
}

enum ClimateJobStatus { queued, running, succeeded, failed, cancelled }

class DailyMeasurement {
  DailyMeasurement.fromJson(Map<String, dynamic> json)
    : variable = json['variable'] as String,
      date = json['date'] as String?,
      value = (json['value'] as num?)?.toDouble(),
      unit = json['unit'] as String,
      originalValue = (json['original_value'] as num?)?.toDouble(),
      originalUnit = json['original_unit'] as String,
      quality = json['quality'] as String,
      missingReason = json['missing_reason'] as String?;
  final String variable, unit, originalUnit, quality;
  final String? date, missingReason;
  final double? value, originalValue;
}

class DailyEvidence {
  DailyEvidence.fromJson(this.raw) {
    if (raw['schema_version'] != 'earthsync.evidence.v1.0' ||
        raw['data_type'] != 'modeled' ||
        raw['source_metadata']['policy'] != 'power-daily-merra2.v1') {
      throw const FormatException(
        'Unsupported daily climate evidence contract',
      );
    }
  }
  final Map<String, dynamic> raw;
  String get provider => raw['provider'] as String;
  String get dataset => raw['dataset'] as String;
  String get sourceUrl => raw['source_url'] as String;
  List<DailyMeasurement> get measurements => (raw['measurements'] as List)
      .map((m) => DailyMeasurement.fromJson(m as Map<String, dynamic>))
      .toList();
}

class ClimateJob {
  ClimateJob.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      status = ClimateJobStatus.values.byName(json['status'] as String),
      error = json['error'] as String?,
      retryable = json['retryable'] as bool,
      records = ((json['result']?['records'] as List?) ?? [])
          .map((r) => DailyEvidence.fromJson(r as Map<String, dynamic>))
          .toList(),
      gaps = List<Map<String, dynamic>>.from(
        json['result']?['gaps'] as List? ?? [],
      );
  final String id;
  final ClimateJobStatus status;
  final String? error;
  final bool retryable;
  final List<DailyEvidence> records;
  final List<Map<String, dynamic>> gaps;
  bool get pending =>
      status == ClimateJobStatus.queued || status == ClimateJobStatus.running;
}

/// 7I remains loopback-only. The adapter does not create farms, transfer tokens,
/// change ownership, bypass origin checks, or substitute monthly evidence.
class PlatformClimateClient {
  PlatformClimateClient(this.client, {required this.baseUri}) {
    if (!['localhost', '127.0.0.1', '::1'].contains(baseUri.host) ||
        !['http', 'https'].contains(baseUri.scheme) ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment) {
      throw ArgumentError(
        'The evidence platform requires an explicit loopback URL.',
      );
    }
  }
  final http.Client client;
  final Uri baseUri;
  Future<ClimateJob> submit({
    required GeoPoint point,
    required DateTime start,
    required DateTime end,
  }) async {
    final first = DateTime.utc(start.year, start.month, start.day),
        last = DateTime.utc(end.year, end.month, end.day);
    final now = DateTime.now().toUtc();
    if (first.year < 1981 ||
        last.isBefore(first) ||
        last.difference(first).inDays >= 366 ||
        !last.isBefore(DateTime.utc(now.year, now.month, now.day))) {
      throw const FormatException(
        'Choose 1–366 ordered historical days from 1981.',
      );
    }
    return ClimateJob.fromJson(
      await _request(
        'POST',
        '/api/platform/v1/climate/jobs',
        body: {
          'query': {
            'point': point.toJson(),
            'start': first.toIso8601String().substring(0, 10),
            'end': last.toIso8601String().substring(0, 10),
            'lineage': 'MERRA2',
            'contract_version': 'power-daily-merra2.v1',
          },
        },
      ),
    );
  }

  Future<ClimateJob> refresh(String id) async => ClimateJob.fromJson(
    await _request('GET', '/api/platform/v1/jobs/${Uri.encodeComponent(id)}'),
  );
  Future<ClimateJob> cancel(String id) async => ClimateJob.fromJson(
    await _request(
      'DELETE',
      '/api/platform/v1/jobs/${Uri.encodeComponent(id)}',
    ),
  );
  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final request = http.Request(method, baseUri.resolve(path));
      request.headers['Content-Type'] = 'application/json';
      if (body != null) request.body = jsonEncode(body);
      final response = await http.Response.fromStream(
        await client.send(request),
      ).timeout(const Duration(seconds: 30));
      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode != 200 && response.statusCode != 202) {
        throw PlatformFailure(
          json['error']?['code'] as String? ?? 'PLATFORM_UNAVAILABLE',
          retryable: json['error']?['retryable'] == true,
        );
      }
      return json;
    } on PlatformFailure {
      rethrow;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const PlatformFailure('NETWORK_UNAVAILABLE', retryable: true);
    }
  }
}
