import '../backend_response.dart';

import 'package:http/http.dart' as http;

/// WMO weather code -> (plain words, picture). Open-Meteo uses these codes.
(String, String) weatherLook(int? code) => switch (code) {
  0 => ('Clear sky', '☀️'),
  1 => ('Mostly clear', '🌤️'),
  2 => ('Partly cloudy', '⛅'),
  3 => ('Cloudy', '☁️'),
  45 || 48 => ('Fog', '🌫️'),
  51 || 53 || 55 || 56 || 57 => ('Drizzle', '🌦️'),
  61 || 63 || 66 || 80 || 81 => ('Rain showers', '🌧️'),
  65 || 67 || 82 => ('Heavy rain', '🌧️'),
  71 || 73 || 75 || 77 || 85 || 86 => ('Snow', '🌨️'),
  95 || 96 || 99 => ('Thunderstorms', '⛈️'),
  _ => ('Not known', '❔'),
};

class CurrentWeather {
  const CurrentWeather({
    this.tempC,
    this.feelsLikeC,
    this.code,
    this.windKmh,
    this.time,
  });
  final double? tempC, feelsLikeC, windKmh;
  final int? code;
  final DateTime? time;
}

class ForecastDay {
  const ForecastDay({
    required this.date,
    this.code,
    this.maxC,
    this.minC,
    this.rainMm,
    this.rainChance,
  });
  final DateTime date;
  final int? code;
  final double? maxC, minC, rainMm;
  final int? rainChance;
}

/// Open-Meteo 5-day forecast via the backend. A model forecast, not a
/// measurement; unknown values stay null.
class Forecast {
  const Forecast({
    required this.current,
    required this.days,
    required this.fetchedAt,
  });
  final CurrentWeather current;
  final List<ForecastDay> days;
  final DateTime fetchedAt;

  static double? _d(Object? v) => (v as num?)?.toDouble();

  factory Forecast.fromJson(
    Map<String, dynamic> j, {
    required DateTime fetchedAt,
  }) {
    final c = (j['current'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Forecast(
      fetchedAt: fetchedAt,
      current: CurrentWeather(
        tempC: _d(c['temp_c']),
        feelsLikeC: _d(c['feels_like_c']),
        code: (c['weather_code'] as num?)?.toInt(),
        windKmh: _d(c['wind_kmh']),
        time: DateTime.tryParse(c['time'] as String? ?? ''),
      ),
      days: [
        for (final raw in (j['days'] as List? ?? const []))
          if (DateTime.tryParse((raw as Map)['date'] as String? ?? '')
              case final date?)
            ForecastDay(
              date: date,
              code: (raw['weather_code'] as num?)?.toInt(),
              maxC: _d(raw['max_c']),
              minC: _d(raw['min_c']),
              rainMm: _d(raw['rain_mm']),
              rainChance: (raw['rain_chance'] as num?)?.toInt(),
            ),
      ],
    );
  }
}

class ForecastException implements Exception {
  const ForecastException(this.code);
  final String code;
}

class ForecastClient {
  ForecastClient({
    this.baseUrl = const String.fromEnvironment(
      'BACKEND_URL',
      defaultValue: 'http://127.0.0.1:8000',
    ),
    this.client,
    this.timeout = const Duration(seconds: 30),
  });
  final String baseUrl;
  final http.Client? client;
  final Duration timeout;

  Future<(Map<String, dynamic>, Forecast)> fetch(double lat, double lon) async {
    final uri = Uri.parse(baseUrl)
        .resolve('/api/v1/environment/forecast')
        .replace(
          queryParameters: {
            'latitude': lat.toStringAsFixed(4),
            'longitude': lon.toStringAsFixed(4),
          },
        );
    final c = client ?? http.Client();
    try {
      final r = await c.get(uri).timeout(timeout);
      final j = backendJson(r);
      if (j == null) throw ForecastException(backendFailure(r));
      if (r.statusCode == 200 && j['status'] == 'success') {
        return (j, Forecast.fromJson(j, fetchedAt: DateTime.now()));
      }
      final e = (j['error'] as Map?) ?? const {};
      throw ForecastException(e['code'] is String ? e['code'] as String : backendFailure(r));
    } on ForecastException {
      rethrow;
    } catch (_) {
      throw const ForecastException('unreachable');
    } finally {
      if (client == null) c.close();
    }
  }
}
