import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class PlatformFailure implements Exception {
  const PlatformFailure(this.code, {this.retryable = false, this.validation});
  final String code;
  final bool retryable;
  final Map<String, dynamic>? validation;
  @override
  String toString() => '$code · retryable: $retryable';
}

/// One request per action. Mutations are never replayed on transport failures.
/// Each endpoint declares its status and response type, including empty 204.
class PlatformTransport {
  PlatformTransport(this.client, {required this.baseUri}) {
    if (!['localhost', '127.0.0.1', '::1'].contains(baseUri.host) ||
        !['http', 'https'].contains(baseUri.scheme) ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment ||
        !['', '/'].contains(baseUri.path)) {
      throw ArgumentError(
        'The private evidence platform requires a loopback origin.',
      );
    }
  }
  final http.Client client;
  final Uri baseUri;

  Future<Object?> request(
    String method,
    String path, {
    required int expectedStatus,
    Map<String, dynamic>? body,
    List<int>? bytes,
    String contentType = 'application/json',
    Duration timeout = const Duration(seconds: 30),
    Future<void>? abortTrigger,
  }) async {
    try {
      final request = abortTrigger == null
          ? http.Request(method, baseUri.resolve(path))
          : http.AbortableRequest(
              method,
              baseUri.resolve(path),
              abortTrigger: abortTrigger,
            );
      if (body != null || bytes != null) {
        request.headers['Content-Type'] = contentType;
      }
      if (body != null) request.body = jsonEncode(body);
      if (bytes != null) request.bodyBytes = bytes;
      // Include both send and body consumption in the same timeout.
      final response = await (() async => http.Response.fromStream(
        await client.send(request),
      ))().timeout(timeout);
      Object? data;
      // Upload request bytes and response metadata can have different formats.
      // Retain the declared-format fallback for transports without MIME headers.
      final responseMime = response.headers['content-type']
          ?.split(';')
          .first
          .trim();
      if (response.bodyBytes.isNotEmpty &&
          (responseMime == 'application/json' ||
              (responseMime == null && contentType == 'application/json'))) {
        try {
          data = jsonDecode(utf8.decode(response.bodyBytes));
        } on FormatException {
          if (response.statusCode == expectedStatus) rethrow;
        }
      }
      if (response.statusCode != expectedStatus) {
        final error = data is Map ? data['error'] : null;
        throw PlatformFailure(
          error is Map && error['code'] is String
              ? error['code'] as String
              : 'HTTP_${response.statusCode}',
          retryable: error is Map && error['retryable'] == true,
          validation: error is Map && error['validation'] is Map
              ? Map<String, dynamic>.from(error['validation'] as Map)
              : null,
        );
      }
      if (expectedStatus == 204) {
        if (response.bodyBytes.isNotEmpty) {
          throw const FormatException('Expected empty response');
        }
        return null;
      }
      return data ?? response.bodyBytes;
    } on PlatformFailure {
      rethrow;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const PlatformFailure('NETWORK_UNAVAILABLE', retryable: true);
    }
  }
}
