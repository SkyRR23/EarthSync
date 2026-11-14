import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// The farmer's whole farm, marked with 4 corner pins (OpenFarm-style field
/// boundary, rebuilt natively). Only plain geometry lives here: the farm's
/// centre and size. All climate and crop analysis stays in the Rust engine,
/// which receives the farm centre as the field location.
class FarmBoundary {
  FarmBoundary(List<LatLng> corners) : corners = orderCorners(corners);

  static const cornerCount = 4;
  static const _earthRadiusM = 6371008.8;
  static const _m2PerAcre = 4046.8564224;

  /// Corners in drawing order (sorted around the middle, so the shape never
  /// crosses itself even if the farmer tapped the corners out of order).
  final List<LatLng> corners;

  bool get isComplete => corners.length == cornerCount;

  /// Puts points in order around their middle point.
  static List<LatLng> orderCorners(List<LatLng> pts) {
    if (pts.length < 3) return List.unmodifiable(pts);
    final lat0 =
        pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length;
    final lon0 =
        pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
    final k = math.cos(lat0 * math.pi / 180);
    final sorted = [...pts]
      ..sort((a, b) {
        final ta = math.atan2(a.latitude - lat0, (a.longitude - lon0) * k);
        final tb = math.atan2(b.latitude - lat0, (b.longitude - lon0) * k);
        return ta.compareTo(tb);
      });
    return List.unmodifiable(sorted);
  }

  /// Local flat projection around the corners' mean (metres). Accurate
  /// enough for a farm a few hundred metres wide.
  ({LatLng origin, List<math.Point<double>> xy}) _project() {
    final lat0 =
        corners.map((p) => p.latitude).reduce((a, b) => a + b) / corners.length;
    final lon0 =
        corners.map((p) => p.longitude).reduce((a, b) => a + b) /
        corners.length;
    final mPerDeg = _earthRadiusM * math.pi / 180;
    final k = math.cos(lat0 * math.pi / 180);
    return (
      origin: LatLng(lat0, lon0),
      xy: [
        for (final p in corners)
          math.Point(
            (p.longitude - lon0) * k * mPerDeg,
            (p.latitude - lat0) * mPerDeg,
          ),
      ],
    );
  }

  double _signedArea(List<math.Point<double>> xy) {
    var s = 0.0;
    for (var i = 0; i < xy.length; i++) {
      final a = xy[i];
      final b = xy[(i + 1) % xy.length];
      s += a.x * b.y - b.x * a.y;
    }
    return s / 2;
  }

  /// Farm size in square metres (0 until there are 3+ corners).
  double get areaM2 {
    if (corners.length < 3) return 0;
    return _signedArea(_project().xy).abs();
  }

  double get areaAcres => areaM2 / _m2PerAcre;
  double get areaHectares => areaM2 / 10000;

  /// Centre of the farm shape. This is the location the engine uses.
  LatLng get center {
    if (corners.isEmpty) throw StateError('No corners');
    final (:origin, :xy) = _project();
    final a = _signedArea(xy);
    if (corners.length < 3 || a.abs() < 1e-6) return origin;
    var cx = 0.0, cy = 0.0;
    for (var i = 0; i < xy.length; i++) {
      final p = xy[i];
      final q = xy[(i + 1) % xy.length];
      final f = p.x * q.y - q.x * p.y;
      cx += (p.x + q.x) * f;
      cy += (p.y + q.y) * f;
    }
    cx /= 6 * a;
    cy /= 6 * a;
    final mPerDeg = _earthRadiusM * math.pi / 180;
    final k = math.cos(origin.latitude * math.pi / 180);
    return LatLng(
      origin.latitude + cy / mPerDeg,
      origin.longitude + cx / (k * mPerDeg),
    );
  }

  List<List<double>> toJson() => [
    for (final c in corners) [c.latitude, c.longitude],
  ];

  static FarmBoundary? fromJson(Object? raw) {
    if (raw is! List || raw.length != cornerCount) return null;
    try {
      return FarmBoundary([
        for (final c in raw)
          LatLng(((c as List)[0] as num).toDouble(), (c[1] as num).toDouble()),
      ]);
    } catch (_) {
      return null;
    }
  }
}

/// "About 2.4 acres" — farmers in Myanmar talk in acres.
String farmSizeLabel(FarmBoundary b) {
  final acres = b.areaAcres;
  final v = acres < 10 ? acres.toStringAsFixed(1) : acres.round().toString();
  return 'About $v acres';
}
