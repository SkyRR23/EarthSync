import 'dart:convert';
import 'package:http/http.dart' as http;

/// Keep a hosting error page distinct from a phone connectivity failure.
Map<String, dynamic>? backendJson(http.Response response) {
  try {
    final value = jsonDecode(response.body);
    return value is Map<String, dynamic> ? value : null;
  } on FormatException {
    return null;
  }
}

String backendFailure(http.Response response) => switch (response.statusCode) {
  401 || 403 => 'backend_access_denied',
  404 => 'backend_route_missing',
  >= 500 => 'backend_unavailable',
  _ => 'backend_invalid_response',
};

String backendMessage(String code) => switch (code) {
  'backend_route_missing' => 'The service address has no matching API route. The server needs an update; Wi-Fi alone will not fix this.',
  'backend_access_denied' => 'The server refused access. The service owner needs to check its access settings.',
  'backend_unavailable' => 'The server is unavailable right now. Your saved records are still available.',
  'backend_invalid_response' => 'The server returned an unexpected response. Please report this to the service owner.',
  'not_configured' || 'ai_key_rejected' => 'The AI service needs configuration on the server. Your phone connection may be working.',
  _ => 'Could not reach the service. This may be a server, network or timeout problem. Please try again.',
};
