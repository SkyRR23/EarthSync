import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../state/platform_provider.dart';
import '../../state/home_provider.dart';

class NdviScreen extends ConsumerWidget {
  const NdviScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final farm = ref.watch(platformFarmProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Satellite NDVI map')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1150),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const NdviPanel(),
              if (farm != null) ...[
                const SizedBox(height: 24),
                NdviPanel(key: ValueKey(farm.id), farmId: farm.id),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class NdviPanel extends ConsumerStatefulWidget {
  const NdviPanel({super.key, this.farmId});
  final String? farmId;
  @override
  ConsumerState<NdviPanel> createState() => _NdviPanelState();
}

class _NdviPanelState extends ConsumerState<NdviPanel> {
  final _map = MapController();
  Timer? _timer;
  Map<String, dynamic>? _snapshot, _pixel, _pointReading;
  Uint8List? _png;
  String? _error, _image;
  String _location = 'ames';
  bool _busy = false, _show = true;
  double _opacity = .75;
  int _revision = 0;

  String get _path =>
      '/api/platform/v1/${widget.farmId == null ? 'realtime/$_location' : 'farms/${widget.farmId}'}/ndvi-overlay';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(refresh: true));
  }

  @override
  void dispose() {
    _revision++;
    _timer?.cancel();
    _map.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    final client = ref.read(platformFarmClientProvider);
    if (client == null || _busy || !mounted) return;
    final revision = _revision;
    final path = _path;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (refresh) {
        await client.transport.request(
          'POST',
          '$path/refresh',
          expectedStatus: 202,
        );
      }
      final raw = Map<String, dynamic>.from(
        await client.transport.request('GET', path, expectedStatus: 200) as Map,
      );
      Map<String, dynamic>? pointReading;
      if (raw['data'] == null) {
        try {
          final pointPath = widget.farmId == null
              ? '/api/platform/v1/realtime/$_location'
              : '/api/platform/v1/farms/${widget.farmId}/realtime';
          final context =
              await client.transport.request(
                    'GET',
                    pointPath,
                    expectedStatus: 200,
                  )
                  as Map;
          final source = (context['sources'] as Map?)?['hls_ndvi'] as Map?;
          if (source?['data'] is Map &&
              (source!['data'] as Map)['value'] is num) {
            pointReading = Map<String, dynamic>.from(source);
          }
        } catch (_) {
          // A missing point reading does not prevent the map from opening.
        }
      }
      if (!mounted || revision != _revision) return;
      final image = (raw['data'] as Map?)?['png_base64'] as String?;
      setState(() {
        _snapshot = raw;
        _pointReading = pointReading;
        if (image != _image) {
          _image = image;
          _png = image == null ? null : base64Decode(image);
        }
      });
    } catch (_) {
      if (mounted && revision == _revision) {
        setState(
          () => _error =
              'Local NDVI service unavailable. Any displayed acquisition keeps its original timestamp.',
        );
      }
    } finally {
      if (mounted && revision == _revision) {
        setState(() => _busy = false);
        _timer?.cancel();
        _timer = Timer(
          Duration(seconds: _snapshot?['status'] == 'loading' ? 2 : 60),
          () => _load(),
        );
      }
    }
  }

