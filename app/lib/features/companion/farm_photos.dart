import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/platform_farms.dart';
import '../../design/components/product.dart';
import '../../state/journal_provider.dart';
import '../../state/platform_provider.dart';
import '../photo_evidence/photo_picker.dart';
import '../photo_evidence/photo_evidence_models.dart';
import 'companion_copy.dart';
import 'soil_workflows.dart';

class FarmPhotosScreen extends ConsumerStatefulWidget {
  const FarmPhotosScreen({super.key, this.initialKind = 'crop'});
  final String initialKind;
  @override
  ConsumerState<FarmPhotosScreen> createState() => _FarmPhotosState();
}

class _FarmPhotosState extends ConsumerState<FarmPhotosScreen> {
  bool _busy = false;
  String? _error;
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(journalProvider);
    final snapshot = state.isLoading || state.hasError ? null : state.value;
    final client = ref.watch(platformFarmClientProvider);
    final prefix = snapshot == null
        ? ''
        : '${PlatformFarmClient.prefix}/farms/${snapshot.farmId}/photos';
    return Scaffold(
      appBar: AppBar(title: Text(CompanionCopy.text(context, 'Photos'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const PageHeader(
                title: 'Farm-owned photos',
                subtitle:
                    'Photos here belong to this exact confirmed farm revision. Existing private workspace photos remain in their original authorized store. No migration is automatic.',
              ),
              if (state.isLoading || _busy) const LinearProgressIndicator(),
              if (state.hasError || snapshot == null)
                const Text(
                  'Connect this farm to the local evidence service to manage its photos.',
                ),
              if (_error != null) Text(_error!),
              if (client != null && snapshot != null && !snapshot.cached)
                SoilWorkflows(
                  key: ValueKey(snapshot.farmId),
                  client: client,
                  farmId: snapshot.farmId,
                  initialKind: widget.initialKind,
                ),
              FilledButton.icon(
                onPressed:
                    _busy ||
                        snapshot == null ||
                        snapshot.cached ||
                        client == null
                    ? null
                    : () async {
                        setState(() {
                          _busy = true;
                          _error = null;
                        });
                        try {
                          final selected = await PlatformFieldPhotoPicker()
                              .pick(PhotoOrigin.gallery, readGps: false);
                          if (selected == null || !context.mounted) return;
                          if (!await confirmAction(
                                context,
                                title: 'Save photo to this farm?',
                                message:
                                    'Only sanitized pixels are sent to the private local service. No GPS or original metadata are retained. Upload time is not the observation date.',
                                confirmLabel: 'Save photo',
                              ) ||
                              !context.mounted) {
                            return;
                          }
                          await client.transport.request(
                            'POST',
                            prefix,
                            expectedStatus: 201,
                            bytes: selected.png,
                            contentType: 'image/png',
                          );
                          ref.invalidate(journalProvider);
                        } catch (e) {
                          if (mounted) {
                            setState(
                              () => _error =
                                  'Photo action failed: $e. Inspect the photo list before retrying an upload.',
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Choose and confirm photo'),
              ),
              TextButton(
                onPressed: () => context.push('/season'),
                child: const Text(
                  'Add a dated observation and attach saved photos',
                ),
              ),
              TextButton(
                onPressed: () => context.push('/photos'),
                child: const Text('Open original private workspace photos'),
              ),
              if (snapshot?.cached == true)
                const Text(
                  'Cached photo metadata only. Private image pixels are not available offline.',
                ),
              if (snapshot != null && snapshot.rows('photos').isEmpty)
                const Text('No farm-owned photos yet.'),
              for (final photo
                  in snapshot?.rows('photos') ?? <Map<String, dynamic>>[])
                SectionCard(
                  title: 'Photo ${photo['id']}',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Uploaded: ${DateTime.fromMillisecondsSinceEpoch(((photo['uploaded_at_epoch'] as num) * 1000).round(), isUtc: true).toIso8601String()}\nObservation date: record separately in the timeline.',
                      ),
                      if (client != null && snapshot?.cached == false)
                        _OwnedPhoto(
                          key: ValueKey('${snapshot!.farmId}:${photo['id']}'),
                          client: client,
                          path: '$prefix/${photo['id']}/image',
                        ),
                      const Text(
                        'Farmer-associated image · not a diagnosis. Original EXIF is removed.',
                      ),
                      TextButton(
                        onPressed:
                            _busy || snapshot?.cached == true || client == null
                            ? null
                            : () async {
                                if (!await confirmAction(
                                      context,
                                      title: 'Delete this photo?',
                                      message:
                                          'This removes the private farm photo. Existing journal references remain as historical links; image bytes will no longer be available.',
                                      confirmLabel: 'Delete',
                                    ) ||
                                    !context.mounted) {
                                  return;
                                }
                                setState(() {
                                  _busy = true;
                                  _error = null;
                                });
                                try {
                                  await client.transport.request(
                                    'DELETE',
                                    '$prefix/${photo['id']}',
                                    expectedStatus: 204,
                                  );
                                  ref.invalidate(journalProvider);
                                } catch (e) {
                                  if (mounted) {
                                    setState(
                                      () => _error =
                                          'Photo deletion could not complete: $e',
                                    );
                                  }
                                } finally {
                                  if (mounted) setState(() => _busy = false);
                                }
                              },
                        child: const Text('Delete photo'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OwnedPhoto extends StatefulWidget {
  const _OwnedPhoto({super.key, required this.client, required this.path});
  final PlatformFarmClient client;
  final String path;
  @override
  State<_OwnedPhoto> createState() => _OwnedPhotoState();
}

class _OwnedPhotoState extends State<_OwnedPhoto> {
  late final Future<Object?> _image = widget.client.transport.request(
    'GET',
    widget.path,
    expectedStatus: 200,
    contentType: 'image/png',
  );
  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _image,
    builder: (_, state) {
      if (state.hasError) {
        return const Text(
          'Private photo unavailable. No placeholder image has been substituted.',
        );
      }
      if (!state.hasData) return const LinearProgressIndicator();
      return Image.memory(
        Uint8List.fromList(state.data! as List<int>),
        height: 240,
        fit: BoxFit.contain,
        semanticLabel: 'Farmer-associated field photo',
      );
    },
  );
}
