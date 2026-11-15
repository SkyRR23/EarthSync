import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../data/models/home_profile.dart';
import '../map/gibs_layer.dart';

/// Each map retains its explicit requested date. No acquisition date is inferred.
class HistoricalFarmMap extends StatelessWidget {
  const HistoricalFarmMap({
    super.key,
    required this.farm,
    required this.offline,
    required this.opacity,
    this.imagery,
    this.soil,
  });
  final ConfirmedFarm farm;
  final bool offline;
  final double opacity;
  final Map<String, dynamic>? imagery;
  final Map? soil;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (imagery != null)
        Text(
          'Requested image: ${imagery!['requested_date']} · acquisition time unknown',
        ),
      SizedBox(
        height: 320,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: LatLng(farm.point.latitude, farm.point.longitude),
            initialZoom: 10,
          ),
          children: [
            if (!offline) ...baseMapLayers(),
            if (!offline && imagery?['tile_url'] != null)
              Opacity(
                opacity: opacity,
                child: TileLayer(
                  key: ValueKey(imagery!['requested_date']),
                  urlTemplate: imagery!['tile_url'] as String,
                  maxNativeZoom: 9,
                  userAgentPackageName: 'org.fieldshift.app',
                ),
              ),
            if (soil != null)
              PolygonLayer(
                polygons: [
                  for (final c in soil!['cells'] as List)
                    if (c['value'] != null)
                      Polygon(
                        points: [
                          for (final p
                              in c['geometry']['coordinates'][0] as List)
                            LatLng(
                              (p[1] as num).toDouble(),
                              (p[0] as num).toDouble(),
                            ),
                        ],
                        color: Colors.purple.withValues(alpha: opacity * .4),
                        borderColor: Colors.purple,
                        borderStrokeWidth: .3,
                      ),
                ],
              ),
            if (farm.boundary != null)
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: [
                      for (final p in farm.boundary!.vertices)
                        LatLng(p.latitude, p.longitude),
                    ],
                    color: Colors.transparent,
                    borderColor: Colors.orange,
                    borderStrokeWidth: 3,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(farm.point.latitude, farm.point.longitude),
                  child: const Icon(Icons.location_on, color: Colors.orange),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}
