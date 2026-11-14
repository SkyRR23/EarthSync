import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/home_provider.dart';
import '../../state/integration_provider.dart';
import '../photo_evidence/photo_evidence.dart';

class PhotosScreen extends ConsumerStatefulWidget {
  const PhotosScreen({super.key});
  @override
  ConsumerState<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends ConsumerState<PhotosScreen> {
  final _token = TextEditingController();
  final _picker = PlatformFieldPhotoPicker();
  String? _error;
  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final farm = ref.watch(homeProfileProvider).value?.farm;
    final repository = ref.watch(photoRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Private field photos')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('Local/demo workspace · no production accounts'),
              const Text(
                'The private workspace token grants access to all photos in that workspace. Farm IDs are farmer labels, not authorization. Only connect your own workspace. Use localhost or HTTPS; do not send this token over plain Wi-Fi HTTP. The token stays in session memory and must be entered again after refresh.',
              ),
              if (repository == null) ...[
                TextField(
                  controller: _token,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Private workspace token (from local setup)',
                  ),
                ),
                if (_error != null) Text(_error!),
                FilledButton(
                  onPressed: () async {
                    final token = _token.text.trim();
                    if (token.length < 32) {
                      setState(
                        () => _error =
                            'Enter the private token of at least 32 characters.',
                      );
                      return;
                    }
                    try {
                      ref.read(workspaceTokenProvider.notifier).connect(token);
                      await ref.read(photoRepositoryProvider)!.list();
                      _token.clear();
                      if (mounted) setState(() => _error = null);
                    } catch (_) {
                      ref.read(workspaceTokenProvider.notifier).connect(null);
                      if (mounted) {
                        setState(
                          () => _error =
                              'Could not connect. Check the private local workspace setup and token.',
                        );
                      }
                    }
                  },
                  child: const Text('Connect private workspace'),
                ),
              ] else ...[
                TextButton(
                  onPressed: () {
                    ref.read(workspaceTokenProvider.notifier).connect(null);
                  },
                  child: const Text('Disconnect workspace'),
                ),
                PhotoEvidencePanel(
                  repository: repository,
                  picker: _picker,
                  confirmedFarm: farm == null
                      ? null
                      : ConfirmedFarmReference(farm.id),
                  key: ValueKey('${farm?.id}:${farm?.point.label}'),
                  onChanged: () {
                    ref.invalidate(workspacePhotosProvider);
                    if (farm != null) {
                      ref.invalidate(
                        satelliteProvider(
                          environmentalKey(farm.point, farmId: farm.id),
                        ),
                      );
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
