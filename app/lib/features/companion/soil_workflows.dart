import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../data/platform_farms.dart';
import '../../data/platform_transport.dart';
import '../../design/components/product.dart';
import '../photo_evidence/photo_picker.dart';
import '../photo_evidence/photo_evidence_models.dart';
import 'companion_copy.dart';

class SoilWorkflows extends StatefulWidget {
  const SoilWorkflows({
    super.key,
    required this.client,
    required this.farmId,
    this.picker,
  });
  final PlatformFarmClient client;
  final String farmId;
  final FieldPhotoPicker? picker;
  @override
  State<SoilWorkflows> createState() => _SoilWorkflowsState();
}

class _SoilWorkflowsState extends State<SoilWorkflows> {
  bool _busy = false, _consent = false, _assist = false;
  String _kind = 'crop';
  String? _message, _photoId;
  PreparedPhoto? _selected;
  Map<String, dynamic>? _appearance, _capabilities;
  List<Map<String, dynamic>> _reports = [];
  final _crop = TextEditingController(),
      _question = TextEditingController(),
      _region = TextEditingController(),
      _growth = TextEditingController(),
      _weather = TextEditingController(),
      _symptoms = TextEditingController();
  late final FieldPhotoPicker _picker =
      widget.picker ?? PlatformFieldPhotoPicker();
  String get prefix => '${PlatformFarmClient.prefix}/farms/${widget.farmId}';
  String tr(String text) => CompanionCopy.text(context, text);

  @override
  void initState() {
    super.initState();
    _loadCapabilities();
  }

