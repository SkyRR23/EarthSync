import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/local/database.dart';
import '../data/local/farm_store.dart';
import '../data/local/farm_task.dart';
import '../data/local/reminder_service.dart';
import 'home_provider.dart';

final localFarmStoreProvider = FutureProvider<LocalFarmStore>((ref) async {
  final db = await openFarmDatabase();
  ref.onDispose(() {
    unawaited(db.close());
  });
  return LocalFarmStore(db);
});
final localRevisionProvider = NotifierProvider<LocalRevision, int>(
  LocalRevision.new,
);

class LocalRevision extends Notifier<int> {
  @override
  int build() => 0;
  void changed() => state++;
}

final localClockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(minutes: 1), (_) => DateTime.now());
});
final deviceRemindersProvider = Provider<DeviceReminders>(
  (ref) => DeviceReminders(),
);
final reminderServiceProvider = FutureProvider<ReminderService>(
  (ref) async => ReminderService(
    await ref.watch(localFarmStoreProvider.future),
    ref.watch(deviceRemindersProvider),
  ),
);
final reminderPreferencesProvider = FutureProvider<ReminderPreferences>((
  ref,
) async {
  ref.watch(localRevisionProvider);
  final store = await ref.watch(localFarmStoreProvider.future);
  return ReminderPreferences.fromJson(
    await store.setting('reminder_preferences') ?? {},
  );
});
final farmTasksProvider = FutureProvider<List<FarmTask>>((ref) async {
  ref.watch(localRevisionProvider);
  final id = ref.watch(homeProfileProvider).value?.farm?.id;
  if (id == null) return [];
  return (await ref.watch(localFarmStoreProvider.future)).tasks(id);
});
final localNotificationsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  ref.watch(localRevisionProvider);
  final profile = await ref.watch(homeProfileProvider.future);
  final store = await ref.watch(localFarmStoreProvider.future);
  final values = [
    for (final farm in profile.farms)
      for (final item in await store.records(farm.id, 'notification'))
        if (item['dismissed'] != true) item,
  ];
  values.sort(
    (a, b) => (b['timestamp'] as String).compareTo(a['timestamp'] as String),
  );
  return values;
});
Future<void> updateLocalFarm(
  WidgetRef ref,
  Future<void> Function(LocalFarmStore) change,
) async {
  final store = await ref.read(localFarmStoreProvider.future);
  await change(store);
  ref.read(localRevisionProvider.notifier).changed();
}

final reminderReconciliationProvider = FutureProvider<void>((ref) async {
  ref.watch(localClockProvider);
  ref.watch(localRevisionProvider);
  final profile = await ref.watch(homeProfileProvider.future);
  final store = await ref.watch(localFarmStoreProvider.future);
  final preferences = await ref.watch(reminderPreferencesProvider.future);
  final tasks = [
    for (final farm in profile.farms) ...await store.tasks(farm.id),
  ];
  final before = await store.db.rawQuery(
    "SELECT COUNT(*) AS n FROM records WHERE kind='notification'",
  );
  await (await ref.watch(
    reminderServiceProvider.future,
  )).reconcile(tasks, preferences, DateTime.now());
  final after = await store.db.rawQuery(
    "SELECT COUNT(*) AS n FROM records WHERE kind='notification'",
  );
  if (before.single['n'] != after.single['n'] && ref.mounted) {
    ref.invalidate(localNotificationsProvider);
  }
});
