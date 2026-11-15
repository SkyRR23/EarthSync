import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

Uri serviceBaseUri() {
  const configured = String.fromEnvironment('BACKEND_URL');
  return Uri.parse(
    configured.isNotEmpty
        ? configured
        : kIsWeb
        ? Uri.base.origin
        : 'https://fieldshift-yangon-2026.web.app',
  );
}

class ServiceFailure implements Exception {
  const ServiceFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class ServiceClient {
  ServiceClient(this.client, {Uri? baseUri})
    : baseUri = baseUri ?? serviceBaseUri();
  final http.Client client;
  final Uri baseUri;

  Future<Map<String, dynamic>> json(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
  }) async {
    try {
      final uri = baseUri.resolve(path);
      final response =
          await (body == null
                  ? client.get(uri, headers: headers)
                  : client.post(
                      uri,
                      headers: {'Content-Type': 'application/json', ...headers},
                      body: jsonEncode(body),
                    ))
              .timeout(const Duration(seconds: 30));
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        final error = data['error'];
        throw ServiceFailure(
          error is Map && error['message'] is String
              ? error['message'] as String
              : 'Service unavailable (HTTP ${response.statusCode}). Retry when it is running.',
        );
      }
      return data;
    } on ServiceFailure {
      rethrow;
    } catch (_) {
      throw const ServiceFailure(
        'Could not reach the service or read its response. No fixture data were substituted.',
      );
    }
  }
}
