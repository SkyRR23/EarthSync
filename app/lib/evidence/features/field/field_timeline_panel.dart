import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/platform_farms.dart';
import '../../design/components/product.dart';

class FieldTimelinePanel extends StatefulWidget {
  const FieldTimelinePanel({
    super.key,
    required this.farm,
    required this.client,
  });
  final PlatformFarm farm;
  final PlatformFarmClient client;
  @override
  State<FieldTimelinePanel> createState() => _TimelineState();
}

class _TimelineState extends State<FieldTimelinePanel> {
  final _notes = TextEditingController();
  String _crop = '',
      _stage = 'unknown',
      _irrigation = 'unknown',
      _drainage = 'unknown';
  DateTime _date = DateTime.now(), _planting = DateTime.now();
  bool _hasPlanting = false, _busy = false;
  String? _error;
  List<Map<String, dynamic>> _reports = [], _events = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  Future<void> _load() async {
    try {
      final values = await Future.wait([
        widget.client.observations(widget.farm.id),
        widget.client.intelligence(widget.farm.id),
      ]);
      if (mounted) {
        setState(() {
          _reports = values[0];
          _events = values[1];
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Timeline unavailable: $e');
    }
  }

  Future<void> _pick(bool planting) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: planting ? _planting : _date,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (selected != null && mounted) {
      setState(() {
        if (planting) {
          _planting = selected;
          _hasPlanting = true;
        } else {
          _date = selected;
        }
      });
    }
  }

  Future<void> _save() async {
    if (_notes.text.trim().isEmpty ||
        (_hasPlanting && _planting.isAfter(_date))) {
      setState(
        () => _error =
            'Enter an observation. Planting cannot follow the observation date.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.reportObservation(widget.farm.id, {
        'observed_on': _day(_date),
        'planting_on': _hasPlanting ? _day(_planting) : null,
        'crop_name': _crop.trim().isEmpty ? null : _crop.trim(),
        'growth_stage': _stage,
        'irrigation': _irrigation,
        'drainage': _drainage,
        'notes': _notes.text.trim(),
      });
      _notes.clear();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = 'Report could not be saved: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _choices(
    String label,
    String value,
    List<String> values,
    ValueChanged<String> update,
  ) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: values
        .map(
          (v) =>
              DropdownMenuItem(value: v, child: Text(v.replaceAll('_', ' '))),
        )
        .toList(),
    onChanged: _busy ? null : (v) => setState(() => update(v!)),
  );
  @override
  Widget build(BuildContext context) {
    final events = <Map<String, dynamic>>[
      for (final r in _reports)
        {
          'date': r['observed_on'],
          'text':
              'Farmer report · ${r['crop_name'] ?? 'crop unknown'} · ${r['growth_stage']}\n${r['notes']}\nPlanting: ${r['planting_on'] ?? 'unknown'} · irrigation: ${r['irrigation']} · drainage: ${r['drainage']}',
        },
      for (final e in _events)
        {
          'date':
              e['result']?['retrieved_at'] ??
              DateTime.fromMillisecondsSinceEpoch(
                ((e['updated'] as num) * 1000).toInt(),
                isUtc: true,
              ).toIso8601String(),
          'text':
              'Source request · ${e['kind']} · ${e['status']}${e['error'] == null ? '' : ' · ${e['error']}'} · retrieval date, not a field observation',
        },
    ]..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    return SectionCard(
      title: 'Field timeline & farmer observations',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Your reports describe what you saw or were told. They are not independently verified satellite observations or laboratory measurements. Older farm revisions remain in the private archive.',
          ),
          Autocomplete<String>(
            optionsBuilder: (v) async => v.text.trim().isEmpty
                ? const <String>[]
                : await widget.client.cropNames(v.text),
            onSelected: (v) => _crop = v,
            fieldViewBuilder: (context, controller, focus, submit) => TextField(
              controller: controller,
              focusNode: focus,
              maxLength: 150,
              decoration: const InputDecoration(
                labelText:
                    'Current crop · search 7P identities or enter your report',
              ),
              onChanged: (v) => _crop = v,
            ),
          ),
          const Text(
            'Catalog names are reference identities, not crop recommendations. Unknown is allowed.',
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: _busy ? null : () => _pick(false),
                child: Text('Observation date: ${_day(_date)}'),
              ),
              TextButton(
                onPressed: _busy ? null : () => _pick(true),
                child: Text(
                  'Planting date: ${_hasPlanting ? _day(_planting) : 'unknown'}',
                ),
              ),
              if (_hasPlanting)
                TextButton(
                  onPressed: () => setState(() => _hasPlanting = false),
                  child: const Text('Planting unknown'),
                ),
            ],
          ),
          _choices('Farmer-reported growth stage', _stage, [
            'unknown',
            'establishment',
            'vegetative',
            'flowering',
            'fruiting',
            'maturing',
            'harvested',
          ], (v) => _stage = v),
          _choices('Farmer-reported water supply', _irrigation, [
            'unknown',
            'none',
            'rain_only',
            'supplemental',
            'regular',
          ], (v) => _irrigation = v),
          _choices('Farmer-reported drainage', _drainage, [
            'unknown',
            'standing_water_reported',
            'drains_freely_reported',
            'poor_drainage_reported',
          ], (v) => _drainage = v),
          TextField(
            controller: _notes,
            maxLength: 2000,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Field observation (farmer report)',
            ),
          ),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Save dated farmer report'),
          ),
          if (_error != null) Text(_error!),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: _load,
                child: const Text('Reload timeline'),
              ),
              TextButton(
                onPressed: () => context.push('/photos'),
                child: const Text('View dated private photos'),
              ),
            ],
          ),
          for (final e in events)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_note),
              title: Text(e['date'] as String),
              subtitle: Text(e['text'] as String),
            ),
          if (events.isEmpty)
            const Text('No saved timeline entries for this farm revision.'),
        ],
      ),
    );
  }
}
