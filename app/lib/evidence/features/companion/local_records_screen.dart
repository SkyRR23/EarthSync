import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/farm_journal.dart' show journalId;
import '../../data/local/farm_task.dart';
import '../../design/tokens.dart';
import '../../state/home_provider.dart';
import '../../state/local_farm_provider.dart';
import '../../state/journal_provider.dart';
import '../photo_evidence/photo_picker.dart';
import '../photo_evidence/photo_evidence_models.dart';
import '../tasks/tasks_screen.dart';

final localRecordsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  ref.watch(localRevisionProvider);
  final farm = ref.watch(homeProfileProvider).value?.farm;
  if (farm == null) return [];
  return (await ref.watch(
    localFarmStoreProvider.future,
  )).records(farm.id, 'journal');
});
final localPhotosProvider = FutureProvider<List<Map<String, Object?>>>((
  ref,
) async {
  ref.watch(localRevisionProvider);
  final farm = ref.watch(homeProfileProvider).value?.farm;
  if (farm == null) return [];
  return (await ref.watch(localFarmStoreProvider.future)).photos(farm.id);
});

class LocalRecordsScreen extends ConsumerStatefulWidget {
  const LocalRecordsScreen({super.key, this.initialKind = 'observation'});
  final String initialKind;
  @override
  ConsumerState<LocalRecordsScreen> createState() => _LocalRecordsState();
}

class _LocalRecordsState extends ConsumerState<LocalRecordsScreen> {
  bool _busy = false;
  String? _error;
  Future<void> _act(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      ref.read(localRevisionProvider.notifier).changed();
      ref.invalidate(journalProvider);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not save locally: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add([Map<String, dynamic>? record]) async {
    final farm = ref.read(homeProfileProvider).value?.farm;
    if (farm == null) return;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _RecordEditor(kind: widget.initialKind, record: record),
    );
    if (result == null || !mounted) return;
    await _act(() async {
      final store = await ref.read(localFarmStoreProvider.future);
      await store.put(farm.id, 'journal', {
        ...result,
        'farm_revision': farm.confirmedAt.toUtc().toIso8601String(),
        'evidence_type': 'farmer_reported',
      }, queue: true);
    });
  }

