import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:earthsync/data/local/database.dart';
import 'package:earthsync/data/local/farm_store.dart';
import 'package:earthsync/data/local/farm_task.dart';
import 'package:earthsync/data/local/reminder_service.dart';

FarmTask task({Map<String, dynamic> changes = const {}}) => FarmTask({
  'id': 'test-task',
  'farm_id': 'test-farm',
  'owner': 'device-local',
  'category': 'soil_moisture',
  'title': 'Synthetic test: inspect soil',
  'description': 'Software test only',
  'due_date': '2026-11-16',
  'minute_of_day': 540,
  'timezone': 'Asia/Yangon',
  'status': 'pending',
  'priority': 'normal',
  'created_at': '2026-11-15T00:00:00Z',
  'updated_at': '2026-11-15T00:00:00Z',
  'reminder': true,
  'reminder_minutes': 0,
  'recurrence': 'none',
  'interval': 1,
  'origin': 'manual',
  ...changes,
});

class FakeReminders implements ReminderPlatform {
  @override
  bool supported = true;
  bool allowed = true;
  final scheduled = <int, DateTime>{};
  final canceled = <int>[];
  @override
  Future<bool> requestPermission() async => allowed;
  @override
  Future<List<int>> pending() async => scheduled.keys.toList();
  @override
  Future<void> schedule(
    int id,
    FarmTask task,
    DateTime when, {
    required bool overdue,
  }) async {
    scheduled[id] = when;
  }

  @override
  Future<void> cancel(int id) async {
    canceled.add(id);
    scheduled.remove(id);
  }

  @override
  Future<void> test() async {}
}

