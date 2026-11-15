import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../app/strings.dart';
import '../../design/components/grouped.dart';
import '../../design/components/sheet.dart';
import '../../design/tokens.dart';

/// GIBS layer settings. PROVISIONAL until P2 confirms the layer (plan §09).
/// Verified 2026-11-14: this layer returns tiles over Myanmar.
class GibsLayerConfig {
  const GibsLayerConfig({
    required this.layerId,
    required this.title,
    required this.tileMatrixSet,
    required this.format,
    required this.maxNativeZoom,
    required this.legend,
    this.dateLagDays = 2,
    this.latest = false,
  });

  /// Ask GIBS for its newest image (`default` time) instead of a fixed lag.
  /// The real date comes back in the `layer-time-actual` header.
  final bool latest;

  final String layerId;
  final String title;
  final String tileMatrixSet;
  final String format;
  final int maxNativeZoom;
  final String legend;

  /// Daily imagery appears with a delay; show the image from N days ago.
  final int dateLagDays;

  DateTime get date =>
      DateTime.now().toUtc().subtract(Duration(days: dateLagDays));
  String get dateString => DateFormat('yyyy-MM-dd').format(date);
  String get dateLabel => DateFormat.yMMMd().format(date);

  String get urlTemplate =>
      'https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/$layerId/default/'
      '${latest ? 'default' : dateString}/$tileMatrixSet/{z}/{y}/{x}.$format';

  /// URL of the one tile that covers [at] at zoom [z].
  String tileUrlAt(LatLng at, [int z = 9]) {
    final n = 1 << z;
    final x = ((at.longitude + 180) / 360 * n).floor();
    final lat = at.latitude * math.pi / 180;
    final y =
        ((1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * n)
            .floor();
    return urlTemplate
        .replaceFirst('{z}', '$z')
        .replaceFirst('{y}', '$y')
        .replaceFirst('{x}', '$x');
  }

  static const provisional = GibsLayerConfig(
    layerId: 'MODIS_Terra_CorrectedReflectance_TrueColor',
    title: 'MODIS Terra true colour',
    tileMatrixSet: 'GoogleMapsCompatible_Level9',
    format: 'jpg',
    maxNativeZoom: 9,
    legend: 'True-colour satellite photo. Clouds appear white.',
  );

  /// NASA plant-health (NDVI) layer — the NASA-data version of OpenFarm's
  /// vegetation tab. 8-day composite, so it lags; verified 2026-11-14.
  static const plantHealth = GibsLayerConfig(
    layerId: 'MODIS_Terra_NDVI_8Day',
    title: 'MODIS Terra plant health (NDVI, 8-day)',
    tileMatrixSet: 'GoogleMapsCompatible_Level9',
    format: 'png',
    maxNativeZoom: 9,
    legend:
        'Greener means more growing plants. Brown means bare ground or dry plants.',
    dateLagDays: 10,
    latest: true,
  );
}

/// Simple colour scale for the plant-health layer.
class PlantHealthLegend extends StatelessWidget {
  const PlantHealthLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return Semantics(
      label:
          'Colour scale: brown is ${S.lessGreen}, dark green is ${S.moreGreen}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 10,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFB08A5A),
                  Color(0xFFE6D58A),
                  Color(0xFF9CCB5B),
                  Color(0xFF3E8E2E),
                  Color(0xFF0F4D1C),
                ],
              ),
            ),
          ),
          const SizedBox(height: FsSpace.xs),
          Row(
            children: [
              Text(S.lessGreen, style: t.caption),
              const Spacer(),
              Text(S.moreGreen, style: t.caption),
            ],
          ),
        ],
      ),
    );
  }
}

const _userAgent = 'org.fieldshift.app';

/// Street base map (for finding the field and filling satellite gaps).
Widget streetTileLayer() => TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: _userAgent,
  maxNativeZoom: 19,
);

/// Satellite photo base map (Esri World Imagery; credit "Esri" on screen).
/// The picture's date varies by place; it shows the land, not crop health.
Widget satelliteTileLayer() => TileLayer(
  urlTemplate:
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
  userAgentPackageName: _userAgent,
  maxNativeZoom: 17, // Esri often has no tiles above 17 in rural Myanmar
  // Show tiles as soon as they arrive: a fade-in can stall on maps that
  // start inside animated or hidden parents.
  tileDisplay: const TileDisplay.instantaneous(),
  errorTileCallback: (_, _, _) {},
);

