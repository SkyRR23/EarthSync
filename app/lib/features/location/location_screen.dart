import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/home_profile.dart';
import '../../state/home_provider.dart';
import '../../state/providers.dart';
import '../map/farm_map_editor.dart';
import '../../data/models/farm_boundary.dart';

/// A local draft. Map taps and area changes never mutate a confirmed farm.
class LocationScreen extends ConsumerStatefulWidget {
  const LocationScreen({
    super.key,
    this.editing = false,
    this.areaOnly = false,
  });
  final bool editing, areaOnly;
  @override
  ConsumerState<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends ConsumerState<LocationScreen> {
  final _form = GlobalKey<FormState>();
  final _lat = TextEditingController(),
      _lon = TextEditingController(),
      _name = TextEditingController();
  bool _initialized = false, _confirmed = false, _map = false, _saving = false;
  FarmBoundary? _boundary;
  bool _boundaryEditing = false;
  AreaSource _source = AreaSource.manual;
  String? _error;
  @override
  void dispose() {
    _lat.dispose();
    _lon.dispose();
    _name.dispose();
    super.dispose();
  }

  void _pick(
    double lat,
    double lon, {
    String? name,
    AreaSource source = AreaSource.manual,
  }) {
    setState(() {
      _lat.text = lat.toStringAsFixed(7);
      _lon.text = lon.toStringAsFixed(7);
      if (name != null) _name.text = name;
      _source = source;
      _confirmed = false;
    });
  }

  GeoPoint? get _point {
    try {
      return GeoPoint(
        double.parse(_lat.text.trim()),
        double.parse(_lon.text.trim()),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || (!widget.areaOnly && !_confirmed)) {
      return;
    }
    final point = _point!;
    if (_boundaryEditing) {
      setState(
        () => _error = 'Confirm or cancel boundary editing before saving.',
      );
      return;
    }
    if (!widget.areaOnly && _boundary != null && !_boundary!.covers(point)) {
      setState(() => _error = 'The farm point must be inside the boundary.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final notifier = ref.read(homeProfileProvider.notifier);
      if (widget.areaOnly) {
        await notifier.setArea(
          ApproximateArea(
            point: point,
            label: _name.text.trim().isEmpty
                ? 'Selected area'
                : _name.text.trim(),
            source: _source,
          ),
        );
      } else {
        await notifier.confirmFarm(point, _name.text, boundary: _boundary);
        ref
            .read(farmerDraftProvider.notifier)
            .setLocation(point.latitude, point.longitude);
        ref.read(analysisProvider.notifier).reset();
      }
      if (!mounted) return;
      if (widget.editing && context.canPop()) {
        context.pop();
      } else {
        context.go('/dashboard');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not save on this device. Please try again, or return to the dashboard.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _suggestLocation() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final point = await ref.read(deviceLocationProvider).locate();
      if (mounted) {
        _pick(point.latitude, point.longitude, source: AreaSource.device);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Device location is unavailable or permission was denied. Enter coordinates or choose a point on the map.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(homeProfileProvider).value;
    if (!_initialized && profile != null) {
      final area = profile.userLocation;
      final point = widget.areaOnly
          ? (area is ApproximateArea ? area.point : null)
          : profile.farm?.point ??
                (area is ApproximateArea ? area.point : null);
      if (point != null) {
        _lat.text = '${point.latitude}';
        _lon.text = '${point.longitude}';
      }
      _name.text = widget.areaOnly
          ? (area is ApproximateArea ? area.label : '')
          : profile.farm?.name ?? '';
      if (widget.areaOnly && area is ApproximateArea) _source = area.source;
      _boundary = widget.areaOnly ? null : profile.farm?.boundary;
      _initialized = true;
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.areaOnly
              ? 'Choose an Area'
              : profile?.farm == null
              ? 'Add My Farm'
              : 'Edit My Farm',
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Form(
            key: _form,
            child: ListView(
              key: PageStorageKey(
                widget.areaOnly ? 'area-picker' : 'farm-picker',
              ),
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  widget.areaOnly
                      ? 'Explore anywhere'
                      : 'Confirm your field point',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.areaOnly
                      ? 'Choose a point for climate context. This will not change your farm.'
                      : 'Check that this point is on your field. Your device location may be somewhere else. A boundary is optional and must be explicitly drawn and confirmed.',
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _suggestLocation,
                  icon: const Icon(Icons.my_location),
                  label: const Text('Suggest a point with GPS (optional)'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  maxLength: 80,
                  decoration: InputDecoration(
                    labelText: widget.areaOnly
                        ? 'Area name (optional)'
                        : 'Field name (optional)',
                  ),
                ),
                TextFormField(
                  key: const Key('latitude'),
                  controller: _lat,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Latitude (−90 to 90)',
                  ),
                  onChanged: (_) => setState(() {
                    _confirmed = false;
                    _source = AreaSource.manual;
                  }),
                  validator: (v) {
                    final n = double.tryParse(v?.trim() ?? '');
                    return n == null || !n.isFinite || n < -90 || n > 90
                        ? 'Enter a latitude from −90 to 90.'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('longitude'),
                  controller: _lon,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Longitude (−180 to 180)',
                  ),
                  onChanged: (_) => setState(() {
                    _confirmed = false;
                    _source = AreaSource.manual;
                  }),
                  validator: (v) {
                    final n = double.tryParse(v?.trim() ?? '');
                    return n == null || !n.isFinite || n < -180 || n > 180
                        ? 'Enter a longitude from −180 to 180.'
                        : null;
                  },
                ),
                const SizedBox(height: 16),
                if (widget.areaOnly) ...[
                  const Text(
                    'Example regions · real places, not your farm. Data are requested only after you save.',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      ActionChip(
                        label: const Text('Yangon, Myanmar'),
                        onPressed: () => _pick(
                          kSampleLat,
                          kSampleLon,
                          name: 'Yangon, Myanmar',
                          source: AreaSource.example,
                        ),
                      ),
                      ActionChip(
                        label: const Text('Nairobi, Kenya'),
                        onPressed: () => _pick(
                          -1.29,
                          36.82,
                          name: 'Nairobi, Kenya',
                          source: AreaSource.example,
                        ),
                      ),
                      ActionChip(
                        label: const Text('São Paulo, Brazil'),
                        onPressed: () => _pick(
                          -23.55,
                          -46.63,
                          name: 'São Paulo, Brazil',
                          source: AreaSource.example,
                        ),
                      ),
                    ],
                  ),
                ],
                const Text(
                  'Selected points go to our climate service and NASA POWER for environmental queries. Satellite views use NASA GIBS. Opening the map shares the viewed tile area with OpenStreetMap.',
                ),
                TextButton.icon(
                  onPressed: _boundaryEditing
                      ? null
                      : () => setState(() => _map = !_map),
                  icon: const Icon(Icons.map_outlined),
                  label: Text(_map ? 'Hide map' : 'Open map (OpenStreetMap)'),
                ),
                if (_map)
                  FarmMapEditor(
                    point: _point,
                    boundary: _boundary,
                    areaOnly: widget.areaOnly,
                    onPoint: (p) => _pick(p.latitude, p.longitude),
                    onEditing: (v) => setState(() => _boundaryEditing = v),
                    onBoundary: (v) => setState(() {
                      _boundary = v;
                      _confirmed = false;
                    }),
                  ),
                if (!_map && _boundary != null)
                  Text(
                    'Saved boundary: ${_boundary!.vertices.length} vertices · ${(_boundary!.areaSquareMetres / 10000).toStringAsFixed(3)} ha. Open map to edit.',
                  ),
                if (!widget.areaOnly)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _confirmed,
                    onChanged: (v) => setState(() => _confirmed = v ?? false),
                    title: const Text('I confirm this point marks my field.'),
                  ),
                if (_error != null) Text(_error!),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed:
                      _saving ||
                          profile == null ||
                          _boundaryEditing ||
                          (!widget.areaOnly && !_confirmed)
                      ? null
                      : _save,
                  child: Text(
                    _saving
                        ? 'Saving…'
                        : widget.areaOnly
                        ? 'Save Area'
                        : 'Save Confirmed Farm',
                  ),
                ),
                TextButton(
                  onPressed: _saving ? null : () => context.go('/dashboard'),
                  child: const Text('Do this later'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
