import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../app/strings.dart';
import '../../data/models/field_analysis.dart';
import '../../design/components/buttons.dart';
import '../../design/components/pressable.dart';
import '../../design/components/segmented.dart';
import '../../design/tokens.dart';
import '../map/gibs_layer.dart';

/// Apple Maps-style: full-bleed map, floating glass controls, info pill.
class MapTab extends StatefulWidget {
  const MapTab({super.key, required this.analysis});
  final FieldAnalysis analysis;

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  bool _nasa = true;
  final _map = MapController();
  static const _cfg = GibsLayerConfig.provisional;
  static const _zoom = 8.0;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    final loc = widget.analysis.location;
    final pt = LatLng(loc.latitude, loc.longitude);

    return Scaffold(
      backgroundColor: p.background,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: pt,
              initialZoom: _zoom,
              maxZoom: 12,
            ),
            children: [
              // Street map underneath so missing satellite tiles never show a hole.
              streetTileLayer(),
              if (_nasa) gibsTileLayer(_cfg),
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
                      const SizedBox(width: FsSpace.sm),
                      Expanded(
                        child: _Glass(
                          child: Padding(
                            padding: const EdgeInsets.all(FsSpace.xs),
                            child: FsSegmented<bool>(
                              value: _nasa,
                              onChanged: (v) => setState(() => _nasa = v),
                              segments: const {
                                true: S.satellite,
                                false: S.street,
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: FsSpace.sm),
                      FsCircleButton(
                        icon: CupertinoIcons.location_fill,
                        tooltip: S.recenter,
                        onPressed: () => _map.move(pt, _zoom),
                      ),
                    ],
                  ),
                  const Spacer(),
                  FsPressable(
                    onTap: () => showImageryLegend(context, _cfg, _nasa),
                    semanticLabel: S.aboutImage,
                    scale: 0.98,
                    child: _Glass(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: FsSpace.lg,
                          vertical: FsSpace.md,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _nasa ? CupertinoIcons.photo : CupertinoIcons.map,
                              color: p.tint,
                              size: 22,
                            ),
                            const SizedBox(width: FsSpace.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _nasa ? 'NASA · ${_cfg.title}' : S.street,
                                    style: t.headline,
                                  ),
                                  Text(
                                    _nasa
                                        ? '${_cfg.dateLabel} · Visual only'
                                        : '© OpenStreetMap contributors',
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

/// Frosted floating surface.
class _Glass extends StatelessWidget {
  const _Glass({required this.child});
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
            color: p.surfaceRaised.withValues(alpha: 0.88),
            child: child,
          ),
        ),
      ),
    );
  }
}
