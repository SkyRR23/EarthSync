import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../app/ui_copy.dart';
import '../../data/models/farm_boundary.dart';
import '../../data/models/home_profile.dart';
import 'gibs_layer.dart';

/// All geometry is local draft state until the farmer explicitly confirms it.
class FarmMapEditor extends StatefulWidget {
  const FarmMapEditor({
    super.key,
    required this.point,
    required this.boundary,
    required this.onPoint,
    required this.onBoundary,
    this.areaOnly = false,
    required this.onEditing,
  });
  final GeoPoint? point;
  final FarmBoundary? boundary;
  final ValueChanged<GeoPoint> onPoint;
  final ValueChanged<FarmBoundary?> onBoundary;
  final ValueChanged<bool> onEditing;
  final bool areaOnly;
  @override
  State<FarmMapEditor> createState() => _FarmMapEditorState();
}

class _FarmMapEditorState extends State<FarmMapEditor> {
  final _controller = MapController();
  List<GeoPoint> _vertices = [];
  final List<List<GeoPoint>> _undo = [];
  bool _editing = false;
  int? _selected;
  String _mode = 'standard';
  String? _error;
  String tr(String key) => UiCopy.text(context, key);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _change(List<GeoPoint> next) {
    setState(() {
      _undo.add(List.of(_vertices));
      _vertices = next;
      _error = null;
    });
  }

  void _start() {
    setState(() {
      _editing = true;
      _selected = null;
      _vertices = List.of(widget.boundary?.vertices ?? []);
      _undo.clear();
      _error = null;
    });
    widget.onEditing(true);
  }

