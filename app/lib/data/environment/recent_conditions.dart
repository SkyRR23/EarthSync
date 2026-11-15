import 'dart:convert';

import 'package:http/http.dart' as http;

/// How a recent value compares with the same time of year at this place in
/// past years (thirds of the place's own record; the backend decides).
enum Compared { lower, usual, higher, unknown }

Compared _compared(Object? v) => switch (v) {
  'less' || 'drier' => Compared.lower,
  'usual' => Compared.usual,
  'more' || 'wetter' => Compared.higher,
  _ => Compared.unknown,
};

/// The last days at the farm from NASA POWER (modeled, about 50 km), from the
/// backend's `/api/v1/environment/recent`. Unknown stays null, never guessed.
class RecentConditions {
  const RecentConditions({
    required this.asOf,
    required this.fetchedAt,
    this.rain7dMm,
    this.rainVsPast = Compared.unknown,
    this.rootWetness,
    this.wetnessVsPast = Compared.unknown,
    this.heaviestDay,
    this.heaviestMm,
    this.heavierThanPercent,
    this.heaviestUnusual = false,
    this.pastYears = 10,
    this.et0Request,
  });

  /// Newest day NASA has published (a few days behind today).
  final DateTime? asOf;
  final DateTime fetchedAt;
  final double? rain7dMm;
  final Compared rainVsPast;
  final double? rootWetness;
  final Compared wetnessVsPast;
  final DateTime? heaviestDay;
  final double? heaviestMm;
  final int? heavierThanPercent;
  final bool heaviestUnusual;
  final int pastYears;

  /// NASA days ready for the team engine's FAO-56 ET0 (`v03::water`).
  final Map<String, dynamic>? et0Request;

  factory RecentConditions.fromJson(
    Map<String, dynamic> j, {
    required DateTime fetchedAt,
  }) {
    final h = (j['heaviest_day'] as Map?)?.cast<String, dynamic>();
    return RecentConditions(
      asOf: DateTime.tryParse(j['as_of'] as String? ?? ''),
      fetchedAt: fetchedAt,
      rain7dMm: (j['rain_7d_mm'] as num?)?.toDouble(),
      rainVsPast: _compared(j['rain_7d_vs_past']),
      rootWetness: (j['root_wetness'] as num?)?.toDouble(),
      wetnessVsPast: _compared(j['root_wetness_vs_past']),
      heaviestDay: DateTime.tryParse(h?['date'] as String? ?? ''),
      heaviestMm: (h?['rain_mm'] as num?)?.toDouble(),
      heavierThanPercent: (h?['heavier_than_percent'] as num?)?.toInt(),
      heaviestUnusual: h?['unusual'] == true,
      pastYears: (j['past_years'] as num?)?.toInt() ?? 10,
      et0Request: (j['et0_request'] as Map?)?.cast<String, dynamic>(),
    );
  }
}

class RecentException implements Exception {
  const RecentException(this.code);
  final String code;
  @override
  String toString() => 'RecentException($code)';
}

class RecentClient {
  RecentClient({
    this.baseUrl = const String.fromEnvironment(
      'BACKEND_URL',
      defaultValue: 'http://127.0.0.1:8000',
    ),
    this.client,
    this.timeout = const Duration(seconds: 60),
  });

  final String baseUrl;

  /// Injected in tests; a fresh client per call otherwise.
  final http.Client? client;
  final Duration timeout;

  /// Raw JSON (kept for the offline copy) and the parsed result.
  Future<(Map<String, dynamic>, RecentConditions)> fetch(
    double latitude,
    double longitude,
  ) async {
    final uri = Uri.parse(baseUrl)
        .resolve('/api/v1/environment/recent')
        .replace(
          queryParameters: {
            'latitude': latitude.toStringAsFixed(5),
            'longitude': longitude.toStringAsFixed(5),
          },
        );
    final c = client ?? http.Client();
    try {
      final r = await c.get(uri).timeout(timeout);
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode == 200 && j['status'] == 'success') {
        return (j, RecentConditions.fromJson(j, fetchedAt: DateTime.now()));
      }
      final e = (j['error'] as Map?) ?? const {};
      throw RecentException(e['code'] as String? ?? 'http_${r.statusCode}');
    } on RecentException {
      rethrow;
    } catch (_) {
      throw const RecentException('unreachable');
    } finally {
      if (client == null) c.close();
    }
  }
}
