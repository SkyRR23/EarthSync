import '../models/home_profile.dart';
import '../models/farm_boundary.dart';

/// Accept the existing bounded SoilGrids display contract, never a suitability rule.
Map<String, dynamic>? validatedSoilLayer(
  Map<String, dynamic> raw,
  GeoPoint point,
) {
  try {
    final source = Uri.parse(raw['source_url'] as String);
    final cells = raw['cells'] as List;
    final retrieved = DateTime.parse(raw['retrieved_at'] as String);
    if (raw['schema_version'] != 'earthsync.soil-map.v1' ||
        raw['provider'] != 'ISRIC SoilGrids' ||
        raw['property'] != 'phh2o' ||
        raw['unit'] != 'pH' ||
        raw['resolution_m'] != 250 ||
        '${raw['depth_cm']}' != '[0, 5]' ||
        raw['usable_for_assessment'] != false ||
        !['available', 'no_valid_pixels'].contains(raw['status']) ||
        source.scheme != 'https' ||
        source.host != 'files.isric.org' ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['source_sha256'] as String) ||
        retrieved.isAfter(
          DateTime.now().toUtc().add(const Duration(days: 1)),
        ) ||
        cells.isEmpty ||
        cells.length > 25) {
      return null;
    }
    var coversPoint = false;
    for (final cell in cells) {
      final value = cell['value'];
      if (value != null &&
          (value is! num || !value.isFinite || value < 0 || value > 14)) {
        return null;
      }
      if (cell['geometry']['type'] != 'Polygon') return null;
      final rings = cell['geometry']['coordinates'] as List;
      if (rings.length != 1) return null;
      final ring = rings.single as List;
      if (ring.length < 4 || ring.length > 10) return null;
      final vertices = [
        for (final pair in ring)
          GeoPoint((pair[1] as num).toDouble(), (pair[0] as num).toDouble()),
      ];
      if (vertices.first != vertices.last) return null;
      final footprint = FarmBoundary(vertices.sublist(0, vertices.length - 1));
      if (footprint.covers(point)) coversPoint = true;
    }
    return coversPoint ? raw : null;
  } catch (_) {
    return null;
  }
}
