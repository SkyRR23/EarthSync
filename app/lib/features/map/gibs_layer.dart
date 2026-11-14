import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';

import '../../app/strings.dart';
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
  });

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

  String get urlTemplate =>
      'https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/$layerId/default/'
      '$dateString/$tileMatrixSet/{z}/{y}/{x}.$format';

  static const provisional = GibsLayerConfig(
    layerId: 'MODIS_Terra_CorrectedReflectance_TrueColor',
    title: 'MODIS Terra true colour',
    tileMatrixSet: 'GoogleMapsCompatible_Level9',
    format: 'jpg',
    maxNativeZoom: 9,
    legend:
        'True-colour satellite photo. Clouds appear white. Visual only — not used for calculations.',
  );
}

/// Base street map (for finding the field) + optional NASA overlay.
List<Widget> baseMapLayers() => [
  TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    userAgentPackageName: 'org.fieldshift.app',
    maxNativeZoom: 19,
  ),
];

Widget gibsTileLayer(GibsLayerConfig c, {double opacity = 1}) => Opacity(
  opacity: opacity,
  child: TileLayer(
    urlTemplate: c.urlTemplate,
    userAgentPackageName: 'org.fieldshift.app',
    maxNativeZoom: c.maxNativeZoom,
    errorTileCallback: (_, _, _) {},
  ),
);

/// Legend + date + source, always visible over the map.
class FsMapLegend extends StatelessWidget {
  const FsMapLegend({
    super.key,
    required this.config,
    required this.showingNasa,
  });
  final GibsLayerConfig config;
  final bool showingNasa;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FsSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.image_outlined,
                  color: FsColors.evidenceImagery,
                ),
                const SizedBox(width: FsSpace.sm),
                Expanded(child: Text(config.title, style: t.titleMedium)),
              ],
            ),
            const SizedBox(height: FsSpace.xs),
            Text('Date: ${config.dateString} (UTC)', style: t.bodyMedium),
            const SizedBox(height: FsSpace.xs),
            Text(config.legend, style: t.bodySmall),
            const SizedBox(height: FsSpace.xs),
            Text(
              '${S.imagery}: NASA GIBS / ${config.layerId}',
              style: t.bodySmall,
            ),
            if (!showingNasa)
              Text(
                'Street map: © OpenStreetMap contributors',
                style: t.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}
