import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
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

/// Mark the field: stand in it and use GPS, tap the map, or use a sample.
class LocationScreen extends ConsumerStatefulWidget {
  const LocationScreen({super.key, this.editing = false, this.setup = false});
  final bool editing;

  /// Opened from setup step 1 ("Pin it on the map instead").
  final bool setup;

  @override
  ConsumerState<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends ConsumerState<LocationScreen> {
  final _map = MapController();
  bool _locating = false;
  String? _gpsMessage;

  void _set(LatLng pt, {double zoom = 12}) {
    ref
        .read(farmerDraftProvider.notifier)
        .setLocation(pt.latitude, pt.longitude);
    _map.move(pt, zoom);
  }

  /// "I'm at my field": one GPS reading, with plain messages when it fails.
  Future<void> _useGps() async {
    setState(() {
      _locating = true;
      _gpsMessage = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _gpsMessage = S.gpsOff);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() => _gpsMessage = S.gpsDenied);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (mounted) _set(LatLng(pos.latitude, pos.longitude), zoom: 14);
    } catch (_) {
      if (mounted) setState(() => _gpsMessage = S.gpsFailed);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _continue() {
    if (widget.editing) {
      ref
          .read(analysisProvider.notifier)
          .run(ref.read(farmerDraftProvider).toInput());
      context.pop();
    } else if (widget.setup) {
      context.push('/setup/2');
    } else {
      context.push('/question/1');
    }
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
              initialZoom: picked == null ? 9 : 12,
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
            if (_gpsMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: FsSpace.md),
                child: Text(
                  _gpsMessage!,
                  style: t.footnote.copyWith(color: p.cautionText),
                ),
              )
            else if (picked != null)
              Padding(
                padding: const EdgeInsets.only(bottom: FsSpace.md),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      color: p.positiveText,
                      size: 26,
                    ),
                    const SizedBox(width: FsSpace.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(S.fieldMarked, style: t.headline),
                          Text(
                            _inMyanmar(picked) ? S.pinLater : S.outsideMyanmar,
                            style: t.footnote.copyWith(
                              color: _inMyanmar(picked) ? null : p.cautionText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (picked == null) ...[
              FsButton(
                _locating ? S.findingYou : S.useMyLocation,
                icon: CupertinoIcons.location_fill,
                loading: _locating,
                onPressed: _useGps,
              ),
              const SizedBox(height: FsSpace.xs),
              FsButton(
                S.useSampleField,
                kind: FsButtonKind.plain,
                onPressed: () =>
                    _set(const LatLng(kSampleLat, kSampleLon), zoom: 10),
              ),
            ] else ...[
              FsButton(
                widget.editing ? S.done : S.continueLabel,
                onPressed: _continue,
              ),
              const SizedBox(height: FsSpace.xs),
              FsButton(
                _locating ? S.findingYou : S.useMyLocation,
                kind: FsButtonKind.plain,
                icon: CupertinoIcons.location_fill,
                loading: _locating,
                onPressed: _useGps,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