  Future<void> _loadCapabilities() async {
    try {
      final result = await widget.client.transport.request(
        'GET',
        '${PlatformFarmClient.prefix}/image-capabilities',
        expectedStatus: 200,
      );
      if (mounted)
        setState(
          () => _capabilities = Map<String, dynamic>.from(result as Map),
        );
    } catch (_) {
      if (mounted) setState(() => _capabilities = {'enabled': false});
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _crop,
      _question,
      _region,
      _growth,
      _weather,
      _symptoms,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _act(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on PlatformFailure catch (error) {
      if (mounted)
        setState(
          () => _message = error.code == 'EXTERNAL_IMAGE_CONSENT_REQUIRED'
              ? 'External processing requires explicit consent for this image.'
              : 'Action could not complete (${error.code}). Refresh reports before retrying extraction.',
        );
    } catch (_) {
      if (mounted)
        setState(
          () => _message =
              'Action could not complete. Refresh reports before retrying extraction.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    final data = await widget.client.transport.request(
      'GET',
      '$prefix/lab-reports',
      expectedStatus: 200,
    );
    if (mounted)
      setState(() => _reports = List<Map<String, dynamic>>.from(data as List));
  }

  Future<void> _choose(PhotoOrigin origin) => _act(() async {
    final selected = await _picker.pick(origin, readGps: false);
    if (selected != null && mounted)
      setState(() {
        _selected = selected;
        _photoId = null;
        _appearance = null;
        _consent = false;
      });
  });

  Future<void> _analyze() => _act(() async {
    if (_selected == null) return;
    try {
      if (_photoId == null) {
        final photo =
            await widget.client.transport.request(
                  'POST',
                  '$prefix/photos',
                  expectedStatus: 201,
                  bytes: _selected!.png,
                  contentType: 'image/png',
                )
                as Map;
        _photoId = photo['id'] as String;
      }
      if (_kind == 'lab') {
        await widget.client.transport.request(
          'POST',
          '$prefix/photos/$_photoId/lab-extraction',
          expectedStatus: 201,
          timeout: const Duration(seconds: 45),
          body: {
            'request_ai_assistance': _assist,
            'external_image_consent': _consent,
          },
        );
        await _refresh();
      } else {
        final result = await widget.client.transport.request(
          'POST',
          '$prefix/photos/$_photoId/analyze',
          expectedStatus: 200,
          body: {
            'image_kind': _kind,
            'crop': _crop.text.trim(),
            'question': _question.text.trim(),
            if (_region.text.trim().isNotEmpty) 'region': _region.text.trim(),
            'growth_stage': _growth.text.trim(),
            'weather_context': _weather.text.trim(),
            'farmer_symptoms': _symptoms.text.trim(),
            'external_image_consent': _consent,
          },
        );
        if (mounted)
          setState(
            () => _appearance = Map<String, dynamic>.from(result as Map),
          );
      }
    } finally {
      // Consent applies to one processing request, including transport failure.
      if (mounted) setState(() => _consent = false);
    }
  });

  Future<void> _edit(Map<String, dynamic> report, {bool ai = false}) async {
    final pixels = widget.client.transport.request(
      'GET',
      '$prefix/photos/${report['photo_id']}/image',
      expectedStatus: 200,
      contentType: 'image/png',
    );
    final correction = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => LabReportEditor(
        report: ai
            ? {
                ...report,
                'confirmed': null,
                'original': report['original']['ai_assistance'],
              }
            : report,
        originalImage: FutureBuilder<Object?>(
          future: pixels,
          builder: (_, state) {
            if (state.hasError)
              return const Text(
                'Original image unavailable. Cancel until you can check the report.',
              );
            if (!state.hasData) return const LinearProgressIndicator();
            return InteractiveViewer(
              child: Image.memory(
                Uint8List.fromList(state.data! as List<int>),
                height: 300,
                fit: BoxFit.contain,
                semanticLabel: 'Original laboratory report for manual checking',
              ),
            );
          },
        ),
      ),
    );
    if (correction == null || !mounted) return;
    await _act(() async {
      await widget.client.transport.request(
        'POST',
        '$prefix/lab-reports/${report['id']}/confirm',
        expectedStatus: 200,
        body: correction,
      );
      await _refresh();
    });
  }

  Future<void> _saveObservation() async {
    final notes = TextEditingController();
    final day = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (day == null || !mounted) {
      notes.dispose();
      return;
    }
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Confirm my observation')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Describe only what you personally observed. Model findings are not copied into confirmed history.',
            ),
            TextField(
              controller: notes,
              maxLength: 1500,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'My appearance observation',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (notes.text.trim().isNotEmpty)
                Navigator.pop(context, notes.text.trim());
            },
            child: Text(tr('Confirm my observation')),
          ),
        ],
      ),
    );
    // The dialog's closing animation may still reference its controller.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    notes.dispose();
    if (text == null || !mounted) return;
    await _act(() async {
      await widget.client.reportObservation(widget.farmId, {
        'observed_on': dateLabel(day),
        'notes': '$text\nAppearance observation; associated photo: $_photoId',
      });
      if (mounted)
        setState(
          () => _message = 'Saved as a farmer-reported appearance observation.',
        );
    });
  }

  Widget _input(String label, TextEditingController controller, int limit) =>
      TextField(
        controller: controller,
        enabled: !_busy,
        maxLength: limit,
        decoration: InputDecoration(labelText: tr(label)),
      );

  @override
  Widget build(BuildContext context) {
    final enabled = _capabilities?['enabled'] == true;
    final needsConsent = enabled && (_kind != 'lab' || _assist);
    return SectionCard(
      title: tr('Image evidence check'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(
              'Appearance observations and laboratory sample values stay separate.',
            ),
          ),
          if (_busy)
            const LinearProgressIndicator(
              semanticsLabel: 'Processing image evidence',
            ),
          if (_message != null) Text(_message!, semanticsLabel: _message),
          DropdownButtonFormField<String>(
            initialValue: _kind,
            decoration: InputDecoration(labelText: tr('Image category')),
            items: [
              for (final entry in {
                'crop': 'Crop / Leaf',
                'soil': 'Soil Appearance',
                'lab': 'Soil Laboratory Report',
              }.entries)
                DropdownMenuItem(
                  value: entry.key,
                  child: Text(tr(entry.value)),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _kind = value!;
                    _appearance = null;
                    _consent = false;
                    _assist = false;
                  }),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _busy ? null : () => _choose(PhotoOrigin.gallery),
                child: Text(tr('Choose image')),
              ),
              if (_picker.supportsCamera)
                OutlinedButton(
                  onPressed: _busy ? null : () => _choose(PhotoOrigin.camera),
                  child: Text(tr('Take photo')),
                ),
              TextButton(
                onPressed: _busy ? null : () => _act(_refresh),
                child: const Text('Load saved reports'),
              ),
            ],
          ),
          if (_selected != null)
            Image.memory(
              _selected!.png,
              height: 220,
              fit: BoxFit.contain,
              semanticLabel: 'Selected sanitized image preview',
            ),
          if (_kind != 'lab') ...[
            _input('Crop (farmer provided, optional)', _crop, 150),
            _input('Question about the image', _question, 1000),
            _input('Reference region filter (optional)', _region, 150),
            _input('Reported growth stage (optional)', _growth, 150),
            _input('Reported weather (optional)', _weather, 500),
            _input('Reported symptoms (optional)', _symptoms, 500),
          ] else ...[
            const Text(
              'Local Tesseract runs first. Check every value against the original report. Uploads are not independently authenticated.',
            ),
            CheckboxListTile(
              value: _assist,
              onChanged: !enabled || _busy
                  ? null
                  : (v) => setState(() {
                      _assist = v ?? false;
                      _consent = false;
                    }),
              title: const Text('Request optional AI document assistance'),
            ),
          ],
          if (!enabled)
            Text(
              tr(
                'External vision is unavailable. Local OCR and saved evidence still work.',
              ),
            ),
          if (needsConsent)
            CheckboxListTile(
              value: _consent,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _consent = v ?? false),
              title: Text(tr('I authorize external processing of this image')),
              subtitle: Text(
                'Sanitized pixels will be sent to ${_capabilities?['provider']} / ${_capabilities?['model']}. Image text can contain personal information.',
              ),
            ),
          FilledButton(
            onPressed: _busy || _selected == null || (needsConsent && !_consent)
                ? null
                : _analyze,
            child: Text(tr('Analyze image')),
          ),
          if (_appearance != null) ...[
            ImageEvidenceResult(packet: _appearance!),
            OutlinedButton(
              onPressed: _busy ? null : _saveObservation,
              child: Text(tr('Confirm my observation')),
            ),
          ],
          for (final report in _reports)
            ExpansionTile(
              key: ValueKey(report['id']),
              title: Text('Report ${report['id']}'),
              subtitle: Text(
                report['confirmed'] == null
                    ? '${report['original']['status']} · check before confirmation'
                    : 'User-confirmed sample transcription',
              ),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Original local OCR (retained separately from corrections):',
                ),
                _LabValues(
                  data: Map<String, dynamic>.from(report['original'] as Map),
                ),
                if (report['original']['ai_assistance'] != null) ...[
                  const Text(
                    'Unverified AI assistance (never automatically confirmed):',
                  ),
                  _LabValues(
                    data: Map<String, dynamic>.from(
                      report['original']['ai_assistance'] as Map,
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _edit(report, ai: true),
                    child: const Text(
                      'Check AI transcription against original image',
                    ),
                  ),
                ],
                if (report['confirmed'] != null)
                  _LabValues(
                    data: Map<String, dynamic>.from(report['confirmed'] as Map),
                  ),
                TextButton(
                  onPressed: _busy ? null : () => _edit(report),
                  child: const Text('Check, correct and confirm sample'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Render only the validated backend contract; no model prose is treated as a diagnosis.
class ImageEvidenceResult extends StatelessWidget {
  const ImageEvidenceResult({super.key, required this.packet});
  final Map<String, dynamic> packet;
  @override
  Widget build(BuildContext context) {
    String tr(String text) => CompanionCopy.text(context, text);
    final saved = packet['saved_environmental_evidence'] as Map? ?? {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${packet['status']} · ${packet['provider_status'] ?? ''}'),
        if (packet['provider'] != null)
          Text(
            '${packet['provider']} / ${packet['model']} · ${packet['latency_ms'] ?? '?'} ms',
          ),
        Text(tr('Visible findings')),
        for (final finding in packet['observations'] as List? ?? [])
          Text(
            '${finding['feature'].toString().replaceAll('_', ' ')} · ${finding['visibility']}',
          ),
        Text(tr('Possible causes to investigate')),
        for (final explanation
            in packet['possible_explanations'] as List? ?? []) ...[
          Text(explanation['reference_says'] as String),
          for (final possibility in explanation['possibilities'] as List? ?? [])
            Text('• $possibility'),
          for (final limit in explanation['limitations'] as List? ?? [])
            Text('• $limit'),
          Text(
            'Source: ${explanation['source_id']} · ${explanation['claim_id']}',
          ),
        ],
        if ((packet['possible_explanations'] as List? ?? []).isEmpty)
          const Text('No supported cause is inferred from this image.'),
        Text(tr('References')),
        for (final source in packet['sources'] as List? ?? [])
          SelectableText(
            '${source['title']}\n${source['publisher']}\n${source['url']}',
          ),
        for (final citation in packet['citations'] as List? ?? [])
          Text('${citation['source_id']}: ${citation['locator']}'),
        Text(tr('Limitations and missing information')),
        for (final item in [
          ...(packet['limitations'] as List? ?? []),
          ...(packet['missing_information'] as List? ?? []),
        ])
          Text('• $item'),
        Text(tr('Safe follow-up observations')),
        for (final item in packet['follow_up'] as List? ?? []) Text('• $item'),
        Text(tr('Saved environmental evidence (separate from the photo)')),
        for (final model
            in saved['modeled_regional_reference'] as List? ?? []) ...[
          Text(
            'Regional modeled SoilGrids pH · depth ${model['depth_cm']} cm · not measured from this photo',
          ),
          for (final cell in model['cells'] as List? ?? [])
            Text('pH: ${cell['value'] ?? 'unavailable'}'),
        ],
        for (final record in saved['saved_evidence_records'] as List? ?? [])
          ExpansionTile(
            title: Text('${record['provider']} · ${record['data_type']}'),
            subtitle: Text('${record['dataset']} · ${record['temporal']}'),
            children: [
              SelectableText('Source: ${record['source_url']}'),
              Text('${record['limitations']}'),
              for (final measurement in record['measurements'] as List? ?? [])
                Text(
                  '${measurement['parameter']}: ${measurement['value']} ${measurement['unit']}',
                ),
            ],
          ),
        for (final record in saved['saved_source_records'] as List? ?? [])
          Text(
            '${record['category']} · ${record['result']?['provider'] ?? 'source'} · ${record['result']?['retrieved_at'] ?? 'retrieval time unavailable'}',
          ),
        const Text(
          'Regional climate and forecast grids are not current station or field observations.',
        ),
        Text(
          'Farmer reports: ${(saved['farmer_reported'] as List? ?? []).length}; lab transcriptions: ${(saved['laboratory_sample_transcriptions'] as List? ?? []).length}. These do not confirm a visual cause.',
        ),
        if (saved['status'] != null) Text(saved['status'] as String),
      ],
    );
  }
}

class _LabValues extends StatelessWidget {
  const _LabValues({required this.data});
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Laboratory: ${data['laboratory'] ?? 'Not reported'}\nSample: ${data['sample_id'] ?? 'Not reported'}\nSample date: ${data['sample_date'] ?? 'Not reported'}',
      ),
      for (final value in data['values'] as List? ?? [])
        ListTile(
          title: Text(
            '${value['parameter']}: ${value['value']} ${value['unit']}',
          ),
          subtitle: Text(
            'Method: ${value['method'] ?? 'Not reported'} · Depth: ${value['depth'] ?? 'Not reported'}\n${value['source_locator']}',
          ),
        ),
      if ((data['unreadable_fields'] as List? ?? []).isNotEmpty)
        Text(
          'Missing or unreadable: ${(data['unreadable_fields'] as List).join(', ')}',
        ),
    ],
  );
}

