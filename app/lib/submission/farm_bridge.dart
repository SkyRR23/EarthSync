import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/providers.dart' as team;
import '../evidence/data/models/farm_boundary.dart' as evidence;
import '../evidence/data/models/home_profile.dart';
import '../evidence/data/models/farmer_input.dart' as input;
import '../evidence/state/home_provider.dart';
import '../evidence/state/local_farm_provider.dart';
import '../evidence/state/providers.dart' as science;
import '../evidence/features/tasks/tasks_screen.dart';

final _linkQueueProvider = Provider<_LinkQueue>((ref) => _LinkQueue());

class _LinkQueue {
  Future<void> pending = Future.value();
  Future<T> run<T>(Future<T> Function() action) {
    final next = pending.then((_) => action());
    pending = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }
}

/// Keep the team's saved field and the retained evidence tools on one stable ID.
final selectedFarmBridgeProvider = FutureProvider<HomeProfile>((ref) {
  final draft = ref.watch(team.farmerDraftProvider);
  final queue = ref.read(_linkQueueProvider);
  return queue.run(() async {
    final profile = ref.read(homeProfileProvider.notifier);
    var saved = await ref.read(homeProfileProvider.future);
    if (!draft.hasLocation || !ref.mounted) return saved;
    final store = await ref.read(localFarmStoreProvider.future);
    final link = await store.setting('primary-farm-link-v1');
    final point = GeoPoint(draft.fieldLatitude!, draft.fieldLongitude!);
    final boundary = draft.hasFarm
        ? evidence.FarmBoundary([
            for (final corner in draft.farm!.corners)
              GeoPoint(corner.latitude, corner.longitude),
          ])
        : null;
    ConfirmedFarm? linked;
    for (final farm in saved.farms) {
      if (farm.id == link?['farm_id'] ||
          (link == null && farm.point == point)) {
        linked = farm;
        break;
      }
    }
    if (linked != null && saved.farm?.id != linked.id) {
      await profile.selectFarm(linked.id);
    }
    final name = (draft.farmName ?? '').trim();
    if (linked == null ||
        linked.point != point ||
        (linked.name ?? '') != name ||
        jsonEncode(linked.boundary?.toJson()) !=
            jsonEncode(boundary?.toJson())) {
      await profile.confirmFarm(
        point,
        name,
        createNew: linked == null,
        boundary: boundary,
      );
    }
    saved = await ref.read(homeProfileProvider.future);
    await store.saveSetting('primary-farm-link-v1', {
      'farm_id': saved.farm!.id,
    });
    if (!ref.mounted) return saved;
    final answers = ref.read(science.farmerDraftProvider.notifier);
    answers.setLocation(point.latitude, point.longitude);
    if (draft.currentCrop != null) answers.setCurrentCrop(draft.currentCrop!);
    if (draft.previousCrop != null) {
      answers.setPreviousCrop(draft.previousCrop!);
    }
    if (draft.plantingMonth != null) {
      answers.setPlantingMonth(draft.plantingMonth!);
    }
    if (draft.irrigation != null) {
      answers.setIrrigation(
        input.Irrigation.values.byName(draft.irrigation!.name),
      );
    }
    if (draft.drainage != null) {
      answers.setDrainage(input.Drainage.values.byName(draft.drainage!.name));
    }
    return saved;
  });
});

Future<void> deleteSubmissionData(WidgetRef ref) =>
    ref.read(_linkQueueProvider).run(() async {
      final reminders = ref.read(deviceRemindersProvider);
      if (reminders.supported) {
        for (final id in await reminders.pending()) {
          await reminders.cancel(id);
        }
      }
      final store = await ref.read(localFarmStoreProvider.future);
      await store.db.transaction((tx) async {
        for (final table in [
          'records',
          'photos',
          'settings',
          'reminder_ids',
          'outbox',
          'sync_versions',
        ]) {
          await tx.delete(table);
        }
      });
      await ref.read(profileStoreProvider).save(const HomeProfile());
      ref.invalidate(homeProfileProvider);
      ref.read(localRevisionProvider.notifier).changed();
    });

class FarmTasksTab extends ConsumerWidget {
  const FarmTasksTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(team.prefsProvider) == null) {
      return const Center(child: Text('Save a field to manage local tasks.'));
    }
    return ref
        .watch(selectedFarmBridgeProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              Center(child: Text('Local tasks could not open: $error')),
          data: (profile) => profile.farm == null
              ? const Center(child: Text('Choose your field first.'))
              : const TasksScreen(),
        );
  }
}
