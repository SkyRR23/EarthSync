// Standalone entrypoint; shared navigation and onboarding are intentionally untouched.
import 'package:flutter/material.dart';

import 'features/assistant/assistant_client.dart';
import 'features/assistant/assistant_models.dart';
import 'features/assistant/assistant_screen.dart';

void main() {
  final service = HttpAssistantService(endpoint: Uri.parse(const String.fromEnvironment(
    'ASSISTANT_URL', defaultValue: 'http://127.0.0.1:8001/api/assistant/v1/chat')));
  runApp(MaterialApp(title: 'EarthSync assistant',
    theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
    home: FarmerAssistantScreen(context: AssistantContext(contextId: 'general:r1'), service: service)));
}