class _Measurement {
  _Measurement(Map<String, dynamic> value)
    : parameter = value['parameter'] as String? ?? 'ph',
      value = TextEditingController(text: '${value['value'] ?? ''}'),
      unit = TextEditingController(text: value['unit'] as String? ?? 'pH'),
      method = TextEditingController(text: value['method'] as String? ?? ''),
      depth = TextEditingController(text: value['depth'] as String? ?? ''),
      locator = TextEditingController(
        text: value['source_locator'] as String? ?? 'image 1, manually checked',
      ),
      referenceRange = TextEditingController(
        text: value['reference_range'] as String? ?? '',
      );
  String parameter;
  final TextEditingController value,
      unit,
      method,
      depth,
      locator,
      referenceRange;
  void dispose() {
    for (final c in [value, unit, method, depth, locator, referenceRange]) {
      c.dispose();
    }
  }

  Map<String, dynamic> toJson() => {
    'parameter': parameter,
    'value': double.parse(value.text),
    'unit': unit.text.trim(),
    'source_locator': locator.text.trim(),
    if (method.text.trim().isNotEmpty) 'method': method.text.trim(),
    if (depth.text.trim().isNotEmpty) 'depth': depth.text.trim(),
    if (referenceRange.text.trim().isNotEmpty)
      'reference_range': referenceRange.text.trim(),
  };
}

