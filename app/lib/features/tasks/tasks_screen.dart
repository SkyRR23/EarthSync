import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../data/farm_journal.dart' show journalId;
import '../../data/local/farm_task.dart';
import '../../design/tokens.dart';
import '../../state/home_provider.dart';
import '../../state/local_farm_provider.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key, this.taskId});
  final String? taskId;
  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  String _view = 'Today';
  DateTime _selected = DateTime.now();
  String? _error;
  bool _busy = false;
  Future<void> _act(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not save this change: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([FarmTask? task, String? template]) async {
    final farm = ref.read(homeProfileProvider).value?.farm;
    if (farm == null) return;
    final result = await showModalBottomSheet<FarmTask>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          TaskEditor(farmId: farm.id, task: task, template: template),
    );
    if (result != null && mounted) {
      await _act(() => updateLocalFarm(ref, (store) => store.saveTask(result)));
    }
  }

  Future<void> _status(FarmTask task, String status) => _act(
    () => updateLocalFarm(
      ref,
      (store) => store.setTaskStatus(task, status, DateTime.now()),
    ),
  );
  void _details(FarmTask task) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => SingleChildScrollView(
        padding: const EdgeInsets.all(FsSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(task.title, style: Theme.of(context).textTheme.headlineSmall),
            Text(taskCategories[task.data['category']] ?? 'Activity'),
            Text('${task.day} ${_time(task.minute)} · ${task.zone}'),
            Text('Status: ${task.status} · Priority: ${task.data['priority']}'),
            if ((task.data['description'] as String? ?? '').isNotEmpty)
              Text(task.data['description'] as String),
            Text(
              'Origin: ${task.data['origin']} · Schedule chosen by the farmer.',
            ),
            if (task.data['observation_id'] != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  context.push('/local-records');
                },
                child: const Text('View linked field observation'),
              ),
            Text(
              'Repeat: ${task.recurrence}${task.recurrence == 'none' ? '' : ' (every ${task.interval})'}',
            ),
            if (task.data['completed_at'] != null)
              Text('Completed: ${task.data['completed_at']}'),
            Wrap(
              spacing: FsSpace.sm,
              runSpacing: FsSpace.sm,
              children: [
                FilledButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _status(task, task.pending ? 'completed' : 'pending');
                  },
                  child: Text(task.pending ? 'Mark completed' : 'Reopen task'),
                ),
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _edit(task);
                  },
                  child: const Text('Edit task'),
                ),
                if (task.pending)
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _postpone(task);
                    },
                    child: const Text('Postpone one day'),
                  ),
                if (task.pending)
                  TextButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _status(task, 'skipped');
                    },
                    child: const Text('Skip this activity'),
                  ),
                if (task.pending)
                  TextButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _status(task, 'canceled');
                    },
                    child: const Text('Cancel task'),
                  ),
                TextButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: sheetContext,
                      builder: (dialog) => AlertDialog(
                        title: const Text('Delete this task?'),
                        content: const Text(
                          'Its scheduled reminders will be canceled.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialog, false),
                            child: const Text('Keep task'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dialog, true),
                            child: const Text('Delete task'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && sheetContext.mounted) {
                      Navigator.pop(sheetContext);
                      await _act(
                        () => updateLocalFarm(
                          ref,
                          (store) => store.deleteTask(task),
                        ),
                      );
                    }
                  },
                  child: const Text('Delete task'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _postpone(FarmTask task) async {
    final day = DateTime.parse(task.day);
    await _act(
      () => updateLocalFarm(
        ref,
        (store) => store.saveTask(
          task.withChanges({
            'due_date': calendarDay(DateTime(day.year, day.month, day.day + 1)),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(farmTasksProvider);
    final now = ref.watch(localClockProvider).value ?? DateTime.now();
    final all = state.value ?? [];
    final rows =
        all
            .where(
              (task) => switch (_view) {
                'Today' => task.pending && task.today(now),
                'Upcoming' =>
                  task.pending && !task.today(now) && !task.overdue(now),
                'Overdue' => task.overdue(now),
                'Completed' => !task.pending,
                _ => task.day == calendarDay(_selected),
              },
            )
            .toList()
          ..sort((a, b) => a.due.compareTo(b.due));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Farm tasks'),
        actions: [
          IconButton(
            tooltip: 'Reminder preferences',
            onPressed: () => context.push('/notifications'),
            icon: const Icon(Icons.notifications_outlined),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: FsLayout.content),
          child: ListView(
            padding: const EdgeInsets.all(FsSpace.lg),
            children: [
              Text(
                'A little planning. A clearer day.',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: FsSpace.sm),
              const Text(
                'Your activities, at your pace. Saved on this device and available offline.',
              ),
              const SizedBox(height: FsSpace.md),
              FilledButton.icon(
                onPressed: _busy ? null : () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('Add a farm task'),
              ),
              const SizedBox(height: FsSpace.md),
              Wrap(
                spacing: FsSpace.sm,
                children: [
                  for (final view in [
                    'Today',
                    'Upcoming',
                    'Overdue',
                    'Completed',
                    'Calendar',
                  ])
                    ChoiceChip(
                      label: Text(view),
                      selected: view == _view,
                      onSelected: (_) => setState(() => _view = view),
                    ),
                ],
              ),
              if (_view == 'Calendar')
                CalendarDatePicker(
                  initialDate: _selected,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  onDateChanged: (value) => setState(() => _selected = value),
                ),
              if (state.isLoading || _busy)
                const LinearProgressIndicator(
                  semanticsLabel: 'Loading saved tasks',
                ),
              if (state.hasError || _error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: FsSpace.md),
                  child: Text(
                    _error ??
                        'Saved tasks could not be opened. Your database has not been replaced. ${state.error}',
                  ),
                ),
              if (widget.taskId != null &&
                  all.any((task) => task.id == widget.taskId))
                OutlinedButton(
                  onPressed: () => _details(
                    all.firstWhere((task) => task.id == widget.taskId),
                  ),
                  child: const Text('Open reminder task'),
                ),
              if (widget.taskId != null &&
                  !state.isLoading &&
                  !all.any((task) => task.id == widget.taskId))
                const Text(
                  'The task linked to this reminder is no longer available in the selected farm.',
                ),
              const SizedBox(height: FsSpace.md),
              if (rows.isEmpty && !state.isLoading && !state.hasError)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(FsSpace.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.checklist_outlined, size: 32),
                        const SizedBox(height: FsSpace.md),
                        Text(
                          _view == 'Today'
                              ? 'Your day is open'
                              : 'No tasks in this view',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Text(
                          'Add an activity or start with an editable template below.',
                        ),
                      ],
                    ),
                  ),
                ),
              for (final task in rows)
                Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(FsSpace.sm),
                    leading: IconButton(
                      tooltip: task.pending
                          ? 'Complete ${task.title}'
                          : 'Reopen ${task.title}',
                      onPressed: _busy
                          ? null
                          : () => _status(
                              task,
                              task.pending ? 'completed' : 'pending',
                            ),
                      icon: Icon(
                        task.status == 'completed'
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                      ),
                    ),
                    title: Text(task.title),
                    subtitle: Text(
                      '${task.day} ${_time(task.minute)} · ${task.zone}\n${task.overdue(now) ? 'Overdue' : task.status} · ${taskCategories[task.data['category']]}',
                    ),
                    isThreeLine: true,
                    onTap: () => _details(task),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
              const SizedBox(height: FsSpace.lg),
              Text(
                'Start with a familiar activity',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'Editable templates. Choose the date and frequency that suit your farm.',
              ),
              Wrap(
                spacing: FsSpace.sm,
                runSpacing: FsSpace.sm,
                children: [
                  for (final category in [
                    'soil_moisture',
                    'crop_inspection',
                    'drainage',
                    'planting_preparation',
                    'harvest_preparation',
                  ])
                    ActionChip(
                      label: Text(taskCategories[category]!),
                      onPressed: _busy ? null : () => _edit(null, category),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _time(int? minute) => minute == null
    ? 'Any time'
    : '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

class TaskEditor extends StatefulWidget {
  const TaskEditor({
    super.key,
    required this.farmId,
    this.task,
    this.template,
    this.observationId,
  });
  final String farmId;
  final FarmTask? task;
  final String? template;
  final String? observationId;
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title, _description, _zone;
  late String _category, _day, _priority, _repeat;
  int? _minute;
  int _interval = 1, _lead = 0;
  bool _reminder = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    initializeFarmTimeZones();
    final task = widget.task;
    _category =
        task?.data['category'] as String? ?? widget.template ?? 'custom';
    _title = TextEditingController(
      text:
          task?.title ??
          (widget.template == null ? '' : taskCategories[_category]),
    );
    _description = TextEditingController(
      text: task?.data['description'] as String? ?? '',
    );
    _zone = TextEditingController(text: task?.zone ?? 'UTC');
    _day = task?.day ?? calendarDay(DateTime.now());
    _priority = task?.data['priority'] as String? ?? 'normal';
    _repeat = task?.recurrence ?? 'none';
    _interval = task?.interval ?? 1;
    _minute = task?.minute;
    _reminder = task?.reminder ?? false;
    _lead = task?.reminderMinutes ?? 0;
    if (task == null) _detectZone();
  }

  Future<void> _detectZone() async {
    try {
      final zone = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.getLocation(zone);
      if (mounted && _zone.text == 'UTC') setState(() => _zone.text = zone);
    } catch (_) {
      /* UTC stays visible and editable when device lookup is unavailable. */
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _zone.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    if (_reminder && _minute == null) {
      setState(
        () => _error = 'Choose a reminder time, or turn the reminder off.',
      );
      return;
    }
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final task = FarmTask({
        ...?widget.task?.data,
        'id': widget.task?.id ?? journalId(),
        'farm_id': widget.farmId,
        'owner': widget.task?.data['owner'] ?? 'device-local',
        'category': _category,
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'observation_id':
            widget.task?.data['observation_id'] ?? widget.observationId,
        'due_date': _day,
        'minute_of_day': _minute,
        'timezone': _zone.text.trim(),
        'priority': _priority,
        'status': widget.task?.status ?? 'pending',
        'completed_at': widget.task?.data['completed_at'],
        'recurrence': _repeat,
        'interval': _interval,
        'reminder': _reminder,
        'reminder_minutes': _lead,
        'origin':
            widget.task?.data['origin'] ??
            (widget.template == null ? 'manual' : 'template'),
        'created_at': widget.task?.data['created_at'] ?? now,
        'updated_at': now,
      });
      Navigator.pop(context, task);
    } catch (error) {
      setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(FsSpace.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.task == null
                      ? 'Plan a farm activity'
                      : 'Edit farm activity',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: FsSpace.md),
                TextFormField(
                  controller: _title,
                  maxLength: 150,
                  decoration: const InputDecoration(
                    labelText: 'Activity title',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Name this activity'
                      : null,
                ),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Activity type'),
                  items: [
                    for (final entry in taskCategories.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (v) => setState(() => _category = v!),
                ),
                const SizedBox(height: FsSpace.md),
                TextFormField(
                  controller: _description,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Due date'),
                  subtitle: Text(_day),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: DateTime.parse(_day),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (date != null && mounted) {
                      setState(() => _day = calendarDay(date));
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Scheduled time (optional)'),
                  subtitle: Text(_time(_minute)),
                  trailing: _minute == null
                      ? const Icon(Icons.schedule)
                      : IconButton(
                          tooltip: 'Clear scheduled time',
                          onPressed: () => setState(() {
                            _minute = null;
                            _reminder = false;
                          }),
                          icon: const Icon(Icons.clear),
                        ),
                  onTap: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(
                        hour: (_minute ?? 540) ~/ 60,
                        minute: (_minute ?? 540) % 60,
                      ),
                    );
                    if (time != null && mounted) {
                      setState(() => _minute = time.hour * 60 + time.minute);
                    }
                  },
                ),
                TextFormField(
                  controller: _zone,
                  decoration: const InputDecoration(
                    labelText: 'Time zone',
                    helperText:
                        'IANA name, for example Asia/Yangon or America/Chicago',
                  ),
                  validator: (value) {
                    try {
                      tz.getLocation(value!.trim());
                      return null;
                    } catch (_) {
                      return 'Enter a recognized time zone';
                    }
                  },
                ),
                const SizedBox(height: FsSpace.md),
                DropdownButtonFormField<String>(
                  initialValue: _priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: [
                    for (final v in ['low', 'normal', 'high'])
                      DropdownMenuItem(value: v, child: Text(v)),
                  ],
                  onChanged: (v) => _priority = v!,
                ),
                ExpansionTile(
                  title: const Text('Repeat and reminder'),
                  initiallyExpanded: _reminder || _repeat != 'none',
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _repeat,
                      decoration: const InputDecoration(labelText: 'Repeat'),
                      items: [
                        for (final v in ['none', 'daily', 'weekly', 'monthly'])
                          DropdownMenuItem(value: v, child: Text(v)),
                      ],
                      onChanged: (v) => setState(() => _repeat = v!),
                    ),
                    if (_repeat != 'none')
                      DropdownButtonFormField<int>(
                        initialValue: _interval,
                        decoration: const InputDecoration(
                          labelText: 'Repeat every',
                        ),
                        items: [
                          for (var n = 1; n <= 52; n++)
                            DropdownMenuItem(
                              value: n,
                              child: Text(
                                '$n ${_repeat == 'daily'
                                    ? 'day(s)'
                                    : _repeat == 'weekly'
                                    ? 'week(s)'
                                    : 'month(s)'}',
                              ),
                            ),
                        ],
                        onChanged: (v) => _interval = v!,
                      ),
                    SwitchListTile(
                      title: const Text('Remind me'),
                      subtitle: const Text(
                        'Enable reminders in notification preferences. No internet required on supported phones.',
                      ),
                      value: _reminder,
                      onChanged: (v) => setState(() => _reminder = v),
                    ),
                    if (_reminder)
                      DropdownButtonFormField<int>(
                        initialValue: _lead,
                        decoration: const InputDecoration(
                          labelText: 'Reminder lead time',
                        ),
                        items: [
                          for (final n in [0, 15, 30, 60, 1440])
                            DropdownMenuItem(
                              value: n,
                              child: Text(
                                n == 0
                                    ? 'At the scheduled time'
                                    : n == 1440
                                    ? 'One day before'
                                    : '$n minutes before',
                              ),
                            ),
                        ],
                        onChanged: (v) => _lead = v!,
                      ),
                  ],
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const Text(
                  'A farmer-chosen schedule. This does not prescribe irrigation amounts or crop treatments.',
                ),
                const SizedBox(height: FsSpace.md),
                FilledButton(
                  onPressed: _save,
                  child: const Text('Save activity on this device'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
