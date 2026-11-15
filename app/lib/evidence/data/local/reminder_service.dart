import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'farm_store.dart';
import 'farm_task.dart';

abstract interface class ReminderPlatform {
  bool get supported;
  Future<bool> requestPermission();
  Future<List<int>> pending();
  Future<void> schedule(
    int id,
    FarmTask task,
    DateTime when, {
    required bool overdue,
  });
  Future<void> cancel(int id);
  Future<void> test();
}

class DeviceReminders implements ReminderPlatform {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _initializing;
  void Function(String)? onOpen;
  @override
  bool get supported =>
      !kIsWeb &&
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ].contains(defaultTargetPlatform);
  Future<void> _initialize() => _initializing ??= (() async {
    if (!supported) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_farm'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null) onOpen?.call(response.payload!);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse?.payload != null) {
      onOpen?.call(launch!.notificationResponse!.payload!);
    }
  })();
  @override
  Future<bool> requestPermission() async {
    if (!supported) return false;
    await _initialize();
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return await _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true) ??
        false;
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'earthsync_farm_tasks',
      'Farm task reminders',
      channelDescription: 'Activities and times chosen by the farmer',
      importance: Importance.defaultImportance,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );
  @override
  Future<List<int>> pending() async {
    if (!supported) return [];
    await _initialize();
    return [
      for (final item in await _plugin.pendingNotificationRequests()) item.id,
    ];
  }

  @override
  Future<void> cancel(int id) async {
    if (!supported) return;
    await _initialize();
    await _plugin.cancel(id: id);
  }

  @override
  Future<void> schedule(
    int id,
    FarmTask task,
    DateTime when, {
    required bool overdue,
  }) async {
    if (!supported) return;
    await _initialize();
    await _plugin.zonedSchedule(
      id: id,
      title: overdue ? 'Task still pending: ${task.title}' : task.title,
      body:
          'Your farm schedule. Open EarthSync to review or complete this activity.',
      scheduledDate: tz.TZDateTime.from(when, tz.getLocation(task.zone)),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload:
          '/tasks?task=${Uri.encodeComponent(task.id)}&farm=${Uri.encodeComponent(task.farmId)}',
    );
  }

  @override
  Future<void> test() async {
    if (!supported) {
      throw UnsupportedError(
        'System reminders are available on Android, iOS and macOS.',
      );
    }
    await _initialize();
    await _plugin.show(
      id: 2147483646,
      title: 'EarthSync reminder check',
      body: 'This is a test selected by you, not an agricultural warning.',
      notificationDetails: _details,
      payload: '/notifications',
    );
  }
}

class ReminderPlan {
  const ReminderPlan(this.key, this.task, this.at, this.overdue);
  final String key;
  final FarmTask task;
  final DateTime at;
  final bool overdue;
}

List<ReminderPlan> planReminders(
  List<FarmTask> tasks,
  ReminderPreferences preferences,
  DateTime now,
) {
  if (!preferences.enabled) return [];
  final plans = <ReminderPlan>[];
  for (final original in tasks.where((task) => task.pending && task.reminder)) {
    FarmTask? task = original;
    final localNow = tz.TZDateTime.from(now, tz.getLocation(original.zone));
    final start = DateTime.parse(original.day);
    final elapsed = original.recurrence == 'monthly'
        ? ((localNow.year - start.year) * 12 + localNow.month - start.month) ~/
              original.interval
        : DateTime.utc(localNow.year, localNow.month, localNow.day)
                  .difference(DateTime.utc(start.year, start.month, start.day))
                  .inDays ~/
              (original.interval * (original.recurrence == 'weekly' ? 7 : 1));
    // Keep the original missed reminder, then jump near today instead of
    // replaying months of old occurrences after a long offline interval.
    final skip = elapsed > 2 ? elapsed - 2 : 0;
    // The OS queue is bounded. Replenished on launch, resume and task changes.
    for (var count = 0; count < 32 && task != null; count++) {
      final due = preferences.afterQuietHours(
        task.due.subtract(Duration(minutes: task.reminderMinutes)),
      );
      final series = task.data['series_id'] ?? task.id;
      if (count == 0 || !due.isBefore(now.subtract(const Duration(days: 1)))) {
        plans.add(
          ReminderPlan('$series:${task.day}:due', original, due, false),
        );
      }
      if (preferences.overdue) {
        final overdueAt = preferences.afterQuietHours(
          task.due.add(const Duration(days: 1)),
        );
        if (count == 0 ||
            !overdueAt.isBefore(now.subtract(const Duration(days: 1)))) {
          plans.add(
            ReminderPlan(
              '$series:${task.day}:overdue',
              original,
              overdueAt,
              true,
            ),
          );
        }
      }
      task = task.next(now, steps: count == 0 && skip > 0 ? skip : 1);
      if (task != null && task.due.isAfter(now.add(const Duration(days: 90)))) {
        break;
      }
    }
  }
  plans.sort((a, b) => a.at.compareTo(b.at));
  return plans;
}

class ReminderService {
  ReminderService(this.store, this.platform);
  final LocalFarmStore store;
  final ReminderPlatform platform;
  Future<void> _pending = Future.value();
  Future<void> reconcile(
    List<FarmTask> tasks,
    ReminderPreferences preferences,
    DateTime now,
  ) {
    final action = _pending.then((_) async {
      final plans = planReminders(tasks, preferences, now);
      for (final plan in plans.where((p) => !p.at.isAfter(now))) {
        await store.notify(
          plan.task.farmId,
          plan.key,
          plan.overdue ? 'overdue_task' : 'task_reminder',
          plan.task.title,
          plan.overdue
              ? 'This farmer-scheduled activity is still pending.'
              : 'Your saved farm reminder.',
          plan.at,
          taskId: plan.task.id,
        );
      }
      if (!platform.supported) return;
      if (!preferences.enabled || !preferences.systemAllowed) {
        for (final id in await platform.pending()) {
          await platform.cancel(id);
        }
        return;
      }
      final wanted = <int, ReminderPlan>{};
      for (final plan in plans.where((p) => p.at.isAfter(now)).take(48)) {
        wanted[await store.reminderId(plan.key)] = plan;
      }
      final pending = await platform.pending();
      for (final id in pending) {
        if (!wanted.containsKey(id)) await platform.cancel(id);
      }
      // Scheduling an existing identifier replaces it rather than duplicating it.
      for (final entry in wanted.entries) {
        await platform.schedule(
          entry.key,
          entry.value.task,
          entry.value.at,
          overdue: entry.value.overdue,
        );
      }
    });
    _pending = action.catchError((Object _) {});
    return action;
  }
}