  Future<void> _inspect(LatLng point) async {
    final client = ref.read(platformFarmClientProvider);
    if (client == null || _snapshot?['data'] == null) return;
    final revision = _revision;
    try {
      final raw =
          await client.transport.request(
                'GET',
                '$_path?lat=${point.latitude}&lon=${point.longitude}',
                expectedStatus: 200,
              )
              as Map;
      if (mounted && revision == _revision) {
        setState(() => _pixel = Map<String, dynamic>.from(raw['pixel'] as Map));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Pixel inspection unavailable. No value inferred.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _snapshot?['data'] as Map?;
    final bounds = data?['bounds'] as List?;
    final hasLayer = _png != null && bounds != null;
    final pointData = _pointReading?['data'] as Map?;
    final local = ref.watch(homeProfileProvider).value?.farm;
    final centre = widget.farmId == null
        ? switch (_location) {
            'crawfordsville' => const LatLng(41.2142, -91.5374),
            'davis' => const LatLng(38.5449, -121.7405),
            'yangon' => const LatLng(16.8661, 96.1951),
            'mandalay' => const LatLng(21.9588, 96.0891),
            _ => const LatLng(42.0308, -93.6319),
          }
        : LatLng(
            local?.point.latitude ?? 42.0308,
            local?.point.longitude ?? -93.6319,
          );
    final polygon = data?['geometry'] as Map?;
    final ring = polygon == null
        ? null
        : (polygon['coordinates'] as List).first as List;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.farmId == null
                  ? 'NASA vegetation index · public reference'
                  : 'NASA vegetation index · selected field',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'NDVI is a satellite measure of vegetation reflectance. When available, the coloured layer shows actual NASA HLS-VI pixels at 30 m resolution. It does not predict crop suitability, disease or yield.',
            ),
            const SizedBox(height: 16),
            if (widget.farmId == null)
              DropdownButtonFormField<String>(
                initialValue: _location,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Choose an area to explore',
                ),
                items: const [
                  DropdownMenuItem(value: 'ames', child: Text('Ames, Iowa')),
                  DropdownMenuItem(
                    value: 'crawfordsville',
                    child: Text('Crawfordsville, Iowa'),
                  ),
                  DropdownMenuItem(
                    value: 'davis',
                    child: Text('Davis, California'),
                  ),
                  DropdownMenuItem(
                    value: 'yangon',
                    child: Text('Yangon, Myanmar'),
                  ),
                  DropdownMenuItem(
                    value: 'mandalay',
                    child: Text('Mandalay, Myanmar'),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value == null) return;
                        _timer?.cancel();
                        setState(() {
                          _location = value;
                          _snapshot = null;
                          _png = null;
                          _image = null;
                          _pixel = null;
                          _pointReading = null;
                          _revision++;
                        });
                        _map.move(centreFor(value), 15);
                        _load(refresh: true);
                      },
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _load(refresh: true),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Check for satellite data'),
                ),
                if (bounds != null)
                  OutlinedButton.icon(
                    onPressed: () => _inspect(_map.camera.center),
                    icon: const Icon(Icons.my_location),
                    label: const Text('Inspect map centre'),
                  ),
                if (bounds != null)
                  TextButton(
                    onPressed: () => _map.fitCamera(
                      CameraFit.bounds(
                        bounds: LatLngBounds(
                          LatLng(
                            (bounds[1] as num).toDouble(),
                            (bounds[0] as num).toDouble(),
                          ),
                          LatLng(
                            (bounds[3] as num).toDouble(),
                            (bounds[2] as num).toDouble(),
                          ),
                        ),
                        padding: const EdgeInsets.all(24),
                      ),
                    ),
                    child: const Text('Fit acquisition'),
                  ),
              ],
            ),
            if (_busy || _snapshot?['status'] == 'loading') ...[
              const LinearProgressIndicator(
                semanticsLabel: 'Loading NASA NDVI',
              ),
              const Text('Checking a bounded native raster window…'),
            ],
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (data == null && !_busy)
              Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.satellite_alt_outlined),
                      const SizedBox(height: 8),
                      Text(
                        'Satellite layer unavailable',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _snapshot?['error'] == 'AUTHENTICATION_REQUIRED'
                            ? 'You’re seeing a street map, not an NDVI image. Earthdata authorization is not configured on this computer and no verified overlay is saved. You can still explore the map and use the rest of EarthSync.'
                            : 'No verified NDVI image is available for this area yet. You can still explore the street map. Try checking for satellite data again later.',
                      ),
                      if (_snapshot?['error'] != null &&
                          _snapshot?['error'] != 'AUTHENTICATION_REQUIRED')
                        Text('Source status: ${_snapshot!['error']}'),
                    ],
                  ),
                ),
              ),
            if (data == null && pointData != null) ...[
              Text(
                'Available point reading',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                'NDVI ${(pointData['value'] as num).toStringAsFixed(3)}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                '${_pointReading!['status'] == 'FRESH' ? 'Observed' : 'Saved earlier observation · stale'} · ${_date(pointData['acquired_start'])}',
              ),
              const Text(
                'One accepted 30 m satellite cell at the reference point. This is not a field average or a coloured map. More pixels are needed to show an overlay.',
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Point reading source'),
                children: [
                  SelectableText(
                    'NASA ${pointData['product']} v${pointData['version']}\nAcquired ${pointData['acquired_start']}\n${pointData['granule_id']}\n${pointData['qa_policy']}',
                  ),
                ],
              ),
            ],
            if (data != null) ...[
              Text(
                'Acquisition: ${data['acquired_at']} · age ${_snapshot?['data_age_days']} days',
              ),
              Text(
                '${data['provider']} · ${data['product']} v${data['version']} · ${data['resolution_m']} m native grid',
              ),
              Text(
                'Quality: ${data['quality']} · valid coverage ${data['coverage_pct']}% (${data['valid_pixels']}/${data['polygon_pixels']} cell centres)',
              ),
              Text(
                '${_snapshot?['stale'] == true ? 'STALE · ' : ''}Cached real acquisition · retrieved ${data['retrieved_at']}${_snapshot?['error'] == null ? '' : ' · latest check: ${_snapshot!['error']}'}',
              ),
              ExpansionTile(
                title: const Text('Source and quality policy'),
                children: [
                  SelectableText(
                    '${data['granule_id']}\n${data['qa_policy']}\n${data['coverage_definition']}\n${data['display_resampling']}',
                  ),
                ],
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show NDVI overlay'),
              subtitle: hasLayer
                  ? null
                  : const Text('Available when satellite pixels have loaded'),
              value: hasLayer && _show,
              onChanged: hasLayer ? (v) => setState(() => _show = v) : null,
            ),
            Row(
              children: [
                const Text('Layer opacity'),
                Expanded(
                  child: Slider(
                    value: _opacity,
                    divisions: 20,
                    label: '${(_opacity * 100).round()}%',
                    semanticFormatterCallback: (v) =>
                        '${(v * 100).round()} percent',
                    onChanged: hasLayer && _show
                        ? (v) => setState(() => _opacity = v)
                        : null,
                  ),
                ),
              ],
            ),
            Text(
              hasLayer && _show
                  ? 'NASA NDVI layer over street map · tap a coloured pixel for its value'
                  : 'Street map only · no NDVI colours displayed',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 390,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: centre,
                    initialZoom: 15,
                    minZoom: 3,
                    maxZoom: 20,
                    onTap: (_, point) => _inspect(point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'org.earthsync.app',
                      maxNativeZoom: 19,
                    ),
                    if (_show && _png != null && bounds != null)
                      OverlayImageLayer(
                        overlayImages: [
                          OverlayImage(
                            bounds: LatLngBounds(
                              LatLng(
                                (bounds[1] as num).toDouble(),
                                (bounds[0] as num).toDouble(),
                              ),
                              LatLng(
                                (bounds[3] as num).toDouble(),
                                (bounds[2] as num).toDouble(),
                              ),
                            ),
                            imageProvider: MemoryImage(_png!),
                            opacity: _opacity,
                          ),
                        ],
                      ),
                    if (ring != null)
                      PolygonLayer(
                        polygons: [
                          Polygon(
                            points: [
                              for (final p in ring)
                                LatLng(
                                  (p[1] as num).toDouble(),
                                  (p[0] as num).toDouble(),
                                ),
                            ],
                            color: Colors.transparent,
                            borderColor: const Color(0xFF173D30),
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),
                    if (widget.farmId != null && local?.boundary != null)
                      PolygonLayer(
                        polygons: [
                          Polygon(
                            points: local!.boundary!.vertices
                                .map((p) => LatLng(p.latitude, p.longitude))
                                .toList(),
                            color: Colors.transparent,
                            borderColor: Theme.of(context).colorScheme.primary,
                            borderStrokeWidth: 3,
                          ),
                        ],
                      ),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: ColoredBox(
                        color: Theme.of(context).colorScheme.surface,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Text(
                            '© OpenStreetMap contributors · NASA HLS-VI',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (hasLayer) const _NdviLegend(),
            if (hasLayer)
              const Text(
                'Cloud, shadow, snow, high aerosol, nodata and cells outside the polygon are transparent. Tap the map to inspect an original native value.',
              ),
            if (_pixel != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _pixel!['value'] == null
                      ? 'Pixel: ${_pixel!['status']} · no accepted NDVI value'
                      : 'NDVI ${(_pixel!['value'] as num).toStringAsFixed(4)} · raw ${_pixel!['raw_value']} × 0.0001 · Fmask ${_pixel!['qa_value']} · native row ${_pixel!['row']}, column ${_pixel!['column']} · ${_pixel!['acquired_at']}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toUtc();
    if (date == null) return 'acquisition date unavailable';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year} UTC';
  }

  LatLng centreFor(String location) => switch (location) {
    'crawfordsville' => const LatLng(41.2142, -91.5374),
    'davis' => const LatLng(38.5449, -121.7405),
    'yangon' => const LatLng(16.8661, 96.1951),
    'mandalay' => const LatLng(21.9588, 96.0891),
    _ => const LatLng(42.0308, -93.6319),
  };
}

class _NdviLegend extends StatelessWidget {
  const _NdviLegend();
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('NDVI · dimensionless numerical scale'),
      Container(
        height: 16,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            stops: [0, .5, .625, .75, .875, 1],
            colors: [
              Color(0xFF784825),
              Color(0xFFB8632D),
              Color(0xFFE1AD3C),
              Color(0xFFD5DA5F),
              Color(0xFF5E9D40),
              Color(0xFF146337),
            ],
          ),
        ),
      ),
      const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text('−1'), Text('0'), Text('+1')],
      ),
    ],
  );
}