  void _finish({bool cancel = false}) {
    try {
      if (!cancel) {
        final boundary = FarmBoundary(_vertices);
        if (widget.point == null || !boundary.covers(widget.point!)) {
          throw const FormatException(
            'Choose a farm point inside the boundary first.',
          );
        }
        widget.onBoundary(boundary);
      }
      setState(() {
        _editing = false;
        _selected = null;
        _error = null;
      });
      widget.onEditing(false);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _coordinates() async {
    final selected = _selected;
    final result = await showDialog<GeoPoint>(
      context: context,
      builder: (_) => _CoordinateDialog(
        point: selected == null ? null : _vertices[selected],
      ),
    );
    if (!mounted || result == null) return;
    if (selected == null) {
      if (_vertices.length < 999) _change([..._vertices, result]);
    } else {
      final next = List<GeoPoint>.of(_vertices);
      next[selected] = result;
      _change(next);
      setState(() => _selected = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    FarmBoundary? draft;
    if (_editing && _vertices.length >= 3) {
      try {
        draft = FarmBoundary(_vertices);
      } on FormatException {
        // Invalid drafts remain editable; confirmation performs validation.
      }
    }
    final needsPin =
        draft != null && (widget.point == null || !draft.covers(widget.point!));
    final points = (_editing ? _vertices : widget.boundary?.vertices ?? [])
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();
    final satellite = _mode != 'standard';
    final c = GibsLayerConfig.provisional;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _mode,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('mapLayer')),
          items: ['standard', 'satellite']
              .map((v) => DropdownMenuItem(value: v, child: Text(tr('map_$v'))))
              .toList(),
          onChanged: (v) => setState(() => _mode = v!),
        ),
        if (satellite)
          Text(
            'NASA MODIS true color · ${c.dateString} UTC · requested imagery date; availability varies. Native zoom ≤9, not field-resolution imagery or NDVI.',
          ),
        const SizedBox(height: 12),
        Text(
          _editing ? tr('boundaryHelp') : tr('pointHelp'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text(
          _editing
              ? 'Green numbers are field corners. Tap a number, then tap where you want to move that corner. Undo removes your last change.'
              : 'The red pin is the location used for your farm’s data. Drawing a field outline is optional.',
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 360,
          child: FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: LatLng(
                widget.point?.latitude ?? 0,
                widget.point?.longitude ?? 0,
              ),
              initialZoom: widget.point == null ? 2 : 15,
              maxZoom: 20,
              onTap: (_, p) {
                final picked = GeoPoint(p.latitude, p.longitude);
                if (_editing) {
                  if (_selected != null) {
                    final next = List<GeoPoint>.of(_vertices);
                    next[_selected!] = picked;
                    _change(next);
                    setState(() => _selected = null);
                  } else if (_vertices.length < 999) {
                    _change([..._vertices, picked]);
                  }
                } else {
                  widget.onPoint(picked);
                }
              },
            ),
            children: [
              ...baseMapLayers(),
              if (satellite) gibsTileLayer(c),
              if (points.length >= 3)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: points,
                      color: Colors.teal.withValues(alpha: 0.2),
                      borderColor: Colors.teal,
                      borderStrokeWidth: 3,
                    ),
                  ],
                ),
              if (points.length == 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: points,
                      color: Colors.teal,
                      strokeWidth: 3,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (widget.point != null)
                    Marker(
                      point: LatLng(
                        widget.point!.latitude,
                        widget.point!.longitude,
                      ),
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 32,
                      ),
                    ),
                  if (_editing)
                    for (var i = 0; i < points.length; i++)
                      Marker(
                        point: points[i],
                        width: 44,
                        height: 44,
                        child: IconButton(
                          tooltip: 'Move corner ${i + 1}',
                          onPressed: () => setState(() => _selected = i),
                          icon: CircleAvatar(
                            backgroundColor: _selected == i
                                ? Colors.orange
                                : Colors.teal,
                            child: Text('${i + 1}'),
                          ),
                        ),
                      ),
                ],
              ),
              Align(
                alignment: Alignment.topRight,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.filled(
                      tooltip: tr('zoomIn'),
                      onPressed: () => _controller.move(
                        _controller.camera.center,
                        (_controller.camera.zoom + 1).clamp(0, 20),
                      ),
                      icon: const Icon(Icons.add),
                    ),
                    IconButton.filled(
                      tooltip: tr('zoomOut'),
                      onPressed: () => _controller.move(
                        _controller.camera.center,
                        (_controller.camera.zoom - 1).clamp(0, 20),
                      ),
                      icon: const Icon(Icons.remove),
                    ),
                    if (widget.point != null)
                      IconButton.filled(
                        tooltip: tr('centerFarm'),
                        onPressed: () => _controller.move(
                          LatLng(
                            widget.point!.latitude,
                            widget.point!.longitude,
                          ),
                          15,
                        ),
                        icon: const Icon(Icons.my_location),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Text(
          satellite
              ? '© OpenStreetMap contributors (base) · NASA GIBS / MODIS'
              : '© OpenStreetMap contributors · ODbL',
        ),
        const Text('Red pin = farm location · Green outline = field edge'),
        const SizedBox(height: 12),
        if (needsPin) ...[
          const Text(
            'Your red pin is outside the outline. Move it inside before continuing.',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () {
                widget.onPoint(draft!.interiorPoint);
                setState(() => _error = null);
              },
              icon: const Icon(Icons.pin_drop_outlined),
              label: const Text('Move farm pin inside outline'),
            ),
          ),
          const Text(
            'This suggests a location only. Check it before saving your farm.',
          ),
          const SizedBox(height: 12),
        ],
        if (!widget.areaOnly)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!_editing)
                OutlinedButton(
                  onPressed: _start,
                  child: Text(
                    tr(
                      widget.boundary == null ? 'drawBoundary' : 'editBoundary',
                    ),
                  ),
                ),
              if (!_editing && widget.boundary != null)
                TextButton(
                  onPressed: () => widget.onBoundary(null),
                  child: Text(tr('pointOnly')),
                ),
              if (_editing) ...[
                OutlinedButton(
                  onPressed: _undo.isEmpty
                      ? null
                      : () => setState(() {
                          _vertices = _undo.removeLast();
                          _selected = null;
                        }),
                  child: Text(tr('undo')),
                ),
                TextButton(
                  onPressed: () => _finish(cancel: true),
                  child: Text(tr('cancelBoundary')),
                ),
                FilledButton(
                  onPressed: _vertices.length < 3 || needsPin
                      ? null
                      : () => _finish(),
                  child: Text(tr('confirmBoundary')),
                ),
                if (_selected != null)
                  TextButton(
                    onPressed: () {
                      final next = List.of(_vertices)..removeAt(_selected!);
                      _change(next);
                      setState(() => _selected = null);
                    },
                    child: Text(tr('deleteVertex')),
                  ),
              ],
            ],
          ),
        if (_editing)
          Text(
            '${_vertices.length} corners added${_selected == null ? (_vertices.length < 3 ? ' · add ${3 - _vertices.length} more to make an outline' : '') : ' · corner ${_selected! + 1} selected; tap its new position'}',
          ),
        if (_editing)
          ExpansionTile(
            key: const PageStorageKey('farm-map-coordinate-entry'),
            tilePadding: EdgeInsets.zero,
            title: const Text('Enter a corner by coordinates (optional)'),
            children: [
              OutlinedButton(
                onPressed: _coordinates,
                child: Text(
                  _selected == null
                      ? 'Add corner by coordinates'
                      : 'Edit selected corner coordinates',
                ),
              ),
            ],
          ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (!_editing && widget.boundary != null)
          Text(
            'Approximate area: ${(widget.boundary!.areaSquareMetres / 10000).toStringAsFixed(3)} ha · spherical calculation, not a survey.',
          ),
        const ExpansionTile(
          key: PageStorageKey('farm-map-source-details'),
          tilePadding: EdgeInsets.zero,
          title: Text('Map sources & privacy'),
          children: [
            Text(
              'Street map: OpenStreetMap. Satellite reference: NASA MODIS, not NDVI. Map backgrounds need internet; a blank tile means imagery is missing. Your field outline stays in your local workspace. Map providers receive the viewed tile area.',
            ),
          ],
        ),
      ],
    );
  }
}

class _CoordinateDialog extends StatefulWidget {
  const _CoordinateDialog({this.point});
  final GeoPoint? point;
  @override
  State<_CoordinateDialog> createState() => _CoordinateDialogState();
}

class _CoordinateDialogState extends State<_CoordinateDialog> {
  final _form = GlobalKey<FormState>();
  late final _latitude = TextEditingController(
    text: widget.point?.latitude.toString() ?? '',
  );
  late final _longitude = TextEditingController(
    text: widget.point?.longitude.toString() ?? '',
  );
  @override
  void dispose() {
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.point == null ? 'Add boundary corner' : 'Edit boundary corner',
    ),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _latitude,
            decoration: const InputDecoration(labelText: 'Corner latitude'),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            validator: (v) {
              final x = double.tryParse(v ?? '');
              return x == null || !x.isFinite || x < -90 || x > 90
                  ? 'Use latitude −90 to 90.'
                  : null;
            },
          ),
          TextFormField(
            controller: _longitude,
            decoration: const InputDecoration(labelText: 'Corner longitude'),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            validator: (v) {
              final x = double.tryParse(v ?? '');
              return x == null || !x.isFinite || x < -180 || x > 180
                  ? 'Use longitude −180 to 180.'
                  : null;
            },
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(
              context,
              GeoPoint(
                double.parse(_latitude.text),
                double.parse(_longitude.text),
              ),
            );
          }
        },
        child: const Text('Use this corner'),
      ),
    ],
  );
}
