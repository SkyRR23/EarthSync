import 'dart:math' as math;
import 'home_profile.dart';

/// EPSG:4326 exterior ring, stored unclosed; GeoJSON closes it.
class FarmBoundary {
  FarmBoundary(List<GeoPoint> vertices)
    : vertices = List.unmodifiable(vertices) {
    if (vertices.length < 3 || vertices.length > 999) {
      throw const FormatException('Use 3–999 boundary vertices.');
    }
    final xs = vertices.map((p) => p.longitude);
    if (xs.reduce(math.max) - xs.reduce(math.min) > 180) {
      throw const FormatException(
        'Antimeridian-crossing boundaries are not supported. Save a point instead.',
      );
    }
    for (var i = 0; i < vertices.length; i++) {
      final a = vertices[i], b = vertices[(i + 1) % vertices.length];
      if (a == b) {
        throw const FormatException('Remove repeated adjacent vertices.');
      }
      for (var j = i + 1; j < vertices.length; j++) {
        if (j == i + 1 || (i == 0 && j == vertices.length - 1)) continue;
        if (_intersects(
          a,
          b,
          vertices[j],
          vertices[(j + 1) % vertices.length],
        )) {
          throw const FormatException(
            'Boundary edges must not cross or touch.',
          );
        }
      }
    }
    var twicePlanarArea = 0.0;
    for (var i = 0; i < vertices.length; i++) {
      final a = vertices[i], b = vertices[(i + 1) % vertices.length];
      twicePlanarArea +=
          (a.longitude - vertices.first.longitude) *
              (b.latitude - vertices.first.latitude) -
          (b.longitude - vertices.first.longitude) *
              (a.latitude - vertices.first.latitude);
    }
    if (twicePlanarArea.abs() < 1e-16) {
      throw const FormatException('Boundary vertices must enclose an area.');
    }
    if (areaSquareMetres < 0.01) {
      throw const FormatException('Boundary has no usable area.');
    }
  }
  final List<GeoPoint> vertices;
  static double _cross(GeoPoint a, GeoPoint b, GeoPoint c) =>
      (b.longitude - a.longitude) * (c.latitude - a.latitude) -
      (b.latitude - a.latitude) * (c.longitude - a.longitude);
  static bool _on(GeoPoint a, GeoPoint b, GeoPoint p) =>
      _cross(a, b, p).abs() < 1e-12 &&
      p.longitude >= math.min(a.longitude, b.longitude) &&
      p.longitude <= math.max(a.longitude, b.longitude) &&
      p.latitude >= math.min(a.latitude, b.latitude) &&
      p.latitude <= math.max(a.latitude, b.latitude);
  static bool _intersects(GeoPoint a, GeoPoint b, GeoPoint c, GeoPoint d) =>
      (_cross(a, b, c) * _cross(a, b, d) < 0 &&
          _cross(c, d, a) * _cross(c, d, b) < 0) ||
      _on(a, b, c) ||
      _on(a, b, d) ||
      _on(c, d, a) ||
      _on(c, d, b);
  bool covers(GeoPoint p) {
    var inside = false;
    for (var i = 0, j = vertices.length - 1; i < vertices.length; j = i++) {
      final a = vertices[j], b = vertices[i];
      if (_on(a, b, p)) return true;
      if ((a.latitude > p.latitude) != (b.latitude > p.latitude) &&
          p.longitude <
              (b.longitude - a.longitude) *
                      (p.latitude - a.latitude) /
                      (b.latitude - a.latitude) +
                  a.longitude) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// A draft pin inside the outline; the farmer must still confirm its location.
  GeoPoint get interiorPoint {
    final ys = vertices.map((p) => p.latitude).toSet().toList()..sort();
    for (var row = 0; row < ys.length - 1; row++) {
      final y = (ys[row] + ys[row + 1]) / 2;
      final crossings = <double>[];
      for (var i = 0; i < vertices.length; i++) {
        final a = vertices[i], b = vertices[(i + 1) % vertices.length];
        if ((a.latitude > y) != (b.latitude > y)) {
          crossings.add(
            a.longitude +
                (y - a.latitude) *
                    (b.longitude - a.longitude) /
                    (b.latitude - a.latitude),
          );
        }
      }
      crossings.sort();
      for (var i = 0; i + 1 < crossings.length; i += 2) {
        final point = GeoPoint(y, (crossings[i] + crossings[i + 1]) / 2);
        if (covers(point)) return point;
      }
    }
    throw const FormatException('Unable to place a pin inside this outline.');
  }

  /// Spherical trapezoid integral, mean Earth radius 6371008.8 m.
  /// Approximate area, not a survey (ellipsoid difference about 1% or less).
  double get areaSquareMetres {
    const rad = math.pi / 180;
    var integral = 0.0;
    for (var i = 0; i < vertices.length; i++) {
      final a = vertices[i], b = vertices[(i + 1) % vertices.length];
      integral +=
          (b.longitude - a.longitude) *
          rad *
          (math.sin(a.latitude * rad) + math.sin(b.latitude * rad));
    }
    return (integral * 6371008.8 * 6371008.8 / 2).abs();
  }

  Map<String, dynamic> toJson() => {
    'type': 'Polygon',
    'coordinates': [
      [
        ...vertices,
        vertices.first,
      ].map((p) => [p.longitude, p.latitude]).toList(),
    ],
  };
  factory FarmBoundary.fromJson(Map<String, dynamic> json) {
    if (json['type'] != 'Polygon' ||
        (json['coordinates'] as List).length != 1) {
      throw const FormatException('Expected one exterior polygon ring.');
    }
    final ring = (json['coordinates'] as List).single as List;
    final points = ring
        .map(
          (v) => GeoPoint((v[1] as num).toDouble(), (v[0] as num).toDouble()),
        )
        .toList();
    if (points.length < 4 || points.first != points.last) {
      throw const FormatException('Boundary ring must be closed.');
    }
    return FarmBoundary(points.sublist(0, points.length - 1));
  }
}
