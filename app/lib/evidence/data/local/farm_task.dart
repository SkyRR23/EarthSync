import 'package:timezone/data/latest_all.dart' as zones;
import 'package:timezone/timezone.dart' as tz;

bool _zonesReady = false;
void initializeFarmTimeZones() {
  if (_zonesReady) return;
  zones.initializeTimeZones();
  _zonesReady = true;
}

const taskCategories = {
  'watering': 'Watering / irrigation',
  'soil_moisture': 'Check soil moisture',
  'crop_inspection': 'Inspect crops',
  'pests': 'Inspect pests',
  'drainage': 'Check drainage',
  'fertilizer': 'Farmer-planned fertilizer',
  'planting_preparation': 'Prepare for planting',
  'planting': 'Planting',
  'weeding': 'Weeding',
  'maintenance': 'Field maintenance',
  'harvest_preparation': 'Prepare for harvest',
  'harvesting': 'Harvesting',
  'custom': 'Custom activity',
};

String calendarDay(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

class FarmTask {
  FarmTask(Map<String, dynamic> value) : data = Map.unmodifiable(value) {
    initializeFarmTimeZones();
    for (final key in [
      'id',
      'farm_id',
      'owner',
      'title',
      'due_date',
      'timezone',
      'created_at',
      'updated_at',
    ]) {
      if (data[key] is! String || (data[key] as String).isEmpty) {
        throw FormatException('Task requires $key.');
      }
    }
    if (title.length > 150 ||
        !taskCategories.containsKey(data['category']) ||
        !['pending', 'completed', 'canceled', 'skipped'].contains(status) ||
        !['none', 'daily', 'weekly', 'monthly'].contains(recurrence) ||
        interval < 1 ||
        interval > 52 ||
        !['normal', 'high', 'low'].contains(data['priority']) ||
        (minute != null && (minute! < 0 || minute! >= 1440)) ||
        reminderMinutes < 0 ||
        reminderMinutes > 10080) {
      throw const FormatException('Invalid task schedule.');
    }
    if (calendarDay(DateTime.parse(day)) != day) {
      throw const FormatException('Invalid due date.');
    }
    tz.getLocation(zone);
    if (status == 'completed' && data['completed_at'] == null) {
      throw const FormatException('Completed tasks require a completion time.');
    }
  }
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get farmId => data['farm_id'] as String;
  String get title => data['title'] as String;
  String get day => data['due_date'] as String;
  String get zone => data['timezone'] as String;
  String get status => data['status'] as String;
  String get recurrence => data['recurrence'] as String? ?? 'none';
  int get interval => data['interval'] as int? ?? 1;
  int? get minute => data['minute_of_day'] as int?;
  int get reminderMinutes => data['reminder_minutes'] as int? ?? 0;
  bool get reminder => data['reminder'] == true;
  bool get pending => status == 'pending';
  tz.TZDateTime get due {
    final date = DateTime.parse(day);
    return tz.TZDateTime(
      tz.getLocation(zone),
      date.year,
      date.month,
      date.day + (minute == null ? 1 : 0),
      (minute ?? 0) ~/ 60,
      (minute ?? 0) % 60,
    );
  }

  bool overdue(DateTime now) =>
      pending && (minute == null ? !due.isAfter(now) : due.isBefore(now));
  bool today(DateTime now) =>
      day == calendarDay(tz.TZDateTime.from(now, tz.getLocation(zone)));
  FarmTask withChanges(Map<String, dynamic> changes) =>
      FarmTask({...data, ...changes});

  FarmTask? next(DateTime now, {int steps = 1}) {
    if (recurrence == 'none') return null;
    if (steps < 1) throw ArgumentError.value(steps, 'steps');
    final date = DateTime.parse(day);
    late DateTime next;
    if (recurrence == 'monthly') {
      final target = DateTime(date.year, date.month + interval * steps);
      final anchor = DateTime.parse(data['series_start'] as String? ?? day).day;
      final last = DateTime(target.year, target.month + 1, 0).day;
      next = DateTime(target.year, target.month, anchor > last ? last : anchor);
    } else {
      next = DateTime(
        date.year,
        date.month,
        date.day + interval * steps * (recurrence == 'weekly' ? 7 : 1),
      );
    }
    final nextDay = calendarDay(next);
    final series = data['series_id'] as String? ?? id;
    return withChanges({
      'id': '$series:$nextDay',
      'series_id': series,
      'series_start': data['series_start'] ?? day,
      'due_date': nextDay,
      'status': 'pending',
      'completed_at': null,
      'created_at': now.toUtc().toIso8601String(),
      'updated_at': now.toUtc().toIso8601String(),
    });
  }
}

class ReminderPreferences {
  const ReminderPreferences({
    this.enabled = false,
    this.quietStart = 22 * 60,
    this.quietEnd = 7 * 60,
    this.zone = 'UTC',
    this.overdue = true,
    this.systemAllowed = false,
  });
  final bool enabled, overdue, systemAllowed;
  final int quietStart, quietEnd;
  final String zone;
  factory ReminderPreferences.fromJson(Map<String, dynamic> data) =>
      ReminderPreferences(
        enabled: data['enabled'] == true,
        overdue: data['overdue'] != false,
        systemAllowed: data['system_allowed'] == true,
        quietStart: data['quiet_start'] as int? ?? 1320,
        quietEnd: data['quiet_end'] as int? ?? 420,
        zone: data['timezone'] as String? ?? 'UTC',
      );
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'overdue': overdue,
    'quiet_start': quietStart,
    'quiet_end': quietEnd,
    'timezone': zone,
    'system_allowed': systemAllowed,
  };
  tz.TZDateTime afterQuietHours(DateTime instant) {
    initializeFarmTimeZones();
    final local = tz.TZDateTime.from(instant, tz.getLocation(zone));
    if (quietStart == quietEnd) return local;
    final m = local.hour * 60 + local.minute;
    final overnight = quietStart > quietEnd;
    final quiet = overnight
        ? m >= quietStart || m < quietEnd
        : m >= quietStart && m < quietEnd;
    if (!quiet) return local;
    return tz.TZDateTime(
      local.location,
      local.year,
      local.month,
      local.day + (overnight && m >= quietStart ? 1 : 0),
      quietEnd ~/ 60,
      quietEnd % 60,
    );
  }
}
