import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../app/strings.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';
import '../map/gibs_layer.dart';

/// Rough Myanmar bounding box, only for a friendly warning.
bool _inMyanmar(LatLng p) =>
    p.latitude >= 9.5 &&
    p.latitude <= 28.6 &&
    p.longitude >= 92.1 &&
    p.longitude <= 101.2;

class LocationScreen extends ConsumerWidget {
  const LocationScreen({super.key, this.editing = false});
  final bool editing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(farmerDraftProvider);
    final notifier = ref.read(farmerDraftProvider.notifier);
    final picked = draft.hasLocation
        ? LatLng(draft.latitude!, draft.longitude!)
        : null;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: FsSpace.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(S.locationTitle, style: t.headlineMedium),
                  const SizedBox(height: FsSpace.xs),
                  Text(S.locationHint, style: t.bodyLarge),
                  const SizedBox(height: FsSpace.md),
                ],
              ),
            ),
            Expanded(
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: picked ?? const LatLng(kSampleLat, kSampleLon),
                  initialZoom: 9,
                  onTap: (_, p) =>
                      notifier.setLocation(p.latitude, p.longitude),
                ),
                children: [
                  ...baseMapLayers(),
                  if (picked != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: picked,
                          width: 48,
                          height: 48,
                          alignment: Alignment.topCenter,
                          child: const Icon(
                            Icons.location_on,
                            size: 48,
                            color: FsColors.riskHigh,
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
            Padding(
              padding: const EdgeInsets.all(FsSpace.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (picked != null) ...[
                    Text(
                      'Field: ${picked.latitude.toStringAsFixed(4)}, ${picked.longitude.toStringAsFixed(4)}',
                      style: t.bodyMedium,
                    ),
                    if (!_inMyanmar(picked))
                      Text(
                        S.outsideMyanmar,
                        style: t.bodyMedium?.copyWith(
                          color: FsColors.constrained,
                        ),
                      ),
                    const SizedBox(height: FsSpace.sm),
                  ],
                  OutlinedButton.icon(
                    onPressed: () =>
                        notifier.setLocation(kSampleLat, kSampleLon),
                    icon: const Icon(Icons.agriculture),
                    label: const Text(S.useSampleField),
                  ),
                  const SizedBox(height: FsSpace.sm),
                  FilledButton(
                    onPressed: picked == null
                        ? null
                        : () => editing
                              ? context.pop()
                              : context.push('/question/1'),
                    child: Text(editing ? S.done : S.next),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
