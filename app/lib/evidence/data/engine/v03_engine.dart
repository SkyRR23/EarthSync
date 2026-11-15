import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../src/rust/api/bridge.dart' as rust;
import '../service_client.dart';
import 'rust_engine.dart';

const v03Version = 'earthsync.engine.v0.3.0';

Object? _freeze(Object? value) => value is Map
    ? Map<String, dynamic>.unmodifiable(
        value.map((key, item) => MapEntry(key as String, _freeze(item))),
      )
    : value is List
    ? List<dynamic>.unmodifiable(value.map(_freeze))
    : value;

/// Explicit versioned request boundary. Rust additionally validates every nested
/// crop rule, date, source, observation and unit before producing findings.
class V03Request {
  V03Request.fromJson(Map<String, dynamic> document)
    : json = _freeze(document) as Map<String, dynamic> {
    if (json['schema_version'] != v03Version ||
        !['evidence_assessment', 'software_test'].contains(json['mode']) ||
        json['day_basis'] is! String ||
        (json['day_basis'] as String).trim().isEmpty ||
        !['historical', 'forecast'].contains(json['climate_intent']) ||
        json['history_complete'] is! bool ||
        json['sequential_field'] is! bool) {
      throw const FormatException('Invalid versioned v0.3 request.');
    }
    for (final key in [
      'sources',
      'catalog',
      'observations',
      'climate',
      'history',
      'scenarios',
      'photos',
    ]) {
      if (json[key] is! List ||
          (json[key] as List).any((item) => item is! Map<String, dynamic>)) {
        throw FormatException('Invalid v0.3 $key collection.');
      }
    }
  }
  final Map<String, dynamic> json;
  bool get synthetic => json['mode'] == 'software_test';
}

enum V03Status {
  supported('supported_by_supplied_evidence', 'Supported comparison'),
  conflict('conflicts_with_supplied_evidence', 'Documented conflict'),
  insufficient('insufficient_information', 'More information needed'),
  inapplicable('evidence_not_applicable', 'Evidence does not apply'),
  invalid('input_or_source_validation_failure', 'Input validation failed');

  const V03Status(this.wire, this.label);
  final String wire, label;
  static V03Status decode(Object? value) => values.firstWhere(
    (s) => s.wire == value,
    orElse: () => throw const FormatException('Unknown v0.3 status'),
  );
}

/// The full immutable wire document is retained alongside explicit typed status
/// decoding. No v0.2 presentation enum can collapse v0.3 evidence states.
class V03Result {
  V03Result._(this.envelope) {
    if (envelope['status'] == 'error') {
      if (envelope['schema_version'] != v03Version) {
        throw const FormatException('Wrong engine version');
      }
      final e = envelope['error'] as Map<String, dynamic>;
      if (V03Status.decode(e['status']) != V03Status.invalid ||
          e['path'] is! String ||
          e['message'] is! String) {
        throw const FormatException('Invalid v0.3 validation response');
      }
      return;
    }
    final d = data!;
    if (envelope['status'] != 'success' ||
        d['schema_version'] != v03Version ||
        d['software_test_only'] is! bool ||
        d['context'] is! Map ||
        d['limitations'] is! List ||
        d['candidates'] is! List) {
      throw const FormatException('Invalid v0.3 result');
    }
    for (final summary in summaries) {
      V03Status.decode(summary['status']);
      for (final f in summary['findings'] as List) {
        V03Status.decode(f['status']);
      }
      List<String>.from(summary['unknowns'] as List);
    }
    for (final finding in findings) {
      V03Status.decode(finding['status']);
      for (final key in [
        'source_ids',
        'input_ids',
        'unknowns',
        'limitations',
      ]) {
        List<String>.from(finding[key] as List);
      }
      if (finding['plan_id'] is! String ||
          finding['rule_id'] is! String ||
          finding['explanation'] is! String ||
          finding['software_test_only'] != d['software_test_only']) {
        throw const FormatException('Invalid finding');
      }
    }
  }
  factory V03Result.decode(Map<String, dynamic> envelope) =>
      V03Result._(_freeze(envelope) as Map<String, dynamic>);
  final Map<String, dynamic> envelope;
  Map<String, dynamic>? get data => envelope['data'] as Map<String, dynamic>?;
  Map<String, dynamic>? get validation =>
      envelope['error'] as Map<String, dynamic>?;
  bool get synthetic => data?['software_test_only'] == true;
  List<Map<String, dynamic>> get summaries =>
      (data?['summaries'] as List? ?? []).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get findings =>
      (data?['findings'] as List? ?? []).cast<Map<String, dynamic>>();
  Map<String, dynamic>? get context =>
      data?['context'] as Map<String, dynamic>?;
  List<String> get limitations =>
      List<String>.from(data?['limitations'] as List? ?? []);
}

class V03Engine {
  const V03Engine(this.service);
  final ServiceClient service;
  Future<V03Result> analyze(V03Request request) async {
    final Map<String, dynamic> output;
    if (kIsWeb) {
      output = await service.json('/api/engine/v03', body: request.json);
    } else {
      await RustEngine.init();
      // Same generated FRB string ABI, explicit version dispatch in Rust.
      output =
          jsonDecode(
                await rust.analyzeIntegrationJson(
                  requestJson: jsonEncode(request.json),
                ),
              )
              as Map<String, dynamic>;
    }
    return V03Result.decode(output);
  }
}
