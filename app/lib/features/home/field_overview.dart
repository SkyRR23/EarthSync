import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../app/strings.dart';
import '../../data/models/farm_boundary.dart';
import '../../design/components/buttons.dart';
import '../../design/components/earth.dart';
import '../../design/components/page.dart' show FsBackArrow;
import '../../design/components/pressable.dart';
import '../../design/tokens.dart';
import '../../data/environment/greenness.dart';
import '../../state/today.dart';
import '../today/farm_tasks.dart' show shortDate;
import '../../state/providers.dart';
import '../map/gibs_layer.dart';
import 'home_shell.dart';
import 'home_tab.dart' show cropName, fieldStatus;
import 'task_cards.dart';

/// Field tab (team design): satellite map of the farm with its border
/// coloured by status, plant health on the map, and a card for the field.
class FieldTab extends ConsumerStatefulWidget {
  const FieldTab({super.key, this.now});
  final DateTime? now;

  @override
  ConsumerState<FieldTab> createState() => _FieldTabState();
}

class _FieldTabState extends ConsumerState<FieldTab> {
  final _map = MapController();
  bool _plantHealth = false;
  int? _shownTab;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The map may get ready while this tab is hidden; nudge it each time
    // the Field tab is opened so its tiles are drawn.
    final tab = HomeTabs.of(context)?.current;
    if (tab == 2 && _shownTab != 2) nudgeMap(_map);
    _shownTab = tab;
  }

  void _showFarm(FarmBoundary? farm, LatLng pin) {
    try {
      if (farm != null) {
        _map.fitCamera(
          CameraFit.coordinates(
            coordinates: farm.corners,
            padding: const EdgeInsets.all(48),
            maxZoom: 17,
          ),
        );
      } else {
        _map.move(pin, 16);
      }
    } catch (_) {
      // Map not laid out yet.
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(farmerDraftProvider);
    if (!d.hasLocation) return const NoFarmView();
    final p = context.fs;
    final t = context.type;
    final tabs = HomeTabs.of(context);
    final farm = d.hasFarm ? d.farm! : null;
    final pin = LatLng(d.fieldLatitude!, d.fieldLongitude!);
    final tasks = watchTasks(ref, widget.now ?? DateTime.now());
    final (statusText, tone) = fieldStatus(tasks);
    final look = tone == FsPillTone.look;
    final line = !kIsWeb ? const Color(0xFF90A4AE) : look ? const Color(0xFFF2B233) : const Color(0xFF7EE07A);
    final crop = cropName(d);
    final health = _plantHealth && farm != null;
    // NASA HLS (30 m) greenness inside the border; MODIS (250 m) when HLS
    // has no clear image or cannot be read.
    final green = health ? (kIsWeb ? ref.watch(greennessProvider) : const AsyncValue<FarmGreenness?>.data(null)) : null;
    final scene = green?.value?.latest;
    final hls = scene != null && scene.cells.isNotEmpty;
    final modis = health && kIsWeb
        ? '${plantHealthDateLabel(ref.watch(plantHealthDateProvider(farm.center)).value)}. ${S.insideFarmOnly} ${S.pixelNote}'
        : null;
    final caption = !kIsWeb
        ? 'Satellite imagery is unavailable in the offline simulation. No dated field image is bundled. The outline marks your field, not its health.'
        : farm == null
        ? S.markFarmForHealth
        : !health
        ? null
        : hls
        ? greenCaption(green!.value!)
        : green!.isLoading
        ? S.greenLoading
        : green.hasError
        ? (kIsWeb ? '${S.greenFailed} $modis' : 'No accepted vegetation image is available. The outline only marks your field; it does not show crop health.')
        : (kIsWeb ? '${S.greenNone} $modis' : 'No accepted vegetation image is available for this field.');

    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: FsSpace.maxContent),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    FsSpace.xs,
                    FsSpace.sm,
                    FsSpace.gutter,
                    0,
                  ),
                  child: Row(
                    children: [
                      FsBackArrow(onTap: () => tabs?.go(0)),
                      const SizedBox(width: FsSpace.xs),
                      Expanded(
                        child: Text(
                          S.yourFieldsTitle,
                          style: t.title1.copyWith(fontSize: 26),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: FsSpace.sm),
                  child: Center(
                    child: FsLocationChip(
                      label: S.myFarm,
                      onTap: () => context.push('/field-details'),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      FsSpace.gutter,
                      FsSpace.md,
                      FsSpace.gutter,
                      0,
                    ),
                    child: FsEntrance(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(FsRadius.xl),
                          boxShadow: FsShadow.card(p),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            FlutterMap(
                              mapController: _map,
                              options: MapOptions(
                                // Draw the first tiles (see nudgeMap).
                                onMapReady: () => nudgeMap(_map),
                                initialCenter: pin,
                                initialZoom: 16,
                                initialCameraFit: farm == null
                                    ? null
                                    : CameraFit.coordinates(
                                        coordinates: farm.corners,
                                        padding: const EdgeInsets.all(48),
                                        maxZoom: 17,
                                      ),
                                interactionOptions: const InteractionOptions(
                                  flags:
                                      InteractiveFlag.all &
                                      ~InteractiveFlag.rotate,
                                ),
                                backgroundColor: const Color(0xFF4F6B3A),
                              ),
                              children: [
                                satelliteTileLayer(),
                                if (health && (kIsWeb || hls))
                                  hls
                                      ? PolygonLayer(
                                          polygons: [
                                            for (final c in scene.cells)
                                              Polygon(
                                                points: c.corners,
                                                color: ndviColor(c.ndvi),
                                                borderColor: const Color(
                                                  0x33FFFFFF,
                                                ),
                                                borderStrokeWidth: 0.5,
                                              ),
                                          ],
                                        )
                                      : plantHealthLayer(
                                          farmCorners: farm.corners,
                                        ),
                                if (farm != null)
                                  PolygonLayer(
                                    polygons: [
                                      Polygon(
                                        points: farm.corners,
                                        color: line.withValues(
                                          alpha: !kIsWeb ? 0.0 : health ? 0.0 : 0.28,
                                        ),
                                        borderColor: line,
                                        borderStrokeWidth: 3,
                                      ),
                                    ],
                                  ),
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: farm?.center ?? pin,
                                      width: 170,
                                      height: 44,
                                      child: _FieldLabel(
                                        name: S.myFarm,
                                        look: look,
                                        pin: farm == null,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Positioned(
                              left: FsSpace.md,
                              top: FsSpace.md,
                              child: _MapPill(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      CupertinoIcons.leaf_arrow_circlepath,
                                      size: 18,
                                      color: kIsWeb ? p.positiveText : Colors.blueGrey,
                                    ),
                                    const SizedBox(width: FsSpace.xs + 2),
                                    Text(
                                      kIsWeb ? S.plantHealthChip : 'Satellite layer',
                                      style: t.subhead.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: FsSpace.xs),
                                    Transform.scale(
                                      scale: 0.8,
                                      child: CupertinoSwitch(
                                        value: health,
                                        activeTrackColor: p.tint,
                                        onChanged: !kIsWeb || farm == null
                                            ? null
                                            : (v) => setState(
                                                () => _plantHealth = v,
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              right: FsSpace.md,
                              top: FsSpace.md,
                              child: Semantics(
                                button: true,
                                label: S.centerFarm,
                                child: FsPressable(
                                  onTap: () => _showFarm(farm, pin),
                                  child: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: p.surfaceRaised,
                                      shape: BoxShape.circle,
                                      boxShadow: FsShadow.soft(p),
                                    ),
                                    child: Icon(
                                      CupertinoIcons.scope,
                                      color: p.label,
                                      size: 24,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: FsSpace.md,
                              bottom: FsSpace.md,
                              right: 70,
                              child: Align(
                                alignment: Alignment.bottomLeft,
                                child: _MapPill(
                                  child: !kIsWeb && !hls
                                      ? const Text('Field boundary · vegetation unknown', style: TextStyle(color: Colors.white))
                                      : health
                                      ? (hls
                                            ? const _GreenLegend()
                                            : const PlantHealthLegend())
                                      : Wrap(
                                          spacing: FsSpace.md,
                                          runSpacing: FsSpace.xs,
                                          children: [
                                            _LegendItem(
                                              const Color(0xFF4CAF50),
                                              S.onTrack,
                                            ),
                                            _LegendItem(
                                              const Color(0xFFF2B233),
                                              S.needsALook,
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                            const Positioned(
                              right: FsSpace.sm,
                              bottom: FsSpace.xs,
                              child: Text(
                                satelliteCredit,
                                style: TextStyle(
                                  color: Color(0xDDFFFFFF),
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (!kIsWeb)
                  Padding(padding: const EdgeInsets.symmetric(horizontal: FsSpace.gutter), child: OutlinedButton.icon(onPressed: () => context.push('/soil-map'), icon: const Icon(Icons.layers_outlined), label: const Text('Explore soil reference layers'))),
                if (caption != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      FsSpace.gutter + FsSpace.xs,
                      FsSpace.sm,
                      FsSpace.gutter,
                      0,
                    ),
                    child: Text(caption, style: t.footnote),
                  ),
                FsEntrance(
                  index: 1,
                  child: FsCard(
                    onTap: () => context.push('/field-details'),
                    semanticLabel: S.viewFieldDetails,
                    padding: const EdgeInsets.all(FsSpace.md),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(FsRadius.md),
                          child: SizedBox(
                            width: 92,
                            height: 70,
                            child: FarmPicture(
                              center: pin,
                              corners: farm?.corners,
                              zoom: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: FsSpace.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                S.myFarm,
                                style: t.title3.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                farm == null
                                    ? (crop ?? S.notMarkedYet)
                                    : crop == null
                                    ? farmSizeLabel(farm)
                                    : S.cropAndSize(crop, farmSizeLabel(farm)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.subhead.copyWith(
                                  color: p.secondaryLabel,
                                ),
                              ),
                              const SizedBox(height: FsSpace.xs),
                              Row(
                                children: [
                                  Icon(
                                    look
                                        ? CupertinoIcons
                                              .exclamationmark_triangle_fill
                                        : CupertinoIcons.checkmark_circle_fill,
                                    size: 18,
                                    color: look
                                        ? p.cautionText
                                        : p.positiveText,
                                  ),
                                  const SizedBox(width: FsSpace.xs),
                                  Flexible(
                                    child: Text(
                                      '${S.tasksLabel} · $statusText',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.subhead.copyWith(
                                        color: look
                                            ? p.cautionText
                                            : p.positiveText,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          CupertinoIcons.chevron_right,
                          size: 18,
                          color: p.tertiaryLabel,
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    FsSpace.gutter,
                    FsSpace.md,
                    FsSpace.gutter,
                    FsSpace.md,
                  ),
                  child: farm == null
                      ? FsButton(
                          S.markFarm,
                          icon: CupertinoIcons.map_pin_ellipse,
                          onPressed: () => context.push('/farm'),
                        )
                      : FsButton(
                          S.viewFieldDetails,
                          onPressed: () => context.push('/field-details'),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MapPill extends StatelessWidget {
  const _MapPill({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: FsSpace.md,
      vertical: FsSpace.xs + 2,
    ),
    decoration: BoxDecoration(
      color: context.fs.surfaceRaised.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(FsRadius.capsule),
      boxShadow: FsShadow.soft(context.fs),
    ),
    child: child,
  );
}

class _LegendItem extends StatelessWidget {
  const _LegendItem(this.color, this.label);
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Dot(color),
      Flexible(child: Text(label, style: context.type.subhead)),
    ],
  );
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 12,
    height: 12,
    margin: const EdgeInsets.only(right: FsSpace.xs + 2),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Name tag on the map ("✓ My farm"), like the design's field labels.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.name, required this.look, this.pin = false});
  final String name;
  final bool look, pin;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return Center(
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          FsSpace.xs,
          FsSpace.xs,
          FsSpace.md,
          FsSpace.xs,
        ),
        decoration: BoxDecoration(
          color: const Color(0xCC1B2A1D),
          borderRadius: BorderRadius.circular(FsRadius.capsule),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: look ? const Color(0xFFF2B233) : const Color(0xFF4CAF50),
                shape: BoxShape.circle,
              ),
              child: Icon(
                pin
                    ? CupertinoIcons.location_solid
                    : look
                    ? CupertinoIcons.exclamationmark
                    : CupertinoIcons.checkmark_alt,
                color: Colors.white,
                size: 17,
              ),
            ),
            const SizedBox(width: FsSpace.sm),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.subhead.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Colour bins for NDVI on the map (display only, not a verdict).
Color ndviColor(double? v) => switch (v) {
  null => const Color(0x99D9D9D9),
  < 0.2 => const Color(0xD9A0522D),
  < 0.35 => const Color(0xD9D8B04A),
  < 0.5 => const Color(0xD9A5C94B),
  < 0.65 => const Color(0xD95DA34A),
  _ => const Color(0xD92E7D32),
};

/// "Green cover 0.62 on 2 Nov · 0.52 on 28 Oct", pixels and source.
String greenCaption(FarmGreenness g) {
  final l = g.latest!;
  final p = g.previous;
  final now = S.greenNow(
    l.ndviMean?.toStringAsFixed(2) ?? '—',
    shortDate(l.date),
  );
  final before = p?.ndviMean == null
      ? ''
      : ' · ${S.greenBefore(p!.ndviMean!.toStringAsFixed(2), shortDate(p.date))}';
  return '$now$before. ${S.greenPixels(l.pixelsClear, l.pixelsInside, l.sensor)}. ${S.greenScale}. Historical vegetation only: trees, parks and gardens can also be green. This does not identify crops or establish plant health.';
}

class _GreenLegend extends StatelessWidget {
  const _GreenLegend();

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    Widget sw(Color c) => Container(
      width: 14,
      height: 14,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(3),
      ),
    );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: FsSpace.xs,
      runSpacing: FsSpace.xs,
      children: [
        Text(S.greenBare, style: t.footnote),
        for (final v in [0.1, 0.3, 0.45, 0.6, 0.8]) sw(ndviColor(v)),
        Text(S.greenDense, style: t.footnote),
        const SizedBox(width: FsSpace.xs),
        sw(ndviColor(null)),
        Text(S.greenNotSeen, style: t.footnote),
      ],
    );
  }
}
