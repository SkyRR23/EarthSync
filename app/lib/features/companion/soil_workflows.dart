import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../data/platform_farms.dart';
import '../../design/components/product.dart';
import '../photo_evidence/photo_picker.dart';
import '../photo_evidence/photo_evidence_models.dart';

class SoilWorkflows extends StatefulWidget {
  const SoilWorkflows({super.key, required this.client, required this.farmId});
  final PlatformFarmClient client;
  final String farmId;
  @override
  State<SoilWorkflows> createState() => _SoilWorkflowsState();
}

class _SoilWorkflowsState extends State<SoilWorkflows> {
  bool _busy = false;
  String? _message;
  Map<String, dynamic>? _appearance;
  List<Map<String, dynamic>> _reports = [];
  String get prefix => '${PlatformFarmClient.prefix}/farms/${widget.farmId}';

  Future<void> _act(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Action could not complete. Refresh reports before retrying an extraction.',
        );
      }
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
    if (mounted) {
      setState(() => _reports = List<Map<String, dynamic>>.from(data as List));
    }
  }

  Future<void> _upload(bool lab) => _act(() async {
    final selected = await PlatformFieldPhotoPicker().pick(
      PhotoOrigin.gallery,
      readGps: false,
    );
    if (selected == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          lab
              ? 'Upload a laboratory report?'
              : 'Upload an ordinary soil photo?',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.memory(selected.png, height: 200, fit: BoxFit.contain),
              Text(
                lab
                    ? 'Use an actual laboratory report, not a home-test strip. Local OCR may make mistakes. You must check and confirm every sample value.'
                    : 'Only visible appearance can be described. A photo cannot measure pH, NPK, salinity, carbon or moisture percentage.',
              ),
              const Text(
                'Sanitized pixels are stored privately by the local farm service. No external AI receives this image.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Upload'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final photo = Map<String, dynamic>.from(
      await widget.client.transport.request(
            'POST',
            '$prefix/photos',
            expectedStatus: 201,
            bytes: selected.png,
            contentType: 'image/png',
          )
          as Map,
    );
    if (!mounted) return;
    if (lab) {
      await widget.client.transport.request(
        'POST',
        '$prefix/photos/${photo['id']}/lab-extraction',
        expectedStatus: 201,
      );
      await _refresh();
    } else {
      final result = await widget.client.transport.request(
        'POST',
        '$prefix/photos/${photo['id']}/analyze',
        expectedStatus: 200,
      );
      if (mounted) {
        setState(() => _appearance = Map<String, dynamic>.from(result as Map));
      }
    }
  });

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Soil photos and laboratory reports',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Choose the workflow that matches the image. Appearance observations and measured sample values stay separate.',
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null) Text(_message!),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: _busy ? null : () => _upload(false),
              child: const Text('Ordinary soil photo'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _upload(true),
              child: const Text('Laboratory report'),
            ),
            TextButton(
              onPressed: _busy ? null : () => _act(_refresh),
              child: const Text('Load saved reports'),
            ),
          ],
        ),
        if (_appearance != null)
          EvidenceNotice(
            title: 'Soil appearance: ${_appearance!['status']}',
            message:
                'No vision provider is configured. No chemical measurements are available. Record dated observations in the farm timeline or obtain a laboratory test.',
          ),
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
                'Original OCR (retained separately from corrections):',
              ),
              _LabValues(
                data: Map<String, dynamic>.from(report['original'] as Map),
              ),
              if (report['confirmed'] != null)
                _LabValues(
                  data: Map<String, dynamic>.from(report['confirmed'] as Map),
                ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final pixels = widget.client.transport.request(
                          'GET',
                          '$prefix/photos/${report['photo_id']}/image',
                          expectedStatus: 200,
                          contentType: 'image/png',
                        );
                        final correction = await showDialog<Map<String, dynamic>>(
                          context: context,
                          builder: (_) => LabReportEditor(
                            report: report,
                            originalImage: FutureBuilder<Object?>(
                              future: pixels,
                              builder: (_, state) {
                                  if (state.hasError) {
                                  return const Text(
                                    'Original image unavailable. Cancel until you can check the report.',
                                  );
                                  }
                                  if (!state.hasData) {
                                  return const LinearProgressIndicator();
                                  }
                                return InteractiveViewer(
                                  child: Image.memory(
                                    Uint8List.fromList(
                                      state.data! as List<int>,
                                    ),
                                    height: 300,
                                    fit: BoxFit.contain,
                                    semanticLabel:
                                        'Original laboratory report for manual checking',
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
                      },
                child: const Text('Check, correct and confirm sample'),
              ),
            ],
          ),
      ],
    ),
  );
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
