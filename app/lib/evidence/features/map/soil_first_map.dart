import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../data/models/home_profile.dart';
import '../../data/environment/soil_property_layer.dart';
import '../../design/tokens.dart';
import '../../state/journal_provider.dart';
import '../../state/platform_provider.dart';
import 'gibs_layer.dart';
import 'ndvi_panel.dart';

Color soilPhColor(num value) {
  const scale = [
    Color(0xFFBD3D32),
    Color(0xFFD9802B),
    Color(0xFFE4CB50),
    Color(0xFFA6CB69),
    Color(0xFF368152),
  ];
  final position = (value.toDouble().clamp(0, 14) / 14) * (scale.length - 1);
  final low = position.floor();
  return Color.lerp(
    scale[low],
    scale[low == scale.length - 1 ? low : low + 1],
    position - low,
  )!;
}

class SoilFirstMap extends ConsumerStatefulWidget {
  const SoilFirstMap({super.key, required this.farm, this.compact = false});
  final ConfirmedFarm farm;
  final bool compact;
  @override
  ConsumerState<SoilFirstMap> createState() => _SoilMapState();
}

class _SoilMapState extends ConsumerState<SoilFirstMap> {
  String _mode = 'soil', _interpretation = 'property';
  double _opacity = .6;
  bool _boundary = true;
  bool _tilesFailed = false;
  final _crop = TextEditingController();
  @override
  void dispose() {
    _crop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(journalProvider).value;
    final linked = ref.watch(platformFarmProvider).value;
    Map<String, dynamic>? soil;
    for (final job
        in snapshot?.rows('intelligence') ?? <Map<String, dynamic>>[]) {
      if (job['kind'] == 'soil_map' &&
          job['status'] == 'succeeded' &&
          job['result'] is Map) {
        soil = validatedSoilLayer(
          Map<String, dynamic>.from(job['result'] as Map),
          widget.farm.point,
        );
        if (soil != null) break;
      }
    }
    final cells = soil?['cells'] as List? ?? [];
    final property = _interpretation == 'property';
    final farm = widget.farm;
    final boundary = [
      for (final p in farm.boundary?.vertices ?? <GeoPoint>[])
        LatLng(p.latitude, p.longitude),
    ];
    final requested = DateTime.now().toUtc().subtract(const Duration(days: 2));
    final gibs = GibsLayerConfig.provisional;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(FsSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Your soil, in context',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                TextButton.icon(
                  onPressed: () => context.push('/sources'),
                  icon: const Icon(Icons.info_outline),
                  label: const Text('Sources & Evidence'),
                ),
              ],
            ),
            const Text(
              'Modeled soil properties are separate from crop suitability.',
            ),
            const SizedBox(height: FsSpace.sm),
            Wrap(
              spacing: FsSpace.sm,
              children: [
                for (final mode in const {
                  'soil': 'Soil properties',
                  'standard': 'Street map',
                  'satellite': 'NASA true color',
                  'vegetation': 'Vegetation / NDVI',
                }.entries)
                  ChoiceChip(
                    label: Text(mode.value),
                    selected: _mode == mode.key,
                    onSelected: (_) => setState(() {
                      _mode = mode.key;
                      _tilesFailed = false;
                    }),
                  ),
              ],
            ),
            if (_mode == 'vegetation') ...[
              const Text(
                'Vegetation greenness is not soil fertility or crop health. Original NASA dates, QA masks and nodata are retained.',
              ),
              if (linked == null)
                const Padding(
                  padding: EdgeInsets.all(FsSpace.lg),
                  child: Text(
                    'Connect this confirmed field to retrieve its NASA pixels. No substitute location is used.',
                  ),
                )
              else
                NdviPanel(
                  key: ValueKey('soil-first-ndvi:${linked.id}'),
                  farmId: linked.id,
                ),
            ] else ...[
              if (_mode == 'soil')
                Wrap(
                  spacing: FsSpace.sm,
                  children: [
                    ChoiceChip(
                      label: const Text('Raw pH'),
                      selected: property,
                      onSelected: (_) =>
                          setState(() => _interpretation = 'property'),
                    ),
                    ChoiceChip(
                      label: const Text('Selected crop context'),
                      selected: !property,
                      onSelected: (_) =>
                          setState(() => _interpretation = 'crop'),
                    ),
                  ],
                ),
              if (_mode == 'soil' && !property) ...[
                TextField(
                  controller: _crop,
                  maxLength: 150,
                  decoration: const InputDecoration(
                    labelText: 'Crop to consider',
                    hintText: 'Enter your crop for this field',
                  ),
                ),
                const Text(
                  'Suitability not yet determined. All 60 candidate crop rules remain blocked. Reviewed crop requirements, field measurements and applicability are needed. Gray means unknown.',
                ),
              ],
              const SizedBox(height: FsSpace.sm),
              ClipRRect(
                borderRadius: const BorderRadius.all(FsRadius.md),
                child: SizedBox(
                  height: widget.compact ? 220 : 360,
                  child: FlutterMap(
                    key: ValueKey('${farm.id}:${farm.confirmedAt}:$_mode'),
                    options: MapOptions(
                      initialCenter: LatLng(
                        farm.point.latitude,
                        farm.point.longitude,
                      ),
                      initialZoom: 14,
                      onTap: (_, _) => showModalBottomSheet<void>(
                        context: context,
                        builder: (_) => SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(FsSpace.lg),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  farm.name ?? 'My Farm',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                Text(
                                  'Farmer-confirmed point: ${farm.point.label}',
                                ),
                                Text(
                                  farm.boundary == null
                                      ? 'No boundary saved. Area unknown.'
                                      : 'Boundary saved on this device. Area is approximate.',
                                ),
                                Text(
                                  soil == null
                                      ? 'Soil properties are unavailable.'
                                      : '${soil['provider']} · ${soil['depth_cm']} cm depth · ${soil['resolution_m']} m modeled grid',
                                ),
                                FilledButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    context.push('/field');
                                  },
                                  child: const Text('Open field details'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'org.earthsync.farmer',
                        errorTileCallback: (_, _, _) {
                          if (mounted && !_tilesFailed) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) setState(() => _tilesFailed = true);
                            });
                          }
                        },
                      ),
                      if (_mode == 'satellite')
                        gibsTileLayer(gibs, opacity: _opacity),
                      if (_mode == 'soil' && property && soil != null)
                        PolygonLayer(
                          polygons: [
                            for (final cell in cells)
                              Polygon(
                                points: [
                                  for (final p
                                      in cell['geometry']['coordinates'][0]
                                          as List)
                                    LatLng(
                                      (p[1] as num).toDouble(),
                                      (p[0] as num).toDouble(),
                                    ),
                                ],
                                color:
                                    (cell['value'] == null
                                            ? FsColors.unknown
                                            : soilPhColor(cell['value'] as num))
                                        .withValues(alpha: _opacity),
                                borderStrokeWidth: .2,
                                borderColor: scheme.outline,
                              ),
                          ],
                        ),
                      if (_boundary && boundary.isNotEmpty)
                        PolygonLayer(
                          polygons: [
                            Polygon(
                              points: boundary,
                              color:
                                  _mode == 'soil' && (soil == null || !property)
                                  ? FsColors.unknown.withValues(alpha: .25)
                                  : Colors.transparent,
                              borderColor: scheme.primary,
                              borderStrokeWidth: 3,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(
                              farm.point.latitude,
                              farm.point.longitude,
                            ),
                            child: Icon(
                              Icons.location_on,
                              color: scheme.primary,
                              size: 38,
                            ),
                          ),
                        ],
                      ),
                      const RichAttributionWidget(
                        attributions: [
                          TextSourceAttribution('OpenStreetMap contributors'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (_tilesFailed)
                const Text(
                  'Map tiles could not be loaded. Your field boundary remains saved; uncached tiles need internet.',
                ),
              if (_mode == 'satellite')
                Text(
                  'NASA GIBS display imagery · requested ${calendarDate(requested)}. A requested date does not prove a pixel acquisition on that date.',
                ),
              if (_mode == 'soil') ...[
                if (soil == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: FsSpace.sm),
                    child: Text(
                      'No accepted soil extract saved for this field. Retrieve a bounded SoilGrids extract or add a farmer soil check. Missing data is unknown.',
                    ),
                  ),
                if (soil != null && property) ...[
                  Text(
                    'pH in water · ${soil['depth_cm']} cm · ${soil['resolution_m']} m modeled grid',
                  ),
                  Text(
                    '${soil['provider']} · retrieved ${soil['retrieved_at']}${snapshot?.cached == true ? ' · saved copy, may be stale' : ''}',
                  ),
                  Container(
                    height: 14,
                    margin: const EdgeInsets.symmetric(vertical: FsSpace.sm),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          for (final n in [0, 3.5, 7, 10.5, 14]) soilPhColor(n),
                        ],
                      ),
                    ),
                  ),
                  const Text(
                    '0     3.5     7     10.5     14 pH · Gray: missing\nColor represents pH only. Green is a higher pH value, not a better soil score.',
                  ),
                ],
                if (!widget.compact && soil != null && property)
                  Row(
                    children: [
                      const Text('Layer opacity'),
                      Expanded(
                        child: Slider(
                          value: _opacity,
                          label: '${(_opacity * 100).round()}%',
                          onChanged: (v) => setState(() => _opacity = v),
                        ),
                      ),
                    ],
                  ),
                if (!widget.compact)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show farm boundary'),
                    value: _boundary,
                    onChanged: (v) => setState(() => _boundary = v),
                  ),
                Wrap(
                  spacing: FsSpace.sm,
                  children: [
                    OutlinedButton(
                      onPressed: () =>
                          context.push('/local-records?kind=soil_test'),
                      child: const Text('Add soil check'),
                    ),
                    OutlinedButton(
                      onPressed: () => context.push('/farm-evidence'),
                      child: const Text('Retrieve source data'),
                    ),
                  ],
                ),
              ],
              if (!widget.compact && _mode == 'satellite')
                Row(
                  children: [
                    const Text('Imagery opacity'),
                    Expanded(
                      child: Slider(
                        value: _opacity,
                        label: '${(_opacity * 100).round()}%',
                        onChanged: (v) => setState(() => _opacity = v),
                      ),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}

String calendarDate(DateTime date) => date.toIso8601String().substring(0, 10);
