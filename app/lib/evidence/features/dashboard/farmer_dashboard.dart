import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/local/farm_task.dart';
import '../../data/models/home_profile.dart';
import '../../design/components/product.dart';
import '../../design/tokens.dart';
import '../../state/home_provider.dart';
import '../../state/journal_provider.dart';
import '../../state/local_farm_provider.dart';
import '../companion/local_records_screen.dart';
import '../map/soil_first_map.dart';
import '../tasks/notifications_screen.dart';
import '../realtime/realtime_panel.dart';

class FarmerDashboard extends ConsumerWidget {
  const FarmerDashboard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileState = ref.watch(homeProfileProvider);
    final profile = profileState.value;
    if (profile == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            semanticsLabel: 'Opening saved farms',
          ),
        ),
      );
    }
    final farm = profile.farm;
    final snapshot = ref.watch(journalProvider).value;
    final records = snapshot?.rows('entries') ?? [];
    final crops =
        records
            .where(
              (row) =>
                  row['kind'] == 'season' &&
                  row['harvest_on'] == null &&
                  row['stage'] != 'harvested',
            )
            .toList()
          ..sort(
            (a, b) => '${b['occurred_on']}'.compareTo('${a['occurred_on']}'),
          );
    final tasks = ref.watch(farmTasksProvider);
    final now = ref.watch(localClockProvider).value ?? DateTime.now();
    final today =
        (tasks.value ?? [])
            .where((task) => task.pending && task.today(now))
            .toList()
          ..sort((a, b) => a.due.compareTo(b.due));
    final upcoming =
        (tasks.value ?? [])
            .where((task) => task.pending && !task.today(now))
            .toList()
          ..sort((a, b) => a.due.compareTo(b.due));
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('EarthSync'),
        actions: [
          const NotificationBell(),
          IconButton(
            tooltip: 'Sources & Evidence',
            onPressed: () => context.push('/sources'),
            icon: const Icon(Icons.menu_book_outlined),
          ),
          IconButton(
            tooltip: 'Account & privacy settings',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.person_outline),
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
                now.hour < 12
                    ? 'Good morning.'
                    : now.hour < 18
                    ? 'Good afternoon.'
                    : 'Good evening.',
                style: t.headlineMedium,
              ),
              const SizedBox(height: FsSpace.xs),
              Text(
                'A clearer view of your farm, one day at a time.',
                style: t.bodyLarge,
              ),
              if (profile.storageNotice != null) Text(profile.storageNotice!),
              const SizedBox(height: FsSpace.lg),
              if (profile.farms.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: farm?.id,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Selected farm'),
                  items: [
                    for (final saved in profile.farms)
                      DropdownMenuItem(
                        value: saved.id,
                        child: Text(saved.name ?? 'My Farm'),
                      ),
                  ],
                  onChanged: (id) async {
                    if (id == null) return;
                    try {
                      await ref
                          .read(homeProfileProvider.notifier)
                          .selectFarm(id);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not switch saved farm.'),
                          ),
                        );
                      }
                    }
                  },
                ),
              const SizedBox(height: FsSpace.md),
              const Text('Saved on this device · Cloud backup not configured.'),
              const SizedBox(height: FsSpace.sm),
              _FarmOverview(
                farmName:
                    farm?.name ??
                    (profile.userLocation is ApproximateArea
                        ? 'Your Area'
                        : 'Explore the world'),
                location:
                    farm?.point.label ??
                    (profile.userLocation is ApproximateArea
                        ? (profile.userLocation as ApproximateArea).point.label
                        : null),
                area: farm?.boundary?.areaSquareMetres,
                crop: crops.isEmpty ? null : crops.first,
                onOpen: () =>
                    context.push(farm == null ? '/location' : '/field'),
              ),
              const SizedBox(height: FsSpace.lg),
              if (farm != null)
                Wrap(
                  spacing: FsSpace.sm,
                  runSpacing: FsSpace.sm,
                  children: [
                    TextButton.icon(
                      onPressed: () => context.push('/location?edit=1'),
                      icon: const Icon(Icons.edit_location_alt_outlined),
                      label: const Text('Edit My Farm'),
                    ),
                    TextButton.icon(
                      onPressed: () => context.push('/question/1'),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Open Farm Questionnaire'),
                    ),
                  ],
                ),
              Wrap(
                spacing: FsSpace.sm,
                runSpacing: FsSpace.sm,
                children: [
                  for (final action in const [
                    ('Check soil', '/field', Icons.layers_outlined),
                    ('Add task', '/tasks', Icons.add_task),
                    ('Add observation', '/local-records', Icons.edit_note),
                    ('Weather', '/weather', Icons.cloud_outlined),
                    ('Plan a rotation', '/rotations', Icons.spa_outlined),
                  ])
                    OutlinedButton.icon(
                      onPressed: () => context.push(
                        farm == null && action.$2 != '/weather'
                            ? '/location'
                            : action.$2,
                      ),
                      icon: Icon(action.$3),
                      label: Text(action.$1),
                    ),
                ],
              ),
              const SizedBox(height: FsSpace.lg),
              if (farm != null)
                LayoutBuilder(
                  builder: (context, box) {
                    final activities = SectionCard(
                      title: 'Today on your farm',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (tasks.isLoading)
                            const LinearProgressIndicator(
                              semanticsLabel: 'Opening tasks',
                            ),
                          if (tasks.hasError)
                            const Text(
                              'Saved activities could not be opened. Visit Tasks to retry.',
                            ),
                          if (!tasks.isLoading && today.isEmpty)
                            const Text(
                              'No activities scheduled today. Make room for what matters to your farm.',
                            ),
                          for (final task in today.take(4))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: IconButton(
                                tooltip: 'Complete ${task.title}',
                                icon: const Icon(Icons.radio_button_unchecked),
                                onPressed: () async {
                                  try {
                                    await updateLocalFarm(
                                      ref,
                                      (store) => store.setTaskStatus(
                                        task,
                                        'completed',
                                        DateTime.now(),
                                      ),
                                    );
                                  } catch (_) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Could not save task completion.',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),
                              title: Text(task.title),
                              subtitle: Text(
                                '${taskCategories[task.data['category']]} · ${task.zone}',
                              ),
                              onTap: () => context.push(
                                '/tasks?task=${Uri.encodeComponent(task.id)}',
                              ),
                            ),
                          if (upcoming.isNotEmpty) ...[
                            const Divider(),
                            Text(
                              'Next: ${upcoming.first.title}',
                              style: t.titleSmall,
                            ),
                            Text(
                              '${upcoming.first.day} · ${upcoming.first.overdue(now) ? 'Overdue' : 'Upcoming'}',
                            ),
                          ],
                          TextButton(
                            onPressed: () => context.push('/tasks'),
                            child: const Text('View all farm tasks'),
                          ),
                        ],
                      ),
                    );
                    final map = SoilFirstMap(
                      key: ValueKey(
                        'dashboard-map:${farm.id}:${farm.confirmedAt}',
                      ),
                      farm: farm,
                      compact: true,
                    );
                    if (box.maxWidth < FsLayout.rail) {
                      return Column(children: [activities, map]);
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: map),
                        const SizedBox(width: FsSpace.md),
                        Expanded(child: activities),
                      ],
                    );
                  },
                )
              else
                SectionCard(
                  title: 'Make it your own',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Save a farm point and boundary, then keep notes, crop history and tasks on this device. Sign-in is optional.',
                      ),
                      FilledButton(
                        onPressed: () => context.push('/location'),
                        child: const Text('Set up a farm'),
                      ),
                      TextButton(
                        onPressed: () => context.push('/explore'),
                        child: const Text('Explore an area first'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: FsSpace.lg),
              SectionCard(
                title: 'Latest environmental evidence',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      snapshot == null ||
                              snapshot.retrieved ==
                                  'No server evidence retrieved'
                          ? 'No farm evidence saved yet. Connect when you want to retrieve real source data.'
                          : 'Latest saved retrieval: ${snapshot.retrieved}${snapshot.cached ? ' · may be stale' : ''}',
                    ),
                    const Text(
                      'Available values retain their original location, date and source. Missing evidence does not mean healthy conditions.',
                    ),
                    RealtimePanel(
                      key: ValueKey('home-evidence:${farm?.id}'),
                      compact: true,
                      fieldOnly: farm != null,
                    ),
                    TextButton(
                      onPressed: () => context.push('/weather'),
                      child: const Text('Open weather & climate history'),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: FsSpace.sm,
                runSpacing: FsSpace.sm,
                children: [
                  TextButton.icon(
                    onPressed: () => context.push('/sources'),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('Sources & Evidence'),
                  ),
                  TextButton(
                    onPressed: () => context.push('/season'),
                    child: const Text('Crop history & saved decisions'),
                  ),
                  TextButton(
                    onPressed: () => context.push('/assistant'),
                    child: const Text('Farmer assistant'),
                  ),
                  TextButton(
                    onPressed: () => context.push('/climate-overview'),
                    child: const Text('Detailed climate workspace'),
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

class _FarmOverview extends ConsumerWidget {
  const _FarmOverview({
    required this.farmName,
    required this.location,
    required this.area,
    required this.crop,
    required this.onOpen,
  });
  final String farmName;
  final String? location;
  final double? area;
  final Map<String, dynamic>? crop;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(localPhotosProvider).value ?? [];
    final farmId = ref.watch(homeProfileProvider).value?.farm?.id;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: FsColors.forest,
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: LandContours())),
          if (photos.isNotEmpty && farmId != null)
            Positioned.fill(
              child: FutureBuilder<Uint8List?>(
                future: (() async => (await ref.read(
                  localFarmStoreProvider.future,
                )).photo(farmId, photos.first['id'] as String))(),
                builder: (_, state) => state.data == null
                    ? const SizedBox.shrink()
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            state.data!,
                            fit: BoxFit.cover,
                            semanticLabel: 'Your privately saved field photo',
                          ),
                          Container(
                            color: FsColors.forest.withValues(alpha: .85),
                          ),
                        ],
                      ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(FsSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FIELD OVERVIEW',
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: FsColors.leaf),
                ),
                const SizedBox(height: FsSpace.sm),
                Text(
                  farmName,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: FsColors.onPrimary,
                  ),
                ),
                const SizedBox(height: FsSpace.sm),
                Text(
                  location ??
                      'Your records, plans and reminders. All in one place.',
                  style: const TextStyle(color: FsColors.onPrimary),
                ),
                if (area != null)
                  Text(
                    '${(area! / 10000).toStringAsFixed(2)} ha · approximate saved boundary',
                    style: const TextStyle(color: FsColors.leaf),
                  ),
                const SizedBox(height: FsSpace.lg),
                Text(
                  crop == null
                      ? 'Current crop not reported'
                      : '${crop!['crop_name']} · farmer-reported',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: FsColors.onPrimary),
                ),
                Text(
                  crop == null
                      ? 'Add crop history when you are ready.'
                      : 'Reported stage: ${crop!['stage'] ?? 'unknown'}',
                  style: const TextStyle(color: FsColors.leaf),
                ),
                const SizedBox(height: FsSpace.md),
                FilledButton(
                  onPressed: onOpen,
                  style: FilledButton.styleFrom(
                    backgroundColor: FsColors.leaf,
                    foregroundColor: FsColors.forest,
                  ),
                  child: Text(farmId == null ? 'Add My Farm' : 'View my farm'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
