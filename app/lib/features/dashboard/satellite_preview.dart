import 'package:flutter/material.dart';
import '../../data/models/home_profile.dart';
import '../map/gibs_layer.dart';

/// A point-centered NASA GIBS image; no street map presented as satellite data.
class SatellitePreview extends StatelessWidget {
  SatellitePreview({super.key, required this.point})
    : date = GibsLayerConfig.provisional.dateString;
  final GeoPoint point;
  final String date;
  @override
  Widget build(BuildContext context) {
    final layer = GibsLayerConfig.provisional;
    // Shift the view at poles/dateline to keep a valid, non-wrapping WMS box.
    final south = (point.latitude - .7).clamp(-90.0, 88.6);
    final west = (point.longitude - 1.0).clamp(-180.0, 178.0);
    final uri =
        Uri.https('gibs.earthdata.nasa.gov', '/wms/epsg4326/best/wms.cgi', {
          'SERVICE': 'WMS',
          'REQUEST': 'GetMap',
          'VERSION': '1.3.0',
          'LAYERS': layer.layerId,
          'STYLES': '',
          'FORMAT': 'image/jpeg',
          'CRS': 'EPSG:4326',
          'BBOX': '$south,$west,${south + 1.4},${west + 2}',
          'WIDTH': '768',
          'HEIGHT': '384',
          'TIME': date,
        });
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Satellite view',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text('NASA GIBS · ${layer.title}'),
            Text('Requested image date: $date (UTC) · provisional layer'),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 2,
              child: Image.network(
                uri.toString(),
                fit: BoxFit.contain,
                semanticLabel:
                    'NASA MODIS true-colour view around ${point.label}, requested date $date',
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const Center(child: Text('Loading satellite image…')),
                errorBuilder: (_, _, _) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Satellite image unavailable. Coverage may be missing or the service may be offline.',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'View near ${point.label} · approximately 2° longitude × 1.4° latitude. No field boundary.',
            ),
            const Text(
              'Clouds, blank pixels and delayed coverage may hide the ground. The requested date does not guarantee a usable image. Visual context only; not used in crop calculations.',
            ),
          ],
        ),
      ),
    );
  }
}
