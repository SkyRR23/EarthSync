import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../app/strings.dart';
import '../../design/components/buttons.dart';
import '../../design/components/page.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';
import '../map/gibs_layer.dart';

/// Rough Myanmar bounding box, only for a friendly warning.
bool _inMyanmar(LatLng p) =>
    p.latitude >= 9.5 &&
    p.latitude <= 28.6 &&
    p.longitude >= 92.1 &&
    p.longitude <= 101.2;

/// Full-bleed map with a floating title and a bottom action panel.
class LocationScreen extends ConsumerStatefulWidget {
  const LocationScreen({super.key, this.editing = false});
  final bool editing;

  @override
  ConsumerState<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends ConsumerState<LocationScreen> {
  final _map = MapController();

  void _useSample() {
    ref.read(farmerDraftProvider.notifier).setLocation(kSampleLat, kSampleLon);
    _map.move(const LatLng(kSampleLat, kSampleLon), 10);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    final draft = ref.watch(farmerDraftProvider);
    final picked = draft.hasLocation
        ? LatLng(draft.latitude!, draft.longitude!)
        : null;

    return Scaffold(
      backgroundColor: p.background,
      appBar: CupertinoNavigationBar(
        middle: const Text(S.locationTitle),
        previousPageTitle: S.back,
        backgroundColor: p.barBackground,
        border: Border(bottom: BorderSide(color: p.separator, width: 0.5)),
        transitionBetweenRoutes: false,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: picked ?? const LatLng(kSampleLat, kSampleLon),
              initialZoom: 9,
              onTap: (_, pt) => ref
                  .read(farmerDraftProvider.notifier)
                  .setLocation(pt.latitude, pt.longitude),
            ),
            children: [
              streetTileLayer(),
              if (picked != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: picked,
                      width: 44,
                      height: 44,
                      child: fieldMarker(context),
                    ),
                  ],
                ),
              const RichAttributionWidget(
                alignment: AttributionAlignment.bottomLeft,
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
          if (picked == null)
            Positioned(
              top: FsSpace.md,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FsSpace.lg,
                    vertical: FsSpace.sm + 2,
                  ),
                  decoration: BoxDecoration(
                    color: p.surfaceRaised.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(FsRadius.capsule),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.map_pin_ellipse,
                        size: 18,
                        color: p.tint,
                      ),
                      const SizedBox(width: FsSpace.sm),
                      Text(S.locationHint, style: t.subhead),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: FsBottomBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedSwitcher(
              duration: FsMotion.of(context, FsMotion.normal),
              child: picked == null
                  ? const SizedBox(key: ValueKey('none'), height: 0)
                  : Padding(
                      key: const ValueKey('picked'),
                      padding: const EdgeInsets.only(bottom: FsSpace.md),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.checkmark_circle_fill,
                            color: p.tint,
                            size: 22,
                          ),
                          const SizedBox(width: FsSpace.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(S.fieldMarked, style: t.headline),
                                Text(
                                  '${picked.latitude.toStringAsFixed(4)}, '
                                  '${picked.longitude.toStringAsFixed(4)}',
                                  style: t.footnote,
                                ),
                                if (!_inMyanmar(picked))
                                  Text(
                                    S.outsideMyanmar,
                                    style: t.footnote.copyWith(
                                      color: p.cautionText,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            Row(
              children: [
                Expanded(
                  child: FsButton(
                    S.useSampleField,
                    kind: FsButtonKind.tinted,
                    onPressed: _useSample,
                  ),
                ),
                const SizedBox(width: FsSpace.sm),
                Expanded(
                  child: FsButton(
                    widget.editing ? S.done : S.continueLabel,
                    onPressed: picked == null
                        ? null
                        : () => widget.editing
                              ? context.pop()
                              : context.push('/question/1'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