class LabReportEditor extends StatefulWidget {
  const LabReportEditor({super.key, required this.report, this.originalImage});
  final Map<String, dynamic> report;
  final Widget? originalImage;
  @override
  State<LabReportEditor> createState() => _LabReportEditorState();
}

class _LabReportEditorState extends State<LabReportEditor> {
  final _form = GlobalKey<FormState>();
  late final Map _initial =
      widget.report['confirmed'] as Map? ?? widget.report['original'] as Map;
  late final _sample = TextEditingController(
    text: _initial['sample_id'] as String? ?? '',
  );
  late final _lab = TextEditingController(
    text: _initial['laboratory'] as String? ?? '',
  );
  late final _date = TextEditingController(
    text: _initial['sample_date'] as String? ?? '',
  );
  late final List<_Measurement> _values = [
    for (final v in _initial['values'] as List? ?? [])
      _Measurement(Map<String, dynamic>.from(v as Map)),
  ];
  bool _confirmed = false;
  @override
  void dispose() {
    _sample.dispose();
    _lab.dispose();
    _date.dispose();
    for (final v in _values) {
      v.dispose();
    }
    super.dispose();
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool required = false,
    bool numeric = false,
  }) => TextFormField(
    controller: controller,
    decoration: InputDecoration(labelText: label),
    maxLength: 150,
    validator: (text) {
      if (required && (text == null || text.trim().isEmpty)) {
        return 'Required from the report';
      }
      if (numeric) {
        final n = double.tryParse(text ?? '');
        if (n == null || !n.isFinite || n < 0) {
          return 'Enter the reported nonnegative number';
        }
      }
      return null;
    },
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Confirm laboratory sample values'),
    content: SizedBox(
      width: 600,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.originalImage != null) widget.originalImage!,
              const Text(
                'Check the original image. Keep units, method and sampling depth exactly as reported. Leave absent fields blank. Confirm one sample only; enter different depths separately. This does not authenticate the laboratory or represent the entire field.',
              ),
              _field('Sample ID', _sample, required: true),
              _field('Laboratory name (if reported)', _lab),
              TextFormField(
                controller: _date,
                decoration: const InputDecoration(
                  labelText: 'Sample date YYYY-MM-DD (if reported)',
                ),
                validator: (text) =>
                    (text ?? '').isNotEmpty &&
                        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text!)
                    ? 'Use YYYY-MM-DD'
                    : null,
              ),
              for (final measurement in _values)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: measurement.parameter,
                          decoration: const InputDecoration(
                            labelText: 'Reported parameter',
                          ),
                          items: [
                            for (final name in [
                              'ph',
                              'nitrogen',
                              'phosphorus',
                              'potassium',
                              'organic_matter',
                              'organic_carbon',
                              'salinity',
                            ])
                              DropdownMenuItem(
                                value: name,
                                child: Text(name.replaceAll('_', ' ')),
                              ),
                          ],
                          onChanged: (value) => measurement.parameter = value!,
                        ),
                        _field(
                          'Reported value',
                          measurement.value,
                          required: true,
                          numeric: true,
                        ),
                        _field(
                          'Original units',
                          measurement.unit,
                          required: true,
                        ),
                        _field('Test method (if reported)', measurement.method),
                        _field(
                          'Sampling depth (if reported)',
                          measurement.depth,
                        ),
                        _field(
                          'Reference range (only if printed)',
                          measurement.referenceRange,
                        ),
                        _field(
                          'Image/page/row locator',
                          measurement.locator,
                          required: true,
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            _values.remove(measurement);
                            measurement.dispose();
                          }),
                          child: const Text('Remove value'),
                        ),
                      ],
                    ),
                  ),
                ),
              TextButton(
                onPressed: _values.length >= 30
                    ? null
                    : () => setState(() => _values.add(_Measurement({}))),
                child: const Text('Add reported measurement'),
              ),
              CheckboxListTile(
                value: _confirmed,
                onChanged: (v) => setState(() => _confirmed = v ?? false),
                title: const Text(
                  'I checked these values against an actual laboratory report.',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: !_confirmed || _values.isEmpty
            ? null
            : () {
                if (!_form.currentState!.validate()) return;
                Navigator.pop(context, {
                  'confirmed': true,
                  'document_kind': 'laboratory_report',
                  'sample_id': _sample.text.trim(),
                  if (_lab.text.trim().isNotEmpty)
                    'laboratory': _lab.text.trim(),
                  if (_date.text.isNotEmpty) 'sample_date': _date.text,
                  'values': [for (final v in _values) v.toJson()],
                });
              },
        child: const Text('Confirm checked values'),
      ),
    ],
  );
}
