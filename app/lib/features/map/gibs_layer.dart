import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';

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
  String get dateLabel => DateFormat.yMMMd().format(date);

  String get urlTemplate =>
      'https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/$layerId/default/'
      '$dateString/$tileMatrixSet/{z}/{y}/{x}.$format';

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
