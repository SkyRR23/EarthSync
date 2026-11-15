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
  Map<String, dynamic>? _snapshot, _pixel;
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
      if (!mounted || revision != _revision) return;
      final image = (raw['data'] as Map?)?['png_base64'] as String?;
      setState(() {
        _snapshot = raw;
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
              'Actual HLS-VI v2 native 30 m NDVI. Colours describe the numerical index, not crop suitability, disease, yield or a field average.',
            ),
            const SizedBox(height: 16),
            if (widget.farmId == null)
              DropdownButtonFormField<String>(
                initialValue: _location,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Public demo viewport',
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
                  label: const Text('Check NASA acquisition'),
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
            if (data == null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _snapshot?['error'] == 'AUTHENTICATION_REQUIRED'
                      ? 'NASA raster unavailable: Earthdata authorization is not configured. No verified overlay is cached yet. The rest of EarthSync remains available.'
                      : 'No verified NDVI overlay is available${_snapshot?['error'] == null ? ' yet' : ': ${_snapshot!['error']}'}. Missing pixels are never replaced.',
                ),
              ),
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
              value: _show,
              onChanged: (v) => setState(() => _show = v),
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
                    onChanged: (v) => setState(() => _opacity = v),
                  ),
                ),
              ],
            ),
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
                    const SimpleAttributionWidget(
                      source: Text(
                        '© OpenStreetMap contributors · NASA HLS-VI',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const _NdviLegend(),
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
