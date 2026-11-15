import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../state/providers.dart';

/// ISRIC's display service, not sampled values or a soil-health calculation.
class SoilReferencePage extends ConsumerStatefulWidget {
  const SoilReferencePage({super.key});
  @override
  ConsumerState<SoilReferencePage> createState() => _SoilReferenceState();
}

class _SoilReferenceState extends ConsumerState<SoilReferencePage> {
  String _property = 'phh2o';
  bool _failed = false;
  double _opacity = .65;
  static const _properties = {
    'phh2o': 'Soil acidity (pH)',
    'clay': 'Clay content',
    'sand': 'Sand content',
  };
  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(farmerDraftProvider);
    final lat = draft.fieldLatitude, lon = draft.fieldLongitude;
    final layer = '${_property}_0-5cm_mean';
    final endpoint = 'https://maps.isric.org/mapserv/$_property';
    final legend = Uri.parse(endpoint).replace(queryParameters: {
      'SERVICE': 'WMS', 'VERSION': '1.1.1', 'REQUEST': 'GetLegendGraphic',
      'FORMAT': 'image/png', 'LAYER': layer,
    });
    return Scaffold(
      appBar: AppBar(title: const Text('Soil reference layers')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Regional soil estimates · not real time', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Text('SoilGrids 2.0 models the top 0–5 cm of soil at about 250 m resolution. A small field may occupy only part of one cell. These maps do not establish current moisture, fertility or crop suitability.'),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [for (final entry in _properties.entries)
          ChoiceChip(label: Text(entry.value), selected: _property == entry.key, onSelected: (_) => setState(() { _property = entry.key; _failed = false; })),
        ]),
        if (lat == null || lon == null) const Text('Choose your field first to centre this map.'),
        if (lat != null && lon != null) SizedBox(height: 360, child: FlutterMap(
          options: MapOptions(initialCenter: LatLng(lat, lon), initialZoom: 12, maxZoom: 17),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'org.earthsync.farmer'),
            if (!_failed) Opacity(opacity: _opacity, child: TileLayer(
              key: ValueKey(_property),
              wmsOptions: WMSTileLayerOptions(baseUrl: '$endpoint?', layers: [layer], format: 'image/png', transparent: true, version: '1.1.1'),
              userAgentPackageName: 'org.earthsync.farmer',
              errorTileCallback: (_, _, _) {
                if (mounted && !_failed) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() => _failed = true); });
              },
            )),
            if (draft.hasFarm) PolygonLayer(polygons: [Polygon(points: draft.farm!.corners, color: Colors.transparent, borderColor: Colors.blueGrey, borderStrokeWidth: 3)]),
            MarkerLayer(markers: [Marker(point: LatLng(lat, lon), child: const Icon(Icons.location_on, color: Colors.blueGrey, size: 32))]),
            const RichAttributionWidget(attributions: [TextSourceAttribution('ISRIC SoilGrids · CC BY 4.0'), TextSourceAttribution('OpenStreetMap contributors')]),
          ],
        )),
        if (_failed) ...[
          const Text('The soil map service did not return its tiles. Only the street map and field outline are shown; no soil values have been substituted.'),
          TextButton(onPressed: () => setState(() => _failed = false), child: const Text('Retry soil layer')),
        ],
        const Text('Layer visibility'),
        Slider(value: _opacity, onChanged: (value) => setState(() => _opacity = value)),
        const Text('Original provider colour legend'),
        Image.network(legend.toString(), alignment: Alignment.centerLeft, errorBuilder: (_, _, _) => const Text('Provider legend unavailable. Do not interpret map colours without a legend.')),
        Text(_property == 'phh2o' ? 'Provider pH values are scaled ×10: divide legend values by 10 to read pH.' : 'Provider legend units: g/kg (100 g/kg = 10% by mass).'),
        const SizedBox(height: 12),
        const Text('Colours describe a modeled property, not good or bad soil. Display tiles are not laboratory samples or numerical field measurements. Blank areas remain unknown.'),
        const SelectableText('Source: https://maps.isric.org/soilgrids.html\nModel edition: SoilGrids 2.0; no current observation date is claimed.'),
      ])),
    );
  }
}
