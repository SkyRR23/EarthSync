import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../data/platform_farms.dart';
import '../../design/components/product.dart';
import '../../state/home_provider.dart';
import '../../state/platform_provider.dart';
import '../map/gibs_layer.dart';

/// Explicit requests only. Source snapshots keep their original dates offline.
class GeospatialIntelligencePanel extends ConsumerStatefulWidget {
  const GeospatialIntelligencePanel({
    super.key,
    required this.farm,
    this.onSaved,
  });
  final PlatformFarm farm;
  final VoidCallback? onSaved;
  @override
  ConsumerState<GeospatialIntelligencePanel> createState() => _PanelState();
}

class _PanelState extends ConsumerState<GeospatialIntelligencePanel> {
  List<Map<String, dynamic>> _saved = [];
  bool _busy = false;
  String? _error;
  String? _soilId, _forecastId;
  double _opacity = .65;
  bool _showSoil = true, _loadMap = false;
  DateTime _opticalEnd = DateTime.now().toUtc();
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final saved = await ref
          .read(platformFarmClientProvider)!
          .intelligence(widget.farm.id);
      if (mounted) setState(() => _saved = saved);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Saved source snapshots unavailable: $e');
      }
    }
  }

  Future<void> _retrieve(String kind) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client = ref.read(platformFarmClientProvider)!;
      var job = kind == 'optical'
          ? await client.discoverOptical(widget.farm.id, _opticalEnd)
          : await client.retrieveIntelligence(kind, widget.farm);
      for (var attempt = 0; attempt < 125 && mounted; attempt++) {
        if (job['status'] != 'queued' && job['status'] != 'running') break;
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        job = await client.job(job['id'] as String);
      }
      if (!mounted) return;
      if (job['status'] != 'succeeded') {
        setState(
          () => _error =
              'Source retrieval ${job['status']}: ${job['error'] ?? 'Still processing; reload saved snapshots shortly.'}. No substitute values supplied.',
        );
      }
      await _load();
      widget.onSaved?.call();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'Source unavailable: $e. Saved snapshots retain their original times.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Map<String, dynamic>> _kind(String kind) => _saved
      .where((j) => j['kind'] == kind && j['status'] == 'succeeded')
      .toList();
  Map<String, dynamic>? _selected(List<Map<String, dynamic>> jobs, String? id) {
    for (final j in jobs) {
      if (j['id'] == id) return Map<String, dynamic>.from(j['result'] as Map);
    }
    return jobs.isEmpty
        ? null
        : Map<String, dynamic>.from(jobs.first['result'] as Map);
  }

  Widget _history(
    List<Map<String, dynamic>> jobs,
    String? id,
    ValueChanged<String?> select,
    String label,
  ) => DropdownButtonFormField<String>(
    key: ValueKey('$label:${jobs.map((j) => j['id']).join()}:$id'),
    initialValue: jobs.any((j) => j['id'] == id)
        ? id
        : jobs.first['id'] as String,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: jobs
        .map(
          (j) => DropdownMenuItem(
            value: j['id'] as String,
            child: Text(
              '${j['result']['retrieved_at'] ?? 'Saved discovery'} · saved snapshot',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList(),
    onChanged: select,
  );
  @override
  Widget build(BuildContext context) {
    final soils = _kind('soil_map'), forecasts = _kind('forecast');
    final soil = _selected(soils, _soilId),
        forecast = _selected(forecasts, _forecastId);
    final optical = _kind('optical_discovery');
    return SectionCard(
      title: 'Farm map & environmental snapshots',
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'These saved snapshots are retrieved on demand. Real-time EarthSync separately monitors current sources while the local backend runs. Map tiles and new retrievals require a connection.',
            ),
            TextButton.icon(
              onPressed: () => context.push('/realtime?field=1'),
              icon: const Icon(Icons.update),
              label: const Text('Open monitoring for the selected field'),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: _busy ? null : () => _retrieve('soil-map'),
                  child: const Text('Retrieve SoilGrids pH map'),
                ),
                FilledButton.tonal(
                  onPressed: _busy ? null : () => _retrieve('forecast'),
                  child: const Text('Retrieve NOAA temperature forecast'),
                ),
                TextButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('Reload saved snapshots'),
                ),
              ],
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (soil == null)
              const Text(
                'Soil pH map: no accepted saved pixels yet. Missing data never becomes zero.',
              ),
            if (soil != null) ...[
              _history(
                soils,
                _soilId,
                (v) => setState(() => _soilId = v),
                'Soil source snapshot',
              ),
              Text(
                '${soil['provider']} · ${soil['dataset']} · mean pH in water · ${soil['depth_cm']} cm · ${soil['resolution_m']} m modeled grid',
              ),
              Text(
                'Original retrieval: ${soil['retrieved_at']} · ${soil['cache_hit'] == true ? 'reused source cache' : 'source capture'}',
              ),
              const Text(
                'Uncertainty: prediction intervals unavailable. This is a modeled estimate, not a laboratory result, field average or crop suitability.',
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show pH raster cells'),
                value: _showSoil,
                onChanged: (v) => setState(() => _showSoil = v),
              ),
              Row(
                children: [
                  const Text('Overlay opacity'),
                  Expanded(
                    child: Slider(
                      value: _opacity,
                      label: '${(_opacity * 100).round()}%',
                      onChanged: (v) => setState(() => _opacity = v),
                    ),
                  ),
                ],
              ),
              const Text(
                'pH legend (property scale, no suitability thresholds): 0–4 purple · 4–6 blue · 6–8 teal · 8–10 amber · 10–14 red. Nodata is transparent.',
              ),
            ],
            OutlinedButton(
              onPressed: () => setState(() => _loadMap = !_loadMap),
              child: Text(
                _loadMap ? 'Hide source map' : 'Open source map (online tiles)',
              ),
            ),
            if (_loadMap) _soilMap(soil),
            if (soil != null)
              ExpansionTile(
                title: const Text('Raw pH cells and processing provenance'),
                children: [
                  for (final cell in soil['cells'] as List)
                    Text(
                      'Row ${cell['row']}, column ${cell['column']}${cell['at_query_point'] == true ? ' · query point' : ''}: raw ${cell['raw'] ?? 'nodata'} → ${cell['value'] ?? 'missing'} pH',
                    ),
                  SelectableText(
                    const JsonEncoder.withIndent('  ').convert({
                      for (final e in soil.entries)
                        if (e.key != 'cells') e.key: e.value,
                    }),
                  ),
                ],
              ),
            const Divider(),
            const Text(
              'Weather & risk awareness',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (forecast == null)
              const Text(
                'No saved forecast. Observed current weather and official alerts are unavailable. NASA POWER remains historical climate only.',
              ),
            if (forecast != null) ...[
              _history(
                forecasts,
                _forecastId,
                (v) => setState(() => _forecastId = v),
                'Forecast source snapshot',
              ),
              Text(
                '${forecast['provider']} · ${forecast['grid_spacing_degrees']}° model grid · UTC · ${forecast['unit']}',
              ),
              Text(
                'Model initialized: ${forecast['model_initialized_at']}\nRetrieved: ${forecast['retrieved_at']}\nPublication/issuance time: unavailable. Forecast reference time is model initialization.',
              ),
              Text(
                DateTime.now()
                            .toUtc()
                            .difference(
                              DateTime.parse(
                                forecast['retrieved_at'] as String,
                              ),
                            )
                            .inMinutes >=
                        30
                    ? 'STALE saved forecast: retrieve a new snapshot. Values below retain original valid times.'
                    : 'Saved forecast snapshot; no automatic updates.',
              ),
              for (final r in forecast['records'] as List)
                Text(
                  '${r['valid_at']} · ${r['temperature_c'] == null ? 'missing' : (r['temperature_c'] as num).toStringAsFixed(1)} °C · ${r['forecast_hour'] == 0 ? 'model analysis, not current observation' : 'forecast'}',
                ),
              const Text(
                'This saved temperature snapshot does not contain official warnings or observed weather. Open Real-time EarthSync for separately dated station, forecast and alert sources. No crop-specific storm or dry-spell risk is inferred.',
              ),
              for (final r in forecast['derived_indicators'] as List)
                Text(
                  'Derived forecast condition · ${r['name']}: ${r['value'] == null
                      ? 'unavailable'
                      : r['value'] == true
                      ? 'present in sampled times'
                      : 'not present in sampled times'}. ${r['basis']}. Sparse samples do not rule out cold between valid times; no crop injury inferred.',
                ),
              ExpansionTile(
                title: const Text('Forecast source and processing details'),
                children: [
                  SelectableText(
                    const JsonEncoder.withIndent('  ').convert(forecast),
                  ),
                ],
              ),
            ],
            const Divider(),
            const Text(
              'NASA satellite vegetation',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text(
              'NDVI overlay unavailable in this saved-snapshot panel. Real-time EarthSync separately reads authorized, quality-controlled HLS-VI point pixels when available. Metadata discovery and NASA GIBS true color do not establish numeric NDVI.',
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _opticalEnd,
                        firstDate: DateTime.utc(2015),
                        lastDate: DateTime.now().toUtc(),
                      );
                      if (picked != null && mounted) {
                        setState(
                          () => _opticalEnd = DateTime.utc(
                            picked.year,
                            picked.month,
                            picked.day,
                            23,
                            59,
                          ),
                        );
                      }
                    },
              child: Text(
                'NASA discovery end date: ${_opticalEnd.toIso8601String().substring(0, 10)} · 30-day window',
              ),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _retrieve('optical'),
              child: const Text('Find NASA HLS metadata (not NDVI pixels)'),
            ),
            if (optical.isNotEmpty) ...[
              Text(
                'Last discovery: ${optical.first['result']['status']} · ${optical.first['result']['retrieved_at']}',
              ),
              for (final r in (optical.first['result']['records'] as List))
                Text(
                  '${r['acquired_at']} · ${r['granule_id']} · metadata only; not numeric NDVI',
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _soilMap(Map<String, dynamic>? soil) {
    final farm = ref.watch(homeProfileProvider).value?.farm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 350,
          child: FlutterMap(
            key: ValueKey('soil:${soil?['source_sha256']}'),
            options: MapOptions(
              initialCenter: LatLng(
                widget.farm.point.latitude,
                widget.farm.point.longitude,
              ),
              initialZoom: 14,
            ),
            children: [
              ...baseMapLayers(),
              if (_showSoil && soil != null)
                PolygonLayer(
                  polygons: [
                    for (final cell in soil['cells'] as List)
                      if (cell['value'] != null)
                        Polygon(
                          points: [
                            for (final p
                                in cell['geometry']['coordinates'][0] as List)
                              LatLng(
                                (p[1] as num).toDouble(),
                                (p[0] as num).toDouble(),
                              ),
                          ],
                          color: _phColor(
                            cell['value'] as num,
                          ).withValues(alpha: _opacity),
                          borderStrokeWidth: .5,
                          borderColor: Colors.black26,
                        ),
                  ],
                ),
              if (farm?.boundary != null)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: farm!.boundary!.vertices
                          .map((p) => LatLng(p.latitude, p.longitude))
                          .toList(),
                      color: Colors.transparent,
                      borderColor: Colors.black,
                      borderStrokeWidth: 3,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(
                      widget.farm.point.latitude,
                      widget.farm.point.longitude,
                    ),
                    child: const Icon(Icons.location_on, color: Colors.red),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Text(
          '© OpenStreetMap contributors · soil overlay: ISRIC SoilGrids, CC BY 4.0. Transparent pixels are nodata or outside the bounded extract.',
        ),
      ],
    );
  }

  Color _phColor(num value) => value < 4
      ? Colors.purple
      : value < 6
      ? Colors.blue
      : value < 8
      ? Colors.teal
      : value < 10
      ? Colors.amber
      : Colors.red;
}
