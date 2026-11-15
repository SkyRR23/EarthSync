import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/export_file.dart';
import '../../design/tokens.dart';
import '../../state/home_provider.dart';
import '../../state/local_farm_provider.dart';

class LocalDataScreen extends ConsumerStatefulWidget {
  const LocalDataScreen({super.key});
  @override
  ConsumerState<LocalDataScreen> createState() => _LocalDataState();
}

class _LocalDataState extends ConsumerState<LocalDataScreen> {
  bool _busy = false;
  String? _message;
  Future<void> _run(Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final message = await action();
      if (mounted) setState(() => _message = message);
    } catch (error) {
      if (mounted) setState(() => _message = 'Could not complete: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final farm = ref.watch(homeProfileProvider).value?.farm;
    return Scaffold(
      appBar: AppBar(title: const Text('Local data & privacy')),
      body: ListView(
        padding: const EdgeInsets.all(FsSpace.lg),
        children: [
          Text(
            'Your farm records belong to you.',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const Text(
            'Daily management stays on this device. Existing server records are kept in their original store. No new Firebase sign-in or cloud push is required.',
          ),
          const SizedBox(height: FsSpace.lg),
          const Text(
            'Optional synchronization is unconfigured in this integration. Local changes are retained with stable IDs for a future reviewed adapter. Nothing is uploaded automatically.',
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_message != null) SelectableText(_message!),
          if (farm != null) ...[
            const SizedBox(height: FsSpace.md),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      final store = await ref.read(
                        localFarmStoreProvider.future,
                      );
                      final data = {
                        ...await store.exportFarm(farm.id),
                        'farm_profile': farm.toJson(),
                        'reminder_preferences': await store.setting(
                          'reminder_preferences',
                        ),
                      };
                      final location = await saveFarmExport(jsonEncode(data));
                      return 'Farm export saved: $location. It contains private notes and photos; store it carefully.';
                    }),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Export selected farm records'),
            ),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialog) => AlertDialog(
                          title: const Text('Delete local farm activity data?'),
                          content: const Text(
                            'This removes tasks, notification history, notes and private photos for the selected farm from this device. Your saved farm boundary and original server records remain. Export first if needed.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialog, false),
                              child: const Text('Keep my records'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(dialog, true),
                              child: const Text('Delete local activity data'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && mounted) {
                        await _run(() async {
                          final store = await ref.read(
                            localFarmStoreProvider.future,
                          );
                          await store.deleteFarm(farm.id);
                          ref.read(localRevisionProvider.notifier).changed();
                          await ref.read(reminderReconciliationProvider.future);
                          return 'Local farm activity data removed. Saved boundary and original server records were preserved.';
                        });
                      }
                    },
              child: const Text('Delete selected farm activity data'),
            ),
          ],
        ],
      ),
    );
  }
}
