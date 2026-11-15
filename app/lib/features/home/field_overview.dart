import 'package:flutter/cupertino.dart';
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
    final line = look ? const Color(0xFFF2B233) : const Color(0xFF7EE07A);
    final crop = cropName(d);
    final health = _plantHealth && farm != null;
    final caption = farm == null
        ? S.markFarmForHealth
        : health
        ? '${plantHealthDateLabel(ref.watch(plantHealthDateProvider(farm.center)).value)}. ${S.insideFarmOnly} ${S.pixelNote}'
        : null;

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
                                if (health)
                                  plantHealthLayer(farmCorners: farm.corners),
                                if (farm != null)
                                  PolygonLayer(
                                    polygons: [
                                      Polygon(
                                        points: farm.corners,
                                        color: line.withValues(
                                          alpha: health ? 0.0 : 0.28,
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
                                      color: p.positiveText,
                                    ),
                                    const SizedBox(width: FsSpace.xs + 2),
                                    Text(
                                      S.plantHealthChip,
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
                                        onChanged: farm == null
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
                                  child: health
                                      ? const PlantHealthLegend()
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
