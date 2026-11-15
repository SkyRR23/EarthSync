import 'package:flutter/material.dart';
import '../../data/models/home_profile.dart';
import '../map/gibs_layer.dart';

/// A point-centered NASA GIBS image; no street map presented as satellite data.
class SatellitePreview extends StatefulWidget {
  const SatellitePreview({super.key, required this.point});
  final GeoPoint point;
  @override
  State<SatellitePreview> createState() => _SatellitePreviewState();
}

class _SatellitePreviewState extends State<SatellitePreview> {
  late String date = GibsLayerConfig.provisional.dateString;
  int _retry = 0;
  @override
  void didUpdateWidget(covariant SatellitePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.point != widget.point) {
      date = GibsLayerConfig.provisional.dateString;
      ++_retry;
    }
  }

  GeoPoint get point => widget.point;
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
            TextButton.icon(
              icon: const Icon(Icons.calendar_today_outlined),
              label: const Text('Choose imagery date'),
              onPressed: () async {
                final selected = await showDatePicker(
                  context: context,
                  initialDate: DateTime.parse(date),
                  firstDate: DateTime(2000, 2, 24),
                  lastDate: DateTime.now().toUtc(),
                );
                if (mounted && selected != null) {
                  setState(
                    () => date = selected.toIso8601String().substring(0, 10),
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 2,
              child: Image.network(
                uri.toString(),
                key: ValueKey('${point.label}:$date:$_retry'),
                fit: BoxFit.contain,
                semanticLabel:
                    'NASA MODIS true-colour view around ${point.label}, requested date $date',
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const Center(child: Text('Loading satellite image…')),
                errorBuilder: (_, _, _) => Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.satellite_alt_outlined),
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                            'Satellite image unavailable. Coverage may be missing or the service may be offline.',
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            imageCache.evict(NetworkImage(uri.toString()));
                            setState(() => ++_retry);
                          },
                          child: const Text('Retry imagery'),
                        ),
                      ],
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
