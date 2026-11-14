import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/farm_journal.dart';
import '../../data/models/farmer_input.dart';
import '../../design/components/product.dart';
import '../../state/home_provider.dart';
import '../../state/integration_provider.dart';
import '../../state/journal_provider.dart';
import '../../state/platform_provider.dart';
import 'companion_copy.dart';
import 'crop_picker.dart';

const journalKinds = {
  'season': 'Actual crop season',
  'fallow': 'Declared fallow period',
  'bare_field': 'Reported bare-field period',
  'plan': 'Future plan',
  'stage': 'Reported growth stage',
  'irrigation': 'Irrigation event',
  'management': 'Management / fertilizer',
  'observation': 'Field observation',
  'problem': 'Reported problem',
  'soil_test': 'Soil test',
  'priorities': 'Farmer priorities',
  'warning_acknowledgment': 'Warning acknowledgment',
};

class JournalForm extends ConsumerStatefulWidget {
  const JournalForm({super.key, required this.snapshot});
  final FarmJournalSnapshot? snapshot;
  @override
  ConsumerState<JournalForm> createState() => _JournalFormState();
}

class _JournalFormState extends ConsumerState<JournalForm> {
  final _notes = TextEditingController(), _resources = TextEditingController();
  final _crop = TextEditingController();
  final _cropFocus = FocusNode();
  final _soilValue = TextEditingController(),
      _soilSource = TextEditingController();
  final _soilTop = TextEditingController(),
      _soilBottom = TextEditingController();
  String _kind = 'observation', _stage = 'unknown', _irrigation = 'unknown';
  String _drainage = 'unknown', _water = 'unknown', _property = 'ph';
  String? _cropId, _date, _harvest, _message;
  String _id = journalId();
  final _priorities = <String>{}, _photos = <String>{}, _evidence = <String>{};
  bool _busy = false, _loaded = false;
  String? _draftKey;
  String tr(String s) => CompanionCopy.text(context, s);
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final farm = ref.read(homeProfileProvider).value?.farm;
    final client = ref.read(platformFarmClientProvider);
    if (farm == null) return;
    _draftKey =
        '${ref.read(journalCacheProvider).key(farm, client?.transport.baseUri.origin ?? 'unconfigured')}.draft';
    try {
      final draft = await ref.read(journalCacheProvider).read(_draftKey!);
      if (!mounted) return;
      if (draft != null) {
        _id = draft['id'] as String;
        _kind = draft['kind'] as String;
        _date = draft['occurred_on'] as String?;
        _harvest = draft['harvest_on'] as String?;
        _crop.text = draft['crop_name'] as String? ?? '';
        _cropId = draft['crop_id'] as String?;
        _stage = draft['stage'] as String;
        _irrigation = draft['irrigation'] as String;
        _drainage = draft['drainage'] as String;
        _water = draft['water_access'] as String;
        _notes.text = draft['notes'] as String;
        _resources.text = draft['resources'] as String? ?? '';
        _priorities.addAll((draft['priorities'] as List).cast<String>());
        _photos.addAll((draft['photo_ids'] as List).cast<String>());
        _evidence.addAll((draft['evidence_ids'] as List).cast<String>());
        final soil = draft['soil_test'] as Map?;
        if (soil != null) {
          _property = soil['property'] as String;
          _soilValue.text = '${soil['value'] ?? ''}';
          _soilSource.text = soil['source'] as String;
          _soilTop.text = '${soil['top_cm'] ?? ''}';
          _soilBottom.text = '${soil['bottom_cm'] ?? ''}';
        }
      }
      setState(() => _loaded = true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Saved draft could not be read. It has not been replaced.',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      _notes,
      _resources,
      _crop,
      _soilValue,
      _soilSource,
      _soilTop,
      _soilBottom,
    ]) {
      c.dispose();
    }
    _cropFocus.dispose();
    super.dispose();
  }

  Map<String, dynamic> value() => {
    'schema_version': 'earthsync.journal.v1',
    'id': _id,
    'kind': _kind,
    'occurred_on': _date,
    'harvest_on': ['season', 'plan', 'fallow', 'bare_field'].contains(_kind)
        ? _harvest
        : null,
    'crop_id': _cropId,
    'crop_name': _crop.text.trim().isEmpty ? null : _crop.text.trim(),
    'stage': _stage,
    'irrigation': _irrigation,
    'drainage': _drainage,
    'water_access': _water,
    'priorities': _priorities.toList(),
    'resources': _resources.text.trim(),
    'notes': _notes.text.trim(),
    'photo_ids': _photos.toList(),
    'evidence_ids': _evidence.toList(),
    'soil_test': _kind != 'soil_test'
        ? null
        : {
            'property': _property,
            'unit': _property == 'ph'
                ? 'pH'
                : ['clay', 'sand', 'silt'].contains(_property)
                ? '%'
                : 'g/kg',
            'value': double.tryParse(_soilValue.text),
            'top_cm': double.tryParse(_soilTop.text),
            'bottom_cm': double.tryParse(_soilBottom.text),
            'source': _soilSource.text.trim(),
          },
  };
  Future<void> _act(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) {
        setState(
          () => _message =
              'Could not complete: $e. Inspect saved records before retrying.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_date == null ||
        (['season', 'plan'].contains(_kind) && _crop.text.trim().isEmpty)) {
      setState(
        () => _message =
            'Choose a record date and crop for a season or plan. Unknown details can stay unknown.',
      );
      return;
    }
    if (!await confirmAction(
          context,
          title: tr('Confirm this record?'),
          message:
              'This saves a farmer report to this farm revision. It does not certify a measurement or create a crop recommendation.',
          confirmLabel: tr('Save'),
        ) ||
        !mounted) {
      return;
    }
    await _act(() async {
      final platform = ref.read(platformFarmClientProvider);
      final snapshot = widget.snapshot;
      if (platform == null || snapshot == null || snapshot.cached) {
        throw StateError(
          'Reconnect before submitting. Your draft remains local.',
        );
      }
      final payload = value();
      // Persist the same UUID before sending so explicit retries are idempotent.
      await ref.read(journalCacheProvider).save(_draftKey!, payload);
      await FarmJournalClient(platform).save(snapshot.farmId, payload);
      await ref.read(journalCacheProvider).remove(_draftKey!);
      if (!mounted) return;
      setState(() {
        _id = journalId();
        _notes.clear();
        _photos.clear();
        _evidence.clear();
        _message = tr('Report saved');
      });
      ref.invalidate(journalProvider);
      ref.invalidate(platformAssistantProvider);
    });
  }

  Widget choice(
    String label,
    String selected,
    Map<String, String> options,
    ValueChanged<String> change,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label:$selected'),
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(labelText: tr(label)),
      items: [
        for (final o in options.entries)
          DropdownMenuItem(value: o.key, child: Text(tr(o.value))),
      ],
      onChanged: _busy ? null : (v) => setState(() => change(v!)),
    ),
  );
  Widget day(String label, String? value, ValueChanged<String?> change) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr(label)),
        subtitle: Text(value ?? tr('Unknown')),
        trailing: Wrap(
          children: [
            if (value != null)
              IconButton(
                tooltip: 'Clear date',
                onPressed: _busy ? null : () => setState(() => change(null)),
                icon: const Icon(Icons.clear),
              ),
            IconButton(
              tooltip: tr(label),
              icon: const Icon(Icons.calendar_month),
              onPressed: _busy
                  ? null
                  : () async {
                      final now = DateTime.now();
                      final last = _kind == 'plan'
                          ? DateTime(now.year + 10)
                          : now;
                      final initial = DateTime.tryParse(value ?? '') ?? now;
                      final result = await showDatePicker(
                        context: context,
                        initialDate: initial.isAfter(last) ? last : initial,
                        firstDate: DateTime(1900),
                        lastDate: last,
                      );
                      if (result != null && mounted) {
                        setState(
                          () =>
                              change(result.toIso8601String().substring(0, 10)),
                        );
                      }
                    },
            ),
          ],
        ),
      );
  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final catalog = ref.watch(catalogProvider).value;
    final identities = <String, Map>{
      for (final p in catalog?['profiles'] as List? ?? [])
        if (p['kind'] != 'fallow')
          '${p['crop_id']}@catalog-${catalog!['reference']['catalog_version']}':
              p as Map,
    };
    return SectionCard(
      title: tr('Add a record'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('Farmer reported')),
          const Text(
            'Save a draft first if offline. Nothing is submitted or retried automatically. Dates and crop stages are reported by you.',
          ),
          choice('Record type', _kind, journalKinds, (v) {
            _kind = v;
            if (['fallow', 'bare_field'].contains(v)) {
              _crop.clear();
              _cropId = null;
            }
          }),
          RawAutocomplete<String>(
            textEditingController: _crop,
            focusNode: _cropFocus,
            optionsBuilder: (v) => Crops.options.values.where(
              (c) => c.toLowerCase().contains(v.text.toLowerCase()),
            ),
            onSelected: (v) => setState(() {
              _crop.text = v;
              _cropId = null;
            }),
            fieldViewBuilder: (_, controller, node, submit) => TextField(
              controller: controller,
              focusNode: node,
              maxLength: 150,
              decoration: InputDecoration(
                labelText: tr('Crop'),
                helperText:
                    'Common name; catalog identity is selected separately for Rust history.',
              ),
              onChanged: (_) => _cropId = null,
            ),
            optionsViewBuilder: (_, select, options) => Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                child: SizedBox(
                  width: 260,
                  height: 200,
                  child: ListView(
                    children: [
                      for (final o in options)
                        ListTile(title: Text(o), onTap: () => select(o)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () async {
                    final crop = await pickCatalogCrop(context);
                    if (crop != null && mounted) {
                      setState(() {
                        _crop.text =
                            (crop['aliases'] as List).firstOrNull as String? ??
                            crop['scientific_name'] as String;
                        _cropId = crop['id'] as String;
                      });
                    }
                  },
            icon: const Icon(Icons.search),
            label: Text(tr('Search crops or aliases')),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _crop.text = 'Unknown crop';
                    _cropId = null;
                  }),
            child: Text(tr('Unknown')),
          ),
          if (_cropId != null)
            Text('Farmer-declared catalog identity: $_cropId'),
          if (['season', 'plan'].contains(_kind) &&
              (_cropId == null || identities.containsKey(_cropId)))
            DropdownButtonFormField<String>(
              key: ValueKey('catalog:$_cropId'),
              initialValue: _cropId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Catalog identity for history (optional)',
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Unknown / not selected'),
                ),
                for (final p in identities.entries)
                  DropdownMenuItem(
                    value: p.key,
                    child: Text(
                      '${p.value['common_name']}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _busy ? null : (v) => setState(() => _cropId = v),
            ),
          day('Date / planting', _date, (v) => _date = v),
          if (['season', 'plan', 'fallow', 'bare_field'].contains(_kind))
            day(
              _kind == 'plan'
                  ? 'Expected harvest'
                  : ['fallow', 'bare_field'].contains(_kind)
                  ? 'Period end'
                  : 'Actual harvest',
              _harvest,
              (v) => _harvest = v,
            ),
          choice('Reported growth stage', _stage, const {
            'unknown': 'Unknown',
            'sowing': 'Sowing',
            'emergence': 'Emergence',
            'vegetative': 'Vegetative',
            'flowering': 'Flowering',
            'fruiting': 'Fruiting',
            'maturity': 'Maturity',
            'harvested': 'Harvested',
          }, (v) => _stage = v),
          ResponsivePair(
            first: choice('Irrigation availability', _irrigation, const {
              'unknown': 'Unknown',
              'available': 'Available',
              'limited': 'Limited',
              'none': 'None',
            }, (v) => _irrigation = v),
            second: choice('Drainage', _drainage, const {
              'unknown': 'Unknown',
              'good': 'Good',
              'moderate': 'Moderate',
              'poor': 'Poor',
            }, (v) => _drainage = v),
          ),
          choice('Water access', _water, const {
            'unknown': 'Unknown',
            'rain_only': 'Rain only',
            'well': 'Well',
            'canal': 'Canal',
            'pond': 'Pond',
            'other': 'Other',
          }, (v) => _water = v),
          Text(tr('Farmer priorities')),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final p in farmerPriorityLabels.entries)
                FilterChip(
                  label: Text(tr(p.value)),
                  selected: _priorities.contains(p.key),
                  onSelected: _busy
                      ? null
                      : (yes) => setState(() {
                          yes
                              ? _priorities.add(p.key)
                              : _priorities.remove(p.key);
                        }),
                ),
            ],
          ),
          TextField(
            controller: _resources,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: tr('Budget, labor & equipment (optional)'),
            ),
          ),
          TextField(
            controller: _notes,
            maxLength: 2000,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(labelText: tr('What did you observe?')),
          ),
          if (_kind == 'soil_test') ...[
            choice('Soil property', _property, const {
              'ph': 'pH',
              'organic_carbon': 'Organic carbon',
              'nitrogen': 'Total nitrogen',
              'clay': 'Clay',
              'sand': 'Sand',
              'silt': 'Silt',
            }, (v) => _property = v),
            TextField(
              controller: _soilValue,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText:
                    'Reported value (${_property == 'ph'
                        ? 'pH'
                        : ['clay', 'sand', 'silt'].contains(_property)
                        ? '%'
                        : 'g/kg'})',
              ),
            ),
            ResponsivePair(
              first: TextField(
                controller: _soilTop,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Sample top depth (cm)',
                ),
              ),
              second: TextField(
                controller: _soilBottom,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Sample bottom depth (cm)',
                ),
              ),
            ),
            TextField(
              controller: _soilSource,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Laboratory / source as reported',
              ),
            ),
          ],
          if (snapshot != null)
            ExpansionTile(
              title: Text(tr('Attach selected photos')),
              children: [
                if (snapshot.rows('photos').isEmpty)
                  const Text(
                    'No farm-owned photos yet. Upload through Photos in this farm.',
                  ),
                for (final photo in snapshot.rows('photos'))
                  CheckboxListTile(
                    title: Text('Photo · ${photo['uploaded_at_epoch']}'),
                    subtitle: Text('${photo['id']}'),
                    value: _photos.contains(photo['id']),
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                            v == true
                                ? _photos.add(photo['id'] as String)
                                : _photos.remove(photo['id']);
                          }),
                  ),
              ],
            ),
          if (snapshot != null)
            ExpansionTile(
              title: Text(tr('Evidence & sources')),
              children: [
                for (final e in snapshot.rows('evidence'))
                  CheckboxListTile(
                    title: Text('${e['dataset']}'),
                    subtitle: Text(
                      '${e['temporal']['start']} · ${e['data_type']}',
                    ),
                    value: _evidence.contains(e['id']),
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                            v == true
                                ? _evidence.add(e['id'] as String)
                                : _evidence.remove(e['id']);
                          }),
                  ),
              ],
            ),
          OutlinedButton(
            onPressed: _busy || !_loaded
                ? null
                : () => _act(() async {
                    await ref
                        .read(journalCacheProvider)
                        .save(_draftKey!, value());
                    if (mounted) {
                      setState(
                        () => _message = tr('Draft saved · not submitted'),
                      );
                    }
                  }),
            child: Text(tr('Save draft on this device')),
          ),
          FilledButton(
            onPressed: _busy || !_loaded || snapshot == null || snapshot.cached
                ? null
                : _save,
            child: Text(tr('Confirm & save report')),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_message != null)
            Semantics(liveRegion: true, child: Text(_message!)),
        ],
      ),
    );
  }
}
