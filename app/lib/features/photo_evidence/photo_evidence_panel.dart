import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'photo_evidence_client.dart';
import 'photo_evidence_models.dart';
import 'photo_picker.dart';

/// Reusable, route-independent photo upload/viewer for a private workspace.
/// The caller supplies a confirmed farm reference; this widget never obtains
/// approximate device location or treats photo GPS as farm confirmation.
class PhotoEvidencePanel extends StatefulWidget {
  const PhotoEvidencePanel({
    super.key,
    required this.repository,
    required this.picker,
    this.confirmedFarm,
    this.onChanged,
  });
  final PhotoEvidenceRepository repository;
  final FieldPhotoPicker picker;
  final ConfirmedFarmReference? confirmedFarm;
  final VoidCallback? onChanged;

  @override
  State<PhotoEvidencePanel> createState() => _PhotoEvidencePanelState();
}

class _PhotoEvidencePanelState extends State<PhotoEvidencePanel> {
  final _caption = TextEditingController();
  final _observations = TextEditingController();
  final Map<String, Future<Uint8List>> _images = {};
  List<StoredPhoto> _photos = [];
  PreparedPhoto? _selected;
  PhotoCategory _category = PhotoCategory.crop;
  DateTime? _capturedDate;
  String? _replaceId;
  bool _readGps = false;
  bool _associate = false;
  bool _synthetic = false;
  bool _busy = true;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant PhotoEvidencePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.confirmedFarm?.id != widget.confirmedFarm?.id) {
      _generation++;
      _clearDraft();
      _photos = [];
      _images.clear();
      _busy = true;
      _refresh();
    }
  }

  @override
  void dispose() {
    _caption.dispose();
    _observations.dispose();
    super.dispose();
  }

  void _clearDraft() {
    _selected = null;
    _replaceId = null;
    _caption.clear();
    _observations.clear();
    _capturedDate = null;
    _associate = false;
    _synthetic = false;
    _readGps = false;
    _category = PhotoCategory.crop;
  }

  Future<void> _operation(Future<void> Function(int generation) action) async {
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(generation);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = error is PhotoEvidenceException
              ? error.message
              : 'Could not process photo evidence. Try again.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _refresh() => _operation((generation) async {
    final photos = await widget.repository.list();
    if (mounted && generation == _generation) {
      setState(() {
        _images.clear();
        _photos = photos;
      });
    }
  });

  Future<void> _pick(PhotoOrigin origin, {String? replaceId}) =>
      _operation((generation) async {
        final selected = await widget.picker.pick(origin, readGps: _readGps);
        if (!mounted || generation != _generation || selected == null) return;
        setState(() {
          _selected = selected;
          _replaceId = replaceId;
          _capturedDate = null;
          _caption.clear();
          _observations.clear();
          _associate = false;
        });
      });

  Future<void> _save() => _operation((generation) async {
    final selected = _selected;
    if (selected == null) return;
    final saved = await widget.repository.save(
      PhotoDraft(
        photo: selected,
        category: _category,
        caption: _caption.text,
        farmerObservations: _observations.text,
        capturedDate: _capturedDate,
        farm: _associate ? widget.confirmedFarm : null,
        synthetic: _synthetic,
      ),
      replaceId: _replaceId,
    );
    if (!mounted || generation != _generation) return;
    setState(() {
      _images.remove(saved.id);
      _photos = [saved, ..._photos.where((photo) => photo.id != saved.id)];
      _clearDraft();
    });
    widget.onChanged?.call();
  });

  Future<void> _remove(StoredPhoto photo) => _operation((generation) async {
    await widget.repository.remove(photo.id);
    if (!mounted || generation != _generation) return;
    setState(() {
      _photos.removeWhere((entry) => entry.id == photo.id);
      _images.remove(photo.id);
      if (_replaceId == photo.id) _clearDraft();
    });
    widget.onChanged?.call();
  });

  Future<void> _chooseDate() async {
    final generation = _generation;
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _capturedDate ?? now,
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'When was this photo taken? (your report)',
    );
    if (mounted && generation == _generation && day != null) {
      setState(() => _capturedDate = day);
    }
  }

  PhotoOrigin get _fileOrigin =>
      kIsWeb ? PhotoOrigin.browserFile : PhotoOrigin.gallery;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Field photo evidence',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const Text(
        'Photos and your observations are farmer-supplied evidence. '
        'A photo cannot establish an exact farm location from its pixels.',
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text(
          'Read and upload EXIF GPS for the next selected photo',
        ),
        subtitle: const Text(
          'Optional consent to retain photo coordinates. '
          'Original metadata is stripped. This does not confirm a farm location.',
        ),
        value: _readGps,
        onChanged: _busy
            ? null
            : (value) => setState(() {
                _readGps = value;
                if (!value) _selected = _selected?.withoutGps();
              }),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _pick(_fileOrigin),
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(kIsWeb ? 'Choose photo file' : 'Choose from gallery'),
          ),
          if (widget.picker.supportsCamera)
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _pick(PhotoOrigin.camera),
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Take photo'),
            ),
          IconButton(
            tooltip: 'Refresh photos',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      const Text(
        'JPEG/PNG · up to 10 MiB · up to 16 megapixels · no animated images',
      ),
      if (_busy)
        const LinearProgressIndicator(
          semanticsLabel: 'Processing photo evidence',
        ),
      if (_error != null)
        Semantics(
          liveRegion: true,
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      if (_selected case final selected?) ...[
        const SizedBox(height: 12),
        Text(
          _replaceId == null
              ? 'New photo preview'
              : 'Replacement photo preview',
        ),
        Image.memory(
          selected.png,
          height: 220,
          fit: BoxFit.contain,
          semanticLabel: 'Selected field photo preview',
          errorBuilder: (_, _, _) => const Text('Photo preview unavailable'),
        ),
        Text(
          '${selected.width} × ${selected.height} pixels · original metadata removed',
        ),
        if (selected.gps != null)
          const Text(
            'Consented EXIF coordinates will be retained. Position uncertainty is unknown.',
          ),
        if (selected.gpsRequested && selected.gps == null)
          const Text(
            'No usable EXIF GPS found. Photo location remains unknown.',
          ),
        DropdownButtonFormField<PhotoCategory>(
          key: ValueKey(_category),
          initialValue: _category,
          decoration: const InputDecoration(labelText: 'Photo category'),
          items: PhotoCategory.values
              .map(
                (category) => DropdownMenuItem(
                  value: category,
                  child: Text(category.name),
                ),
              )
              .toList(),
          onChanged: _busy
              ? null
              : (value) => setState(() => _category = value!),
        ),
        TextField(
          controller: _caption,
          enabled: !_busy,
          maxLength: 1000,
          decoration: const InputDecoration(labelText: 'Optional caption'),
        ),
        TextField(
          controller: _observations,
          enabled: !_busy,
          maxLength: 2000,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Your observation (farmer-reported, optional)',
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: _busy ? null : _chooseDate,
              child: Text(
                _capturedDate == null
                    ? 'Capture date unknown — choose date'
                    : dateLabel(_capturedDate!),
              ),
            ),
            if (_capturedDate != null)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() => _capturedDate = null),
                child: const Text('Clear date'),
              ),
          ],
        ),
        if (widget.confirmedFarm case final farm?)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Associate with farmer-confirmed farm ${farm.id}'),
            subtitle: const Text(
              'This is your association, not a location inferred from the image.',
            ),
            value: _associate,
            onChanged: _busy
                ? null
                : (value) => setState(() => _associate = value ?? false),
          ),
        if (!_associate) const Text('Will be retained as unlocated evidence.'),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'This is a synthetic test image, not a field observation',
          ),
          value: _synthetic,
          onChanged: _busy
              ? null
              : (value) => setState(() => _synthetic = value ?? false),
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(
                _replaceId == null ? 'Upload photo' : 'Save replacement',
              ),
            ),
            TextButton(
              onPressed: _busy ? null : () => setState(_clearDraft),
              child: const Text('Remove selected photo'),
            ),
          ],
        ),
      ],
      const SizedBox(height: 16),
      if (_photos.isEmpty && !_busy) const Text('No uploaded photos.'),
      for (final photo in _photos)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FutureBuilder<Uint8List>(
                  future: _images.putIfAbsent(
                    photo.id,
                    () => widget.repository.image(photo.id),
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Text(
                        'Photo preview unavailable. Refresh to retry.',
                      );
                    }
                    if (!snapshot.hasData) {
                      return const SizedBox(
                        height: 100,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return Image.memory(
                      snapshot.data!,
                      height: 200,
                      fit: BoxFit.contain,
                      semanticLabel: photo.caption.isEmpty
                          ? 'Uploaded field photo'
                          : photo.caption,
                      errorBuilder: (_, _, _) =>
                          const Text('Photo preview unavailable'),
                    );
                  },
                ),
                Text('${photo.category} · ${photo.captureLabel}'),
                if (photo.synthetic)
                  const Text(
                    'SYNTHETIC test photo — not a real field observation',
                  ),
                Text(photo.caption),
                if (photo.observations.isNotEmpty)
                  Text('Farmer-reported: ${photo.observations}'),
                Text(
                  photo.farmId == null
                      ? 'Unlocated evidence'
                      : 'Farmer-associated farm: ${photo.farmId}',
                ),
                const Text(
                  'Photo view extent unknown · not scientifically validated',
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _pick(_fileOrigin, replaceId: photo.id),
                      child: const Text('Replace photo'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _remove(photo),
                      child: const Text('Delete photo'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );
}
