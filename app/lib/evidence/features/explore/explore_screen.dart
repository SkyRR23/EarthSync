import '../../app/ui_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../app/ui_copy.dart';
import '../../data/models/home_profile.dart';
import '../../design/components/product.dart';
import '../../state/home_provider.dart';
import '../../state/integration_provider.dart';
import '../dashboard/satellite_preview.dart';
import '../field/evidence_panels.dart';
import '../map/gibs_layer.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});
  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  bool _loadMap = false;
  @override
  Widget build(BuildContext context) {
    String tr(String k) => UiCopy.text(context, k);
    final profile = ref.watch(homeProfileProvider).value;
    final farm = profile?.farm;
    final area = profile?.userLocation;
    final areaPoint = area is ApproximateArea ? area.point : null;
    final point = areaPoint ?? farm?.point;
    return Scaffold(
      appBar: AppBar(title: Text(tr('explore'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              PageHeader(
                title: tr('satellite'),
                subtitle: tr('satelliteBody'),
                action: OutlinedButton.icon(
                  onPressed: () => context.push('/area'),
                  icon: const Icon(Icons.location_searching),
                  label: Text(tr('areaAction')),
                ),
              ),
              if (point == null)
                EvidenceNotice(
                  title: tr('noLocation'),
                  message: tr('discoverBody'),
                  icon: Icons.public,
                ),
              SectionCard(
                title: tr('explore'),
                icon: Icons.map_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        if (farm != null)
                          Text('● ${tr('point')} · ${farm.point.label}'),
                        if (areaPoint != null)
                          Text('◆ ${tr('areaPoint')} · ${areaPoint.label}'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(tr('mapPrivacy')),
                    if (!_loadMap)
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _loadMap = true),
                        icon: const Icon(Icons.map_outlined),
                        label: Text(tr('mapConsent')),
                      ),
                    if (_loadMap) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 360,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: FlutterMap(
                            key: ValueKey(
                              '${farm?.point.label}:${areaPoint?.label}',
                            ),
                            options: MapOptions(
                              initialCenter: LatLng(
                                point?.latitude ?? 0,
                                point?.longitude ?? 0,
                              ),
                              initialZoom: point == null ? 2 : 9,
                            ),
                            children: [
                              ...baseMapLayers(),
                              MarkerLayer(
                                markers: [
                                  if (farm != null)
                                    Marker(
                                      point: LatLng(
                                        farm.point.latitude,
                                        farm.point.longitude,
                                      ),
                                      child: Tooltip(
                                        message: tr('point'),
                                        child: const Icon(
                                          Icons.location_on,
                                          color: Color(0xFF173D30),
                                          size: 40,
                                        ),
                                      ),
                                    ),
                                  if (areaPoint != null)
                                    Marker(
                                      point: LatLng(
                                        areaPoint.latitude,
                                        areaPoint.longitude,
                                      ),
                                      child: Tooltip(
                                        message: tr('areaPoint'),
                                        child: const Icon(
                                          Icons.diamond,
                                          color: Color(0xFF4385A4),
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const RichAttributionWidget(
                                attributions: [
                                  TextSourceAttribution(
                                    UiLabels.openstreetmapContributors,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (point != null) SatellitePreview(point: point),
              if (farm != null)
                SatelliteEvidencePanel(
                  target: environmentalKey(farm.point, farmId: farm.id),
                ),
              const SourceNote(),
            ],
          ),
        ),
      ),
    );
  }
}
