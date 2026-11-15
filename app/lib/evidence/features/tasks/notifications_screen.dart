import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../data/local/farm_task.dart';
import '../../design/tokens.dart';
import '../../state/home_provider.dart';
import '../../state/local_farm_provider.dart';

class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = (ref.watch(localNotificationsProvider).value ?? [])
        .where((n) => n['read'] != true)
        .length;
    return IconButton(
      tooltip: 'Notifications, $count unread',
      onPressed: () => context.push('/notifications'),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsState();
}

class _NotificationsState extends ConsumerState<NotificationsScreen> {
  bool _busy = false;
  String? _message;
  Future<void> _act(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Could not update notifications: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _read(Map<String, dynamic> item, bool read) => updateLocalFarm(
    ref,
    (store) => store.put(item['farm_id'] as String, 'notification', {
      ...item,
      'read': read,
    }),
  );
  Future<void> _preferences(
    ReminderPreferences preferences,
    Map<String, dynamic> changes,
  ) => updateLocalFarm(
    ref,
    (store) => store.saveSetting('reminder_preferences', {
      ...preferences.toJson(),
      ...changes,
    }),
  );
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(localNotificationsProvider);
    final items = state.value ?? [];
    final farms = ref.watch(homeProfileProvider).value?.farms ?? [];
    final farmNames = {
      for (final farm in farms) farm.id: farm.name ?? 'My Farm',
    };
    final preferences =
        ref.watch(reminderPreferencesProvider).value ??
        const ReminderPreferences();
    final device = ref.watch(deviceRemindersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: _busy || items.isEmpty
                ? null
                : () => _act(() async {
                    for (final item in items) {
                      await _read(item, true);
                    }
                  }),
            child: const Text('Read all'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(FsSpace.lg),
            children: [
              Text(
                'A helpful nudge, on your terms.',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: FsSpace.md),
              if (_busy || state.isLoading)
                const LinearProgressIndicator(
                  semanticsLabel: 'Loading notifications',
                ),
              if (_message != null) Text(_message!, semanticsLabel: _message),
              if (state.hasError)
                Text('Notification history could not be read: ${state.error}'),
              Card(
                child: ExpansionTile(
                  title: const Text('Notification preferences'),
                  children: [
                    SwitchListTile(
                      title: const Text('Farm task reminders'),
                      subtitle: const Text(
                        'Saved locally. No account or internet required.',
                      ),
                      value: preferences.enabled,
                      onChanged: _busy
                          ? null
                          : (value) => _act(() async {
                              var zone = preferences.zone;
                              if (value) {
                                try {
                                  zone =
                                      (await FlutterTimezone.getLocalTimezone())
                                          .identifier;
                                  initializeFarmTimeZones();
                                  tz.getLocation(zone);
                                } catch (_) {
                                  zone = preferences.zone;
                                }
                              }
                              await _preferences(preferences, {
                                'enabled': value,
                                'timezone': zone,
                              });
                            }),
                    ),
                    SwitchListTile(
                      title: const Text('One overdue follow-up'),
                      value: preferences.overdue,
                      onChanged: _busy
                          ? null
                          : (value) => _act(
                              () =>
                                  _preferences(preferences, {'overdue': value}),
                            ),
                    ),
                    ListTile(
                      title: const Text('Quiet hours'),
                      subtitle: Text(
                        '${_clock(preferences.quietStart)} to ${_clock(preferences.quietEnd)} · ${preferences.zone}',
                      ),
                      trailing: const Icon(Icons.bedtime_outlined),
                      onTap: _busy
                          ? null
                          : () => _act(() async {
                              final start = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay(
                                  hour: preferences.quietStart ~/ 60,
                                  minute: preferences.quietStart % 60,
                                ),
                              );
                              if (start == null || !context.mounted) return;
                              final end = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay(
                                  hour: preferences.quietEnd ~/ 60,
                                  minute: preferences.quietEnd % 60,
                                ),
                              );
                              if (end == null || !mounted) return;
                              var zone = preferences.zone;
                              try {
                                zone =
                                    (await FlutterTimezone.getLocalTimezone())
                                        .identifier;
                                tz.getLocation(zone);
                              } catch (_) {
                                zone = preferences.zone;
                              }
                              await _preferences(preferences, {
                                'quiet_start': start.hour * 60 + start.minute,
                                'quiet_end': end.hour * 60 + end.minute,
                                'timezone': zone,
                              });
                            }),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(FsSpace.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            device.supported
                                ? preferences.systemAllowed
                                      ? 'Device permission granted at last check. OS settings can still silence reminders.'
                                      : 'Enable device permission to schedule system reminders.'
                                : 'This platform supports in-app reminders while EarthSync is open. Background system scheduling is unavailable here.',
                          ),
                          if (device.supported)
                            FilledButton(
                              onPressed: _busy
                                  ? null
                                  : () => _act(() async {
                                      final granted = await device
                                          .requestPermission();
                                      var zone = preferences.zone;
                                      try {
                                        zone =
                                            (await FlutterTimezone.getLocalTimezone())
                                                .identifier;
                                      } catch (_) {
                                        /* Keep visible saved zone. */
                                      }
                                      await _preferences(preferences, {
                                        'system_allowed': granted,
                                        'enabled': true,
                                        'timezone': zone,
                                      });
                                      if (mounted) {
                                        setState(
                                          () => _message = granted
                                              ? 'Device reminders enabled. Your task schedules are being restored.'
                                              : 'Permission was not granted. In-app reminders still work. You can change device settings later.',
                                        );
                                      }
                                    }),
                              child: const Text('Enable device reminders'),
                            ),
                          if (device.supported && preferences.systemAllowed)
                            OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () => _act(() async {
                                      await device.test();
                                      if (mounted) {
                                        setState(
                                          () => _message =
                                              'Test notification requested. Confirm delivery on your device.',
                                        );
                                      }
                                    }),
                              child: const Text('Send a test notification'),
                            ),
                          const Text(
                            'Upcoming system reminders use a bounded queue of up to 48 events. Open the app periodically to refresh long recurring schedules. Device power-saving settings can delay delivery.',
                          ),
                          const Text(
                            'Cloud push is not configured. Historical climate never generates emergency alerts.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FsSpace.lg),
              Text(
                'Your updates',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (items.isEmpty && !state.isLoading)
                const Padding(
                  padding: EdgeInsets.all(FsSpace.lg),
                  child: Text(
                    'No notifications yet. Your saved task reminders will appear here when due.',
                  ),
                ),
              for (final item in items)
                Card(
                  child: ListTile(
                    leading: Icon(
                      item['category'] == 'overdue_task'
                          ? Icons.schedule
                          : Icons.notifications_outlined,
                    ),
                    title: Text(
                      item['title'] as String,
                      style: TextStyle(
                        fontWeight: item['read'] == true
                            ? FontWeight.normal
                            : FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      _notificationSummary(
                        context,
                        item,
                        farmNames[item['farm_id']] ?? 'Saved farm',
                      ),
                    ),
                    onTap: () => _act(() async {
                      await _read(item, true);
                      final farmId = item['farm_id'] as String;
                      if (ref
                              .read(homeProfileProvider)
                              .value
                              ?.farms
                              .any((f) => f.id == farmId) ==
                          true) {
                        await ref
                            .read(homeProfileProvider.notifier)
                            .selectFarm(farmId);
                      }
                      if (!context.mounted) return;
                      context.push(
                        item['task_id'] == null
                            ? '/season'
                            : '/tasks?task=${Uri.encodeComponent(item['task_id'] as String)}',
                      );
                    }),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Notification actions',
                      onSelected: (action) => _act(
                        () => action == 'delete'
                            ? updateLocalFarm(
                                ref,
                                (store) => store.put(
                                  item['farm_id'] as String,
                                  'notification',
                                  {...item, 'dismissed': true},
                                ),
                              )
                            : _read(item, item['read'] != true),
                      ),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'read',
                          child: Text(
                            item['read'] == true ? 'Mark unread' : 'Mark read',
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Dismiss'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _clock(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

String _notificationSummary(
  BuildContext context,
  Map<String, dynamic> item,
  String farmName,
) {
  final category = switch (item['category']) {
    'task_reminder' => 'Task reminder',
    'overdue_task' => 'Pending activity',
    'observation_follow_up' => 'Observation follow-up',
    'assessment_update' => 'Saved assessment update',
    'sync_status' => 'Sync status',
    'weather_update' => 'Verified weather update',
    _ => 'Application information',
  };
  final date = DateTime.tryParse('${item['timestamp']}')?.toLocal();
  final labels = MaterialLocalizations.of(context);
  final timestamp = date == null
      ? 'Date unavailable'
      : '${labels.formatMediumDate(date)} ${date.year} · '
            '${labels.formatTimeOfDay(TimeOfDay.fromDateTime(date))} '
            '(${date.timeZoneName})';
  final readState = item['read'] == true ? 'Read' : 'Unread';
  return '$category · $readState\n$farmName\n${item['body']}\n$timestamp';
}
