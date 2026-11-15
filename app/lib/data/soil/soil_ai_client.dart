import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/soil_texture.dart';

/// Result of the photo soil check (backend `/api/v1/soil/estimate`).
class SoilEstimate {
  const SoilEstimate({
    required this.soilClass,
    required this.source,
    required this.confidence,
    required this.signs,
    required this.photoUsable,
    required this.reason,
    this.handTest,
  });

  /// Null = "unknown" (the AI would not guess).
  final SoilClass? soilClass;

  /// `ai_estimate` or `hand_test`.
  final String source;

  /// `low`, `medium` or `high`.
  final String confidence;
  final List<SoilSign> signs;
  final bool photoUsable;
  final String reason;
  final SoilClass? handTest;

  factory SoilEstimate.fromJson(Map<String, dynamic> j) => SoilEstimate(
    soilClass: soilClassFromName(j['soil_class'] as String?),
    source: j['source'] as String? ?? 'ai_estimate',
    confidence: j['confidence'] as String? ?? 'low',
    signs: [
      for (final s in (j['signs_seen'] as List? ?? const []))
        ?soilSignFromWire(s as String?),
    ],
    photoUsable: j['photo_usable'] as bool? ?? false,
    reason: j['reason'] as String? ?? '',
    handTest: soilClassFromName(j['hand_test'] as String?),
  );
}

class SoilAiException implements Exception {
  const SoilAiException(this.code, {this.retryable = true});
  final String code;
  final bool retryable;
  @override
  String toString() => 'SoilAiException($code)';
}

/// Sends the farmer's soil photos and hand-test answers to the backend, which
/// asks Claude for an estimate. The app never holds an AI key.
class SoilAiClient {
  SoilAiClient({
    this.baseUrl = const String.fromEnvironment(
      'BACKEND_URL',
      defaultValue: 'http://127.0.0.1:8000',
    ),
    this.client,
    this.timeout = const Duration(seconds: 90),
  });

  final String baseUrl;

  /// Injected in tests; a fresh client per call otherwise.
  final http.Client? client;
  final Duration timeout;

  Future<SoilEstimate> estimate({
    required List<File> photos,
    required Ribbon? ribbon,
    required Feel? feel,
    required Set<SoilSign> signs,
    double? latitude,
    double? longitude,
  }) async {
    final body = jsonEncode({
      'photos': [for (final f in photos) base64Encode(await f.readAsBytes())],
      'answers': {
        'ribbon': ribbon?.wire ?? 'unsure',
        'feel': feel?.name ?? 'unsure',
        'signs': [for (final s in signs) s.wire],
      },
      'latitude': ?latitude,
      'longitude': ?longitude,
    });
    final c = client ?? http.Client();
    try {
      final r = await c
          .post(
            Uri.parse(baseUrl).resolve('/api/v1/soil/estimate'),
            headers: {'content-type': 'application/json'},
            body: body,
          )
          .timeout(timeout);
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode == 200 && j['status'] == 'success') {
        return SoilEstimate.fromJson(j);
      }
      final e = (j['error'] as Map?) ?? const {};
      throw SoilAiException(
        e['code'] as String? ?? 'http_${r.statusCode}',
        retryable: e['retryable'] as bool? ?? true,
      );
    } on SoilAiException {
      rethrow;
    } catch (_) {
      throw const SoilAiException('unreachable');
    } finally {
      if (client == null) c.close();
    }
  }
}