  Future<void> _photo() => _act(() async {
    final farm = ref.read(homeProfileProvider).value!.farm!;
    final photo = await PlatformFieldPhotoPicker().pick(
      PhotoOrigin.gallery,
      readGps: false,
    );
    if (photo == null) return;
    final store = await ref.read(localFarmStoreProvider.future);
    await store.savePhoto(farm.id, journalId(), 'image/png', photo.png, {
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'source': 'farmer_supplied',
      'farm_revision': farm.confirmedAt.toUtc().toIso8601String(),
      'gps_retained': false,
      'width': photo.width,
      'height': photo.height,
    });
  });
  Future<void> _followUp(Map<String, dynamic> record) async {
    final farm = ref.read(homeProfileProvider).value?.farm;
    if (farm == null) return;
    final task = await showModalBottomSheet<FarmTask>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          TaskEditor(farmId: farm.id, observationId: record['id'] as String),
    );
    if (task == null || !mounted) return;
    await _act(() async {
      await (await ref.read(localFarmStoreProvider.future)).saveTask(task);
    });
  }

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(localRecordsProvider);
    final photos = ref.watch(localPhotosProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Field notes & soil checks')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.all(FsSpace.lg),
            children: [
              Text(
                'Keep your field story close.',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const Text(
                'Notes, crop history, soil checks and photos stay on this device. Cloud upload is optional. Photos do not establish laboratory properties.',
              ),
              const SizedBox(height: FsSpace.md),
              Wrap(
                spacing: FsSpace.sm,
                runSpacing: FsSpace.sm,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _add(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add field record'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _photo,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Save a private photo'),
                  ),
                  TextButton(
                    onPressed: () => context.push('/season'),
                    child: const Text('All history & evidence'),
                  ),
                  TextButton(
                    onPressed: () => context.push('/tasks'),
                    child: const Text('Linked farm tasks'),
                  ),
                ],
              ),
              if (_busy || records.isLoading || photos.isLoading)
                const LinearProgressIndicator(
                  semanticsLabel: 'Loading field records',
                ),
              if (_error != null || records.hasError || photos.hasError)
                Text(
                  _error ??
                      'Local records could not be opened. Existing storage has not been replaced.',
                ),
              const SizedBox(height: FsSpace.lg),
              if ((records.value ?? []).isEmpty && !records.isLoading)
                const Text(
                  'No field notes yet. Add what you observed; unknown details can stay unknown.',
                ),
              for (final record in records.value ?? <Map<String, dynamic>>[])
                Card(
                  child: ListTile(
                    leading: Icon(
                      record['kind'] == 'soil_test'
                          ? Icons.science_outlined
                          : record['kind'] == 'season'
                          ? Icons.spa_outlined
                          : Icons.notes_outlined,
                    ),
                    title: Text(
                      '${record['crop_name'] ?? record['kind']} · ${record['occurred_on']}',
                    ),
                    subtitle: Text(
                      '${record['notes'] ?? ''}${record['soil_test'] is Map ? '\n${record['soil_test']['property']}: ${record['soil_test']['value']} ${record['soil_test']['unit']} · ${record['soil_test']['source']}' : ''}\nFarmer-reported',
                    ),
                    trailing: IconButton(
                      tooltip: 'Plan a follow-up task',
                      onPressed: _busy ? null : () => _followUp(record),
                      icon: const Icon(Icons.add_task),
                    ),
                    onTap: () => _add(record),
                  ),
                ),
              const SizedBox(height: FsSpace.lg),
              Text(
                'Private field photos',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'GPS metadata is removed. Saved images are available offline on this device.',
              ),
              Wrap(
                spacing: FsSpace.sm,
                runSpacing: FsSpace.sm,
                children: [
                  for (final photo in photos.value ?? <Map<String, Object?>>[])
                    _LocalPhoto(id: photo['id'] as String),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalPhoto extends ConsumerWidget {
  const _LocalPhoto({required this.id});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final farm = ref.watch(homeProfileProvider).value?.farm;
    return SizedBox(
      width: 180,
      height: 150,
      child: FutureBuilder<Uint8List?>(
        future: (() async => (await ref.read(
          localFarmStoreProvider.future,
        )).photo(farm!.id, id))(),
        builder: (_, state) => state.hasError
            ? const Text('Photo could not be opened')
            : state.data == null
            ? const Center(child: CircularProgressIndicator())
            : ClipRRect(
                borderRadius: const BorderRadius.all(FsRadius.md),
                child: Image.memory(
                  state.data!,
                  fit: BoxFit.cover,
                  semanticLabel: 'Private farmer-supplied field photograph',
                ),
              ),
      ),
    );
  }
}

class _RecordEditor extends StatefulWidget {
  const _RecordEditor({required this.kind, this.record});
  final String kind;
  final Map<String, dynamic>? record;
  @override
  State<_RecordEditor> createState() => _RecordEditorState();
}

class _RecordEditorState extends State<_RecordEditor> {
  final _notes = TextEditingController(),
      _crop = TextEditingController(),
      _value = TextEditingController(),
      _source = TextEditingController();
  late String _kind, _day;
  String _property = 'ph', _stage = 'unknown';
  String? _error;
  @override
  void initState() {
    super.initState();
    final record = widget.record;
    _kind = record?['kind'] as String? ?? widget.kind;
    _day = record?['occurred_on'] as String? ?? calendarDay(DateTime.now());
    _notes.text = record?['notes'] as String? ?? '';
    _crop.text = record?['crop_name'] as String? ?? '';
    _stage = record?['stage'] as String? ?? 'unknown';
    final soil = record?['soil_test'] as Map?;
    if (soil != null) {
      _property = soil['property'] as String;
      _value.text = '${soil['value']}';
      _source.text = soil['source'] as String? ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [_notes, _crop, _value, _source]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (_kind != 'plan' && DateTime.parse(_day).isAfter(DateTime.now())) {
      setState(() => _error = 'Use a plan for future activities.');
      return;
    }
    if (_kind == 'season' && _crop.text.trim().isEmpty) {
      setState(() => _error = 'Choose the crop you grew.');
      return;
    }
    final numeric = double.tryParse(_value.text);
    if (_kind == 'soil_test' &&
        (numeric == null ||
            !numeric.isFinite ||
            numeric < 0 ||
            (_property == 'ph' && numeric > 14) ||
            _source.text.trim().isEmpty)) {
      setState(() => _error = 'Add a valid value and its measurement source.');
      return;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    Navigator.pop(context, <String, dynamic>{
      ...?widget.record,
      'id': widget.record?['id'] ?? journalId(),
      'kind': _kind,
      'occurred_on': _day,
      'crop_name': _crop.text.trim().isEmpty ? null : _crop.text.trim(),
      'stage': _stage,
      'notes': _notes.text.trim(),
      'created_at': widget.record?['created_at'] ?? now,
      'updated_at': now,
      'soil_test': _kind == 'soil_test'
          ? {
              'property': _property,
              'value': numeric,
              'unit': _property == 'ph' ? 'pH' : 'g/kg',
              'source': _source.text.trim(),
              'verification': 'farmer_reported',
            }
          : null,
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(FsSpace.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Record what you know',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          DropdownButtonFormField<String>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Record type'),
            items: [
              for (final entry in const {
                'observation': 'Field observation',
                'season': 'Crop history / current crop',
                'soil_test': 'Reported soil measurement',
                'soil_texture': 'Hand-feel soil check',
                'plan': 'Farmer plan',
              }.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (v) => setState(() => _kind = v!),
          ),
          ListTile(
            title: const Text('Record date'),
            subtitle: Text(_day),
            trailing: const Icon(Icons.calendar_month),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: DateTime.parse(_day),
                firstDate: DateTime(1900),
                lastDate: _kind == 'plan' ? DateTime(2100) : DateTime.now(),
              );
              if (date != null && mounted) {
                setState(() => _day = calendarDay(date));
              }
            },
          ),
          if (_kind == 'season' || _kind == 'plan') ...[
            TextField(
              controller: _crop,
              maxLength: 150,
              decoration: const InputDecoration(
                labelText: 'Crop (farmer-reported)',
              ),
            ),
            DropdownButtonFormField<String>(
              initialValue: _stage,
              decoration: const InputDecoration(
                labelText: 'Reported growth stage',
              ),
              items: [
                for (final v in [
                  'unknown',
                  'sowing',
                  'emergence',
                  'vegetative',
                  'flowering',
                  'fruiting',
                  'maturity',
                  'harvested',
                ])
                  DropdownMenuItem(value: v, child: Text(v)),
              ],
              onChanged: (v) => _stage = v!,
            ),
          ],
          if (_kind == 'soil_test') ...[
            DropdownButtonFormField<String>(
              initialValue: _property,
              decoration: const InputDecoration(labelText: 'Soil property'),
              items: [
                for (final entry in const {
                  'ph': 'pH in water',
                  'organic_carbon': 'Organic carbon (g/kg)',
                  'nitrogen': 'Nitrogen (g/kg)',
                }.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (v) => setState(() => _property = v!),
            ),
            TextField(
              controller: _value,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText:
                    'Reported value (${_property == 'ph' ? 'pH' : 'g/kg'})',
              ),
            ),
            TextField(
              controller: _source,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Measurement source / laboratory',
              ),
            ),
            const Text(
              'Stored as a farmer-reported value. Laboratory verification and sampling depth remain unconfirmed.',
            ),
          ],
          if (_kind == 'soil_texture')
            const Text(
              'Describe the damp soil feel, ribbon, grittiness and sampling depth. This observation does not establish a laboratory texture classification.',
            ),
          TextField(
            controller: _notes,
            minLines: 3,
            maxLines: 6,
            maxLength: 2000,
            decoration: const InputDecoration(labelText: 'Your observations'),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          FilledButton(
            onPressed: _save,
            child: const Text('Save field record locally'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );
}