const satelliteCredit = 'Imagery © Esri';

/// flutter_map paints the first tiles only after the camera moves; a map
/// that just fitted itself has not moved yet. A tiny zoom change (invisible)
/// right after the first frame makes the tiles appear.
void nudgeMap(MapController map) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    try {
      final c = map.camera;
      map.move(c.center, c.zoom - 0.001);
    } catch (_) {
      // Map gone or not laid out: nothing to do.
    }
  });
}

Widget gibsTileLayer(GibsLayerConfig c) => TileLayer(
  urlTemplate: c.urlTemplate,
  userAgentPackageName: _userAgent,
  maxNativeZoom: c.maxNativeZoom,
  errorTileCallback: (_, _, _) {},
);

/// Field pin in the accent colour with a soft halo.
Widget fieldMarker(BuildContext context) {
  final p = context.fs;
  return Stack(
    alignment: Alignment.center,
    children: [
      Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: p.tint.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
      ),
      Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: p.tint,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    ],
  );
}

void showImageryLegend(BuildContext context, GibsLayerConfig? c) {
  showFsSheet<void>(
    context,
    title: S.aboutImage,
    builder: (ctx) => FsGroupedSection(
      footer: S.imageryNote,
      children: [
        if (c != null) ...[
          FsListRow(
            leading: Icon(CupertinoIcons.photo, color: ctx.fs.tint),
            title: c.title,
            subtitle: c.legend,
          ),
          if (c.layerId == GibsLayerConfig.plantHealth.layerId)
            const Padding(
              padding: EdgeInsets.all(FsSpace.lg),
              child: PlantHealthLegend(),
            ),
          FsListRow(title: 'Date', value: '${c.dateLabel} (UTC)'),
          FsListRow(title: 'Source', subtitle: 'NASA GIBS · ${c.layerId}'),
        ],
        const FsListRow(
          title: 'Street map',
          subtitle: '© OpenStreetMap contributors',
        ),
      ],
    ),
  );
}

/// The real date of the newest image GIBS serves for [at] (one tile request).
Future<DateTime?> fetchLatestGibsDate(GibsLayerConfig c, LatLng at) async {
  try {
    final r = await http
        .get(Uri.parse(c.tileUrlAt(at)))
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) return null;
    return DateTime.tryParse(r.headers['layer-time-actual'] ?? '');
  } catch (_) {
    return null;
  }
}

/// Date of the newest NASA plant-health image at a farm (null = unknown).
final plantHealthDateProvider = FutureProvider.family<DateTime?, LatLng>(
  (ref, at) => fetchLatestGibsDate(GibsLayerConfig.plantHealth, at),
);

/// "NASA 8-day image, newest: 13 Nov 2026".
String plantHealthDateLabel(DateTime? d) => d == null
    ? S.plantHealthNewest
    : '${S.plantHealthNewest}: ${DateFormat('d MMM y').format(d.toUtc())}';

/// Shows [child] (a map layer) only inside [corners] — used to colour plant
/// health inside the farm border and nowhere else.
class ClipToPolygon extends StatelessWidget {
  const ClipToPolygon({super.key, required this.corners, required this.child});
  final List<LatLng> corners;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final pts = [for (final c in corners) camera.latLngToScreenOffset(c)];
    return ClipPath(clipper: _PolygonClipper(pts), child: child);
  }
}

class _PolygonClipper extends CustomClipper<Path> {
  _PolygonClipper(this.points);
  final List<Offset> points;

  @override
  Path getClip(Size size) => Path()..addPolygon(points, true);

  @override
  bool shouldReclip(_PolygonClipper old) {
    if (old.points.length != points.length) return true;
    for (var i = 0; i < points.length; i++) {
      if (old.points[i] != points[i]) return true;
    }
    return false;
  }
}

/// NASA plant health: inside the farm border only when a farm is marked.
Widget plantHealthLayer({List<LatLng>? farmCorners}) {
  final layer = Opacity(
    opacity: 0.85,
    child: gibsTileLayer(GibsLayerConfig.plantHealth),
  );
  return farmCorners == null || farmCorners.length < 3
      ? layer
      : ClipToPolygon(corners: farmCorners, child: layer);
}