void main() {
  late Database db;
  late LocalFarmStore store;
  setUpAll(() {
    sqfliteFfiInit();
    initializeFarmTimeZones();
  });
  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: createFarmSchema,
        singleInstance: false,
      ),
    );
    store = LocalFarmStore(db);
  });
  tearDown(() => db.close());

  test('create, edit and delete tasks without network or account', () async {
    await store.saveTask(task());
    expect(
      (await store.tasks('test-farm')).single.title,
      contains('inspect soil'),
    );
    await store.saveTask(task().withChanges({'title': 'Edited activity'}));
    expect((await store.tasks('test-farm')).single.title, 'Edited activity');
    expect(await store.tasks('another-farm'), isEmpty);
    await store.deleteTask(task());
    expect(await store.tasks('test-farm'), isEmpty);
    expect((await store.db.query('outbox')).single['status'], 'pending');
  });
  test(
    'long offline recurring schedules retain future reminders without replaying a backlog',
    () {
      final now = DateTime.utc(2026, 11, 15, 12);
      final plans = planReminders(
        [
          task(changes: {'due_date': '2020-01-01', 'recurrence': 'daily'}),
        ],
        const ReminderPreferences(enabled: true),
        now,
      );
      expect(plans.where((plan) => plan.at.isAfter(now)), isNotEmpty);
      expect(
        plans.where((plan) => plan.at.isBefore(now)).length,
        lessThanOrEqualTo(6),
      );
      expect(plans.map((plan) => plan.key).toSet().length, plans.length);
    },
  );
  test('complete and reopen retains original creation identity', () async {
    final now = DateTime.utc(2026, 11, 16);
    await store.saveTask(task());
    await store.setTaskStatus(task(), 'completed', now);
    var current = (await store.tasks('test-farm')).single;
    expect(current.data['completed_at'], now.toIso8601String());
    await store.setTaskStatus(current, 'pending', now);
    current = (await store.tasks('test-farm')).single;
    expect(current.id, 'test-task');
    expect(current.data['completed_at'], isNull);
  });
  test(
    'repeated completion materializes exactly one recurring successor',
    () async {
      final repeated = task(changes: {'recurrence': 'weekly'});
      await store.saveTask(repeated);
      await store.setTaskStatus(
        repeated,
        'completed',
        DateTime.utc(2026, 11, 16),
      );
      await store.setTaskStatus(
        repeated,
        'completed',
        DateTime.utc(2026, 11, 16),
      );
      final rows = await store.tasks('test-farm');
      expect(rows.length, 2);
      expect(rows.singleWhere((row) => row.pending).day, '2026-11-23');
    },
  );
  test('monthly recurrence keeps the original day through short months', () {
    final first = task(
      changes: {'due_date': '2027-01-31', 'recurrence': 'monthly'},
    );
    final february = first.next(DateTime.utc(2027, 1, 31))!;
    expect(february.day, '2027-02-28');
    expect(february.next(DateTime.utc(2027, 2, 28))!.day, '2027-03-31');
  });
  test('daily recurrence uses civil calendar across daylight saving', () {
    final first = task(
      changes: {
        'due_date': '2026-03-07',
        'timezone': 'America/New_York',
        'recurrence': 'daily',
      },
    );
    final next = first.next(DateTime.utc(2026, 3, 7))!;
    expect(next.due.hour, 9);
    expect(next.due.difference(first.due).inHours, 23);
  });
  test('date-only task becomes overdue at its own next midnight', () {
    final current = task(changes: {'minute_of_day': null, 'timezone': 'UTC'});
    expect(current.overdue(DateTime.utc(2026, 11, 16, 23, 59, 59)), false);
    expect(current.overdue(DateTime.utc(2026, 11, 17)), true);
    expect(current.today(DateTime.utc(2026, 11, 16)), true);
  });
  test('quiet hours defer overnight and same-day windows', () {
    const overnight = ReminderPreferences(zone: 'UTC');
    expect(
      overnight.afterQuietHours(DateTime.utc(2026, 11, 16, 23)).toUtc(),
      DateTime.utc(2026, 11, 17, 7),
    );
    const daytime = ReminderPreferences(
      zone: 'UTC',
      quietStart: 12 * 60,
      quietEnd: 14 * 60,
    );
    expect(
      daytime.afterQuietHours(DateTime.utc(2026, 11, 16, 13)).toUtc(),
      DateTime.utc(2026, 11, 16, 14),
    );
  });
  test(
    'reconciliation replaces reminders and cancels after completion',
    () async {
      final device = FakeReminders();
      final service = ReminderService(store, device);
      const preferences = ReminderPreferences(
        enabled: true,
        systemAllowed: true,
        zone: 'UTC',
      );
      final now = DateTime.utc(2026, 11, 15);
      await service.reconcile([task()], preferences, now);
      final ids = device.scheduled.keys.toSet();
      await service.reconcile([task()], preferences, now);
      expect(device.scheduled.keys.toSet(), ids);
      await service.reconcile(
        [
          task(changes: {'due_date': '2026-11-18'}),
        ],
        preferences,
        now,
      );
      expect(device.canceled.toSet().containsAll(ids), true);
      await service.reconcile([], preferences, now);
      expect(device.scheduled, isEmpty);
    },
  );
  test(
    'permission denied keeps in-app center without system schedules',
    () async {
      final device = FakeReminders()..allowed = false;
      final service = ReminderService(store, device);
      expect(await device.requestPermission(), false);
      await service.reconcile(
        [task()],
        const ReminderPreferences(enabled: true),
        DateTime.utc(2026, 11, 18),
      );
      expect(device.scheduled, isEmpty);
      expect(await store.records('test-farm', 'notification'), isNotEmpty);
    },
  );
  test(
    'notification read state and dismissal survive duplicate reconciliation',
    () async {
      final service = ReminderService(
        store,
        FakeReminders()..supported = false,
      );
      const preferences = ReminderPreferences(enabled: true);
      final now = DateTime.utc(2026, 11, 18);
      await service.reconcile([task()], preferences, now);
      final notification = (await store.records(
        'test-farm',
        'notification',
      )).first;
      await store.put('test-farm', 'notification', {
        ...notification,
        'read': true,
        'dismissed': true,
      });
      await service.reconcile([task()], preferences, now);
      final restored = (await store.records(
        'test-farm',
        'notification',
      )).firstWhere((row) => row['id'] == notification['id']);
      expect(restored['read'], true);
      expect(restored['dismissed'], true);
      expect((await store.records('test-farm', 'notification')).length, 2);
    },
  );
  test(
    'exports and farm deletion include notes, tasks, notifications and photos',
    () async {
      await store.saveTask(task());
      await store.put('test-farm', 'journal', {
        'id': 'note',
        'notes': 'Synthetic record',
      });
      await store.savePhoto(
        'test-farm',
        'photo',
        'image/png',
        Uint8List.fromList([1, 2, 3]),
        {'source': 'synthetic_test'},
      );
      await store.notify(
        'test-farm',
        'notification',
        'application',
        'Test',
        'Synthetic',
        DateTime.utc(2026),
      );
      await store.saveSetting('earthsync.journal.v1.test.test-farm.revision', {
        'entries': [],
      });
      final exported = await store.exportFarm('test-farm');
      expect((exported['records'] as List).length, 3);
      expect((exported['photos'] as List).length, 1);
      expect((exported['cached_farm_evidence'] as List).length, 1);
      await store.deleteFarm('test-farm');
      expect(await store.tasks('test-farm'), isEmpty);
      expect(await store.photos('test-farm'), isEmpty);
      expect(await store.db.query('outbox'), isEmpty);
      expect(
        await store.setting('earthsync.journal.v1.test.test-farm.revision'),
        isNull,
      );
    },
  );
  test('SQLite survives closing and reopening an actual local file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'earthsync-synthetic-persistence-',
    );
    final path = '${directory.path}/test.sqlite3';
    final first = await databaseFactoryFfiNoIsolate.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 1, onCreate: createFarmSchema),
    );
    await LocalFarmStore(first).saveTask(task());
    await first.close();
    final reopened = await databaseFactoryFfiNoIsolate.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 1),
    );
    expect(
      (await LocalFarmStore(reopened).tasks('test-farm')).single.id,
      'test-task',
    );
    await reopened.close();
    final resolved = directory.resolveSymbolicLinksSync();
    final tempRoot = Directory.systemTemp.resolveSymbolicLinksSync();
    if (!resolved.startsWith('$tempRoot${Platform.pathSeparator}') ||
        !directory.path.contains('earthsync-synthetic-persistence-')) {
      throw StateError('Unsafe test cleanup');
    }
    await directory.delete(recursive: true);
  });
}
