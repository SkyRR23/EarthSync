// Independent harness: flutter run -d chrome -t example/photo_evidence_main.dart
// Serve through the same origin or configure the evidence service's exact CORS
// origin. The private workspace token is entered at runtime, never compiled in.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:earthsync/features/photo_evidence/photo_evidence.dart';

void main() => runApp(const MaterialApp(home: EvidenceExample()));

class EvidenceExample extends StatefulWidget {
  const EvidenceExample({super.key});
  @override
  State<EvidenceExample> createState() => _EvidenceExampleState();
}

class _EvidenceExampleState extends State<EvidenceExample> {
  final _url = TextEditingController(text: 'http://127.0.0.1:8017');
  final _token = TextEditingController();
  final _http = http.Client();
  final _picker = PlatformFieldPhotoPicker();
  PhotoEvidenceRepository? _repository;
  String? _error;

  @override
  void dispose() {
    _http.close();
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('EarthSync private photo workspace')),
    body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_repository == null) ...[
          TextField(controller: _url, decoration: const InputDecoration(labelText: 'Evidence service origin')),
          TextField(controller: _token, obscureText: true, enableSuggestions: false, autocorrect: false,
            decoration: const InputDecoration(labelText: 'Private workspace token')),
          FilledButton(onPressed: () {
            try {
              final repository = HttpPhotoEvidenceRepository(
                baseUri: Uri.parse(_url.text), token: _token.text, client: _http,
              );
              _token.clear();
              setState(() { _repository = repository; _error = null; });
            } catch (_) {
              setState(() => _error = 'Use HTTPS (or loopback) and a private token of at least 32 characters.');
            }
          }, child: const Text('Open workspace')),
          if (_error != null) Text(_error!),
        ] else ...[
          PhotoEvidencePanel(repository: _repository!, picker: _picker),
          TextButton(onPressed: () => setState(() => _repository = null), child: const Text('Close workspace')),
        ],
      ],
    )),
  );
}
