import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' show LatLng;

/// One 30 m NASA HLS pixel inside the farm (null NDVI = cloud, shadow,
/// water or no data: not measured).
class GreenCell {
  const GreenCell({required this.corners, this.ndvi});
  final List<LatLng> corners;
  final double? ndvi;
}

/// One clear HLS image over the farm.
class GreenScene {
  const GreenScene({
    required this.date,
    required this.sensor,
    required this.pixelsInside,
    required this.pixelsClear,
    this.ndviMean,
    this.cells = const [],
  });
  final DateTime date;
  final String sensor;
  final int pixelsInside, pixelsClear;
  final double? ndviMean;
  final List<GreenCell> cells;

  static GreenScene? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final date = DateTime.tryParse(raw['date'] as String? ?? '');
    if (date == null) return null;
    return GreenScene(
      date: date,
      sensor: raw['sensor'] as String? ?? 'NASA HLS',
      pixelsInside: (raw['pixels_inside'] as num?)?.toInt() ?? 0,
      pixelsClear: (raw['pixels_clear'] as num?)?.toInt() ?? 0,
      ndviMean: (raw['ndvi_mean'] as num?)?.toDouble(),
      cells: [
        for (final c in (raw['cells'] as List? ?? const []))
          if (c is Map && c['corners'] is List)
            GreenCell(
              ndvi: (c['ndvi'] as num?)?.toDouble(),
              corners: [
                for (final p in c['corners'] as List)
                  LatLng(
                    ((p as List)[0] as num).toDouble(),
                    (p[1] as num).toDouble(),
                  ),
              ],
            ),
      ],
    );
  }
}

/// Farm greenness (NDVI) from NASA HLS via the backend: newest clear image
/// and the clear one before it. Both can be null (no clear image).
class FarmGreenness {
  const FarmGreenness({this.latest, this.previous});
  final GreenScene? latest, previous;
}

class GreennessException implements Exception {
  const GreennessException(this.code);
  final String code;
}

class GreennessClient {
  GreennessClient({
    this.baseUrl = const String.fromEnvironment(
      'BACKEND_URL',
      defaultValue: 'http://127.0.0.1:8000',
    ),
    this.client,
    this.timeout = const Duration(seconds: 90),
  });
  final String baseUrl;
  final http.Client? client;
  final Duration timeout;

  Future<FarmGreenness> fetch(List<LatLng> farm) async {
    final uri = Uri.parse(baseUrl)
        .resolve('/api/v1/environment/greenness')
        .replace(
          queryParameters: {
            // Plain commas: web.app passes them through unchanged.
            'farm': [
              for (final p in farm) ...[
                p.latitude.toStringAsFixed(6),
                p.longitude.toStringAsFixed(6),
              ],
            ].join(','),
          },
        );
    final c = client ?? http.Client();
    try {
      final r = await c.get(uri).timeout(timeout);
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode == 200 && j['status'] == 'success') {
        return FarmGreenness(
          latest: GreenScene.fromJson(j['latest']),
          previous: GreenScene.fromJson(j['previous']),
        );
      }
      final e = (j['error'] as Map?) ?? const {};
      throw GreennessException(e['code'] as String? ?? 'http_${r.statusCode}');
    } on GreennessException {
      rethrow;
    } catch (_) {
      throw const GreennessException('unreachable');
    } finally {
      if (client == null) c.close();
    }
  }
}
