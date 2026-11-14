import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/environment/area_climate.dart';
import '../../data/models/home_profile.dart';
import '../../state/home_provider.dart';
import '../../state/providers.dart';
import '../onboarding/location_choices.dart';
import '../questionnaire/historical_window_selector.dart';
import 'climate_panel.dart';
import 'satellite_preview.dart';
import '../field/evidence_panels.dart';
import '../../state/integration_provider.dart';
import '../../data/engine/v03_engine.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _areaView = false;
  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(homeProfileProvider).value;
    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final farm = profile.farm;
    final area = profile.userLocation;
    final showingFarm = farm != null && !_areaView;
    final point = showingFarm
        ? farm.point
        : area is ApproximateArea
        ? area.point
        : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('EarthSync'),
        actions: [
          IconButton(
            tooltip: 'Sources and limits',
            onPressed: () => context.push('/sources'),
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: ListView(
              key: const PageStorageKey('home-dashboard'),
              padding: const EdgeInsets.all(20),
              children: [
                if (profile.storageNotice != null) Text(profile.storageNotice!),
                OutlinedButton.icon(
                  onPressed: () =>
                      context.push('/assistant${_areaView ? '?area=1' : ''}'),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('Ask the EarthSync assistant'),
                ),
                if (farm != null) ...[
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('My Farm'),
                        icon: Icon(Icons.agriculture),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Your Area'),
                        icon: Icon(Icons.public),
                      ),
                    ],
                    selected: {_areaView},
                    onSelectionChanged: (v) =>
                        setState(() => _areaView = v.single),
                  ),
                  const SizedBox(height: 20),
                ],
                Text(
                  showingFarm
                      ? farm.name ?? 'My Farm'
                      : point == null
                      ? 'Explore the world'
                      : 'Your Area',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                if (showingFarm) ...[
                  Text('Farmer-confirmed point · ${farm.point.label}'),
                  Text(
                    'Confirmed: ${farm.confirmedAt.toUtc().toIso8601String()}',
                  ),
                  const Text(
                    'This point stays fixed when you change your area. It is not a field boundary.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: () => context.push('/field'),
                        child: const Text('Field situation'),
                      ),
                      OutlinedButton(
                        onPressed: () => context.push('/photos'),
                        child: const Text('Field photos'),
                      ),
                      OutlinedButton(
                        onPressed: () => context.push('/assessment'),
                        child: const Text('Crop assessment'),
                      ),
                    ],
                  ),
                  if (ref.watch(assessmentProvider).result
                      case final result?) ...[
                    Text(
                      result.synthetic
                          ? 'Synthetic software assessment · not your farm'
                          : 'Reference crop assessment · more information needed',
                    ),
                    for (final summary in result.summaries.take(2))
                      Text(V03Status.decode(summary['status']).label),
                  ],
                  FilledButton.icon(
                    onPressed: () {
                      ref
                          .read(farmerDraftProvider.notifier)
                          .setLocation(
                            farm.point.latitude,
                            farm.point.longitude,
                          );
                      context.push('/question/1');
                    },
                    icon: const Icon(Icons.checklist),
                    label: const Text('Open Farm Questionnaire'),
                  ),
                  TextButton(
                    onPressed: () => context.push('/location'),
                    child: const Text('Edit My Farm'),
                  ),
                ] else ...[
                  if (area is ApproximateArea) ...[
                    Text(
                      '${area.source == AreaSource.example ? "Example region · " : ""}${area.label} · ${area.point.label}',
                    ),
                    const Text(
                      'Area context only. This point has not been confirmed as your field. No personalized crop recommendations.',
                    ),
                  ] else
                    const Text(
                      'Choose an area to explore climate records and satellite images. Location permission and a farm are optional.',
                    ),
                  const SizedBox(height: 12),
                  if (farm == null)
                    FilledButton.icon(
                      onPressed: () => context.push('/location'),
                      icon: const Icon(Icons.add_location_alt_outlined),
                      label: const Text('Add My Farm'),
                    ),
                  if (area is UnknownLocation &&
                      area.reason == LocationUnavailableReason.denied)
                    const Text(
                      'Location permission was denied. Choose an area or explore without GPS.',
                    ),
                  if (area is UnknownLocation &&
                      area.reason == LocationUnavailableReason.unavailable)
                    const Text(
                      'Device location is unavailable. Browsers usually need HTTPS or localhost. You can choose an area manually.',
                    ),
                  LocationChoices(
                    showSkip: false,
                    areaLabel: point == null ? 'Choose an Area' : 'Switch Area',
                  ),
                  if (point == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Try clearly labeled example regions: Yangon, Nairobi or São Paulo in Choose an Area. No data are loaded until you select an area.',
                      ),
                    ),
                ],
                if (point != null) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'For these views, selected coordinates go to our climate service and NASA POWER; imagery requests go to NASA GIBS. Choices and farm records stay on this device.',
                  ),
                  const SizedBox(height: 16),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Change historical dates'),
                    children: const [HistoricalWindowSelector()],
                  ),
                  const SizedBox(height: 12),
                  ClimatePanel(
                    query: ClimateQuery(
                      point,
                      ref.watch(historicalWindowProvider),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SatellitePreview(point: point),
                  if (!showingFarm)
                    EnvironmentalPanel(target: environmentalKey(point)),
                ],
                const SizedBox(height: 20),
                const Text(
                  'Missing data do not mean safe conditions. Climate and imagery are decision support, not crop suitability advice.',
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
