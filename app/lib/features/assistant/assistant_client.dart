import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'assistant_models.dart';

abstract interface class AssistantService {
  Future<AssistantAnswer> ask({
    required String question,
    required AssistantContext context,
    String language = 'en',
    bool expanded = false,
  });
}

class AssistantUnavailable implements Exception {
  const AssistantUnavailable(this.code);
  final String code;
}

/// No demo substitution on an outage. Provider URLs in citations are never fetched.
class HttpAssistantService implements AssistantService {
  HttpAssistantService({
    required this.endpoint,
    this.client,
    this.timeout = const Duration(seconds: 15),
  });
  final Uri endpoint;
  final http.Client? client;
  final Duration timeout;

  @override
  Future<AssistantAnswer> ask({
    required String question,
    required AssistantContext context,
    String language = 'en',
    bool expanded = false,
  }) async {
    final local = [
      'localhost',
      '127.0.0.1',
      '10.0.2.2',
      '::1',
    ].contains(endpoint.host);
    if (!endpoint.hasAuthority ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.fragment.isNotEmpty ||
        !(endpoint.scheme == 'https' || (local && endpoint.scheme == 'http'))) {
      throw const AssistantUnavailable('configuration');
    }
    final transport = client ?? http.Client();
    try {
      final response = await transport
          .post(
            endpoint,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'schema_version': assistantVersion,
              'question': question,
              'language': language,
              'expanded': expanded,
              'context': context.toJson(),
            }),
          )
          .timeout(timeout);
      if (response.statusCode != 200) {
        throw AssistantUnavailable('http_${response.statusCode}');
      }
      final answer = AssistantAnswer.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
      if (answer.contextId != context.contextId ||
          answer.language != language) {
        throw const AssistantUnavailable('context_mismatch');
      }
      return answer;
    } on AssistantUnavailable {
      rethrow;
    } on TimeoutException {
      throw const AssistantUnavailable('timeout');
    } on http.ClientException {
      throw const AssistantUnavailable('unavailable');
    } on Object {
      throw const AssistantUnavailable('invalid_response');
    } finally {
      if (client == null) transport.close();
    }
  }
}
