import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../app/strings.dart';
import '../../design/components/buttons.dart';
import '../../design/components/pressable.dart';
import '../../design/components/segmented.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';
import '../home/field_tab.dart' show farmOutlineLayer;
import 'gibs_layer.dart';

enum MapLayerKind { street, plantHealth }

GibsLayerConfig? configFor(MapLayerKind k) => switch (k) {
  MapLayerKind.plantHealth => GibsLayerConfig.plantHealth,
  MapLayerKind.street => null,
};

/// Full-screen farm map: street map, or NASA plant health over it.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key, this.plantHealth = false});
  final bool plantHealth;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  late MapLayerKind _layer = widget.plantHealth
      ? MapLayerKind.plantHealth
      : MapLayerKind.street;
  final _map = MapController();
  static const _zoom = 15.0;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    final d = ref.watch(farmerDraftProvider);
    final pt = LatLng(
      d.fieldLatitude ?? kSampleLat,
      d.fieldLongitude ?? kSampleLon,
    );
    final farm = d.hasFarm ? d.farm! : null;
    final cfg = configFor(_layer);
    final fit = farm == null
        ? null
        : CameraFit.coordinates(
            coordinates: farm.corners,
            padding: const EdgeInsets.all(72),
            maxZoom: 18,
          );

    return Scaffold(
      backgroundColor: p.background,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: pt,
              initialZoom: _zoom,
              initialCameraFit: fit,
              maxZoom: 19,
            ),
            children: [
              // Street map underneath so a missing satellite tile is never a hole.
              streetTileLayer(),
              if (cfg != null)
                Opacity(opacity: 0.75, child: gibsTileLayer(cfg)),
              if (farm != null) farmOutlineLayer(context, farm),
              if (farm == null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: pt,
                      width: 44,
                      height: 44,
                      child: fieldMarker(context),
                    ),
                  ],
                ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(FsSpace.md),
              child: Column(
                children: [
                  Row(
                    children: [
                      FsCircleButton(
                        icon: CupertinoIcons.chevron_back,
                        tooltip: S.back,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const Spacer(),
                      FsCircleButton(
                        icon: CupertinoIcons.location_fill,
                        tooltip: S.recenter,
                        onPressed: () => fit != null
                            ? _map.fitCamera(fit)
                            : _map.move(pt, _zoom),
                      ),
                    ],
                  ),
                  const SizedBox(height: FsSpace.sm),
                  MapGlass(
                    child: Padding(
                      padding: const EdgeInsets.all(FsSpace.xs),
                      child: FsSegmented<MapLayerKind>(
                        value: _layer,
                        onChanged: (v) => setState(() => _layer = v),
                        segments: const {
                          MapLayerKind.street: S.street,
                          MapLayerKind.plantHealth: S.plantHealth,
                        },
                      ),
                    ),
                  ),
                  const Spacer(),
                  FsPressable(
                    onTap: () => showImageryLegend(context, cfg),
                    semanticLabel: S.aboutImage,
                    scale: 0.98,
                    child: MapGlass(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: FsSpace.lg,
                          vertical: FsSpace.md,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        cfg == null
                                            ? S.street
                                            : 'NASA · ${cfg.dateLabel}',
                                        style: t.headline,
                                      ),
                                      Text(
                                        cfg == null
                                            ? '© OpenStreetMap contributors'
                                            : '${cfg.legend} ${S.pixelNote}',
                                        style: t.footnote,
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  CupertinoIcons.info_circle,
                                  color: p.secondaryLabel,
                                  size: 20,
                                ),
                              ],
                            ),
                            if (_layer == MapLayerKind.plantHealth) ...[
                              const SizedBox(height: FsSpace.md),
                              const PlantHealthLegend(),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Frosted floating surface used over maps.
class MapGlass extends StatelessWidget {
  const MapGlass({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FsRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FsRadius.lg),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: ColoredBox(
            color: p.surfaceRaised.withValues(alpha: 0.9),
            child: child,
          ),
        ),
      ),
    );
  }
}
