import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../app/strings.dart';
import '../../data/models/farm_boundary.dart';
import '../../design/components/buttons.dart';
import '../../design/components/page.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';
import '../location/gps.dart';
import '../map/gibs_layer.dart';
import '../map/map_screen.dart' show MapGlass;

/// Mark the whole farm with 4 corner pins (OpenFarm-style field boundary).
/// Walk to each corner and use GPS, or tap the map. After saving, every
/// result is calculated for this farm (its centre goes to the engine).
class MarkFarmScreen extends ConsumerStatefulWidget {
  const MarkFarmScreen({super.key});

  @override
  ConsumerState<MarkFarmScreen> createState() => _MarkFarmScreenState();
}

class _MarkFarmScreenState extends ConsumerState<MarkFarmScreen> {
  final _map = MapController();
  late final List<LatLng> _corners = [
    ...?ref.read(farmerDraftProvider).farm?.corners,
  ];
  bool _locating = false;
  String? _message;

  bool get _full => _corners.length == FarmBoundary.cornerCount;

  /// Farthest a corner may be from the others (a big Myanmar farm is well
  /// under 1 km across; 2 km catches GPS from somewhere else).
  static const _maxSpreadKm = 2.0;

  void _add(LatLng p) {
    if (_full) return;
    const dist = Distance();
    final far = _corners
        .map((c) => dist.as(LengthUnit.Meter, c, p) / 1000)
        .fold<double>(0, (a, b) => a > b ? a : b);
    if (far > _maxSpreadKm) {
      setState(
        () => _message = S.cornerTooFar(far.toStringAsFixed(far < 10 ? 1 : 0)),
      );
      return;
    }
    setState(() {
      _corners.add(p);
      _message = null;
    });
  }

  Future<void> _gpsCorner() async {
    setState(() {
      _locating = true;
      _message = null;
    });
    final r = await readGps();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _message = r.message;
    });
    if (r.point != null) {
      _add(r.point!);
      _map.move(r.point!, 18);
    }
  }

  void _save() {
    final farm = FarmBoundary(_corners);
    ref.read(farmerDraftProvider.notifier).setFarm(farm);
    ref
        .read(analysisProvider.notifier)
        .run(ref.read(farmerDraftProvider).toInput());
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text(S.farmSaved)));
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    final d = ref.watch(farmerDraftProvider);
    final start = _corners.isNotEmpty
        ? _corners.last
        : LatLng(d.fieldLatitude ?? kSampleLat, d.fieldLongitude ?? kSampleLon);
    final shape = FarmBoundary.orderCorners(_corners);
    final preview = _corners.length >= 3 ? FarmBoundary(_corners) : null;

    return Scaffold(
      backgroundColor: p.background,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: start,
              initialZoom: 17,
              maxZoom: 19,
              onTap: (_, pt) => _add(pt),
            ),
            children: [
              streetTileLayer(),
              if (shape.length >= 3)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: shape,
                      color: p.tint.withValues(alpha: 0.22),
                      borderColor: p.tint,
                      borderStrokeWidth: 3,
                    ),
                  ],
                )
              else if (shape.length == 2)
                PolylineLayer(
                  polylines: [
                    Polyline(points: shape, color: p.tint, strokeWidth: 3),
                  ],
                ),
              MarkerLayer(
                markers: [
                  for (final (i, c) in _corners.indexed)
                    Marker(
                      point: c,
                      width: 40,
                      height: 40,
                      child: _CornerPin(i + 1),
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
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(FsSpace.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FsCircleButton(
                    icon: CupertinoIcons.xmark,
                    tooltip: S.cancel,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: FsSpace.sm),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: MapGlass(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: FsSpace.lg,
                            vertical: FsSpace.md,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _full
                                    ? S.allCorners
                                    : S.cornerOf(_corners.length + 1),
                                style: t.title3,
                              ),
                              const SizedBox(height: FsSpace.xxs),
                              Text(
                                _full && preview != null
                                    ? farmSizeLabel(preview)
                                    : S.cornerHint,
                                style: t.subhead,
                              ),
                            ],
                          ),
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
      bottomNavigationBar: FsBottomBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: FsSpace.md),
                child: Text(
                  _message!,
                  style: t.footnote.copyWith(color: p.cautionText),
                ),
              ),
            if (_full)
              FsButton(
                S.saveFarm,
                icon: CupertinoIcons.checkmark_alt,
                onPressed: _save,
              )
            else
              FsButton(
                _locating ? S.findingYou : S.atCorner,
                icon: CupertinoIcons.location_fill,
                loading: _locating,
                onPressed: _gpsCorner,
              ),
            const SizedBox(height: FsSpace.xs),
            Row(
              children: [
                Expanded(
                  child: FsButton(
                    S.undo,
                    kind: FsButtonKind.plain,
                    icon: CupertinoIcons.arrow_uturn_left,
                    onPressed: _corners.isEmpty
                        ? null
                        : () => setState(_corners.removeLast),
                  ),
                ),
                Expanded(
                  child: FsButton(
                    S.clear,
                    kind: FsButtonKind.plain,
                    onPressed: _corners.isEmpty
                        ? null
                        : () => setState(_corners.clear),
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

/// Numbered corner pin.
class _CornerPin extends StatelessWidget {
  const _CornerPin(this.n);
  final int n;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    return Semantics(
      label: 'Corner $n',
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.tint,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          '$n',
          style: context.type.headline.copyWith(color: p.onTint),
        ),
      ),
    );
  }
}
