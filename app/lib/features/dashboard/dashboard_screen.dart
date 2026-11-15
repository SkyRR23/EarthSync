import '../../app/ui_labels.dart';
import '../../state/integration_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/ui_copy.dart';
import '../../data/environment/area_climate.dart';
import '../../data/models/home_profile.dart';
import '../../design/components/product.dart';
import '../../state/home_provider.dart';
import '../../state/providers.dart';
import '../onboarding/location_choices.dart';
import '../questionnaire/historical_window_selector.dart';
import 'climate_panel.dart';
import 'satellite_preview.dart';
import '../realtime/realtime_panel.dart';

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
    String tr(String k) => UiCopy.text(context, k);
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
            tooltip: tr('sources'),
            onPressed: () => context.push('/sources'),
            icon: const Icon(Icons.menu_book_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: ListView(
              key: const PageStorageKey('home-dashboard'),
              padding: const EdgeInsets.all(24),
              children: [
                TextButton.icon(
                  onPressed: () => context.push('/historical'),
                  icon: const Icon(Icons.history),
                  label: const Text('Historical Simulation Lab'),
                ),
                if (profile.storageNotice != null) Text(profile.storageNotice!),
                PageHeader(
                  eyebrow: UiLabels.nasaSpaceAppsFieldShift,
                  title: tr('overview'),
                  subtitle: tr('overviewBody'),
                ),
                if (farm != null) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('My Farm'),
                          icon: Icon(Icons.grass),
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
                  ),
                  const SizedBox(height: 20),
                ],
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: const Color(0xFF173D30),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: CustomPaint(
                    painter: LandContours(),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            showingFarm ? Icons.grass_outlined : Icons.public,
                            color: const Color(0xFFC8DFBF),
                            size: 30,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            showingFarm
                                ? farm.name ?? 'My Farm'
                                : point == null
                                ? UiLabels.exploreTheWorld
                                : 'Your Area',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            showingFarm
                                ? 'Farmer-confirmed point · ${farm.point.label}'
                                : area is ApproximateArea
                                ? '${area.source == AreaSource.example ? 'Example region · ' : ''}${area.label} · ${area.point.label}'
                                : tr('discoverBody'),
                            style: const TextStyle(color: Color(0xFFDFEBDD)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            showingFarm
                                ? UiLabels.thisPointStaysFixedWhenYouChangeYour
                                : UiLabels
                                      .regionalContextOnlyNoPersonalizedCropRecommendations,
                            style: const TextStyle(color: Color(0xFFDFEBDD)),
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFDBEBCF),
                                  foregroundColor: const Color(0xFF173D30),
                                ),
                                onPressed: () => context.push(
                                  showingFarm ? '/field' : '/area',
                                ),
                                icon: Icon(
                                  showingFarm
                                      ? Icons.arrow_forward
                                      : Icons.public,
                                ),
                                label: Text(
                                  showingFarm
                                      ? UiLabels.fieldSituation
                                      : tr('areaAction'),
                                ),
                              ),
                              if (farm == null)
                                FilledButton.tonalIcon(
                                  onPressed: () => context.push('/location'),
                                  icon: const Icon(
                                    Icons.add_location_alt_outlined,
                                  ),
                                  label: const Text(UiLabels.addMyFarm),
                                ),
                              if (showingFarm)
                                TextButton(
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () => context.push('/location'),
                                  child: const Text(UiLabels.editMyFarm),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (showingFarm) ...[
                  if (ref.watch(assessmentProvider).result case final result?)
                    EvidenceNotice(
                      title: 'Latest assessment',
                      message: result.validation != null
                          ? 'Input validation failed · open Crop assessment for details'
                          : result.synthetic
                          ? 'Synthetic software assessment · not your farm'
                          : 'Reference crop assessment · more information needed',
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
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
                    label: const Text(UiLabels.openFarmQuestionnaire),
                  ),
                ],
                Text(
                  'What would you like to do?',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Start with the weather, find your field, or ask for help. Your farm records stay in your local workspace.',
                ),
                const SizedBox(height: 16),
                const DemoNavigation(),
                const SizedBox(height: 16),
                RealtimePanel(
                  key: ValueKey('realtime:$showingFarm:${farm?.id}'),
                  compact: true,
                  fieldOnly: showingFarm,
                ),
                ResponsivePair(
                  first: ActionCard(
                    title: tr('planning'),
                    body: tr('planningBody'),
                    icon: Icons.spa_outlined,
                    onTap: () => context.push(
                      farm == null ? '/location' : '/assessment',
                    ),
                  ),
                  second: ActionCard(
                    title: tr('ask'),
                    body: tr('askBody'),
                    icon: Icons.chat_bubble_outline,
                    onTap: () =>
                        context.push('/assistant${_areaView ? '?area=1' : ''}'),
                  ),
                ),
                if (point == null) ...[
                  SectionCard(
                    title: tr('discover'),
                    icon: Icons.travel_explore,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (area is UnknownLocation &&
                            area.reason == LocationUnavailableReason.denied)
                          const Text(
                            UiLabels.locationPermissionWasDeniedChooseAnAreaOr,
                          ),
                        if (area is UnknownLocation &&
                            area.reason ==
                                LocationUnavailableReason.unavailable)
                          const Text(
                            UiLabels
                                .deviceLocationIsUnavailableBrowsersUsuallyNeedHTTPS,
                          ),
                        const LocationChoices(showSkip: false),
                        const SizedBox(height: 12),
                        const Text(
                          UiLabels
                              .tryClearlyLabeledExampleRegionsYangonNairobiOr,
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  ExpansionTile(
                    key: const PageStorageKey('dashboard.reference-context'),
                    title: const Text('Climate history & reference images'),
                    subtitle: const Text(
                      'Older climate records and background imagery',
                    ),
                    children: [
                      ExpansionTile(
                        key: const PageStorageKey('dashboard.historical-dates'),
                        tilePadding: EdgeInsets.zero,
                        title: const Text(UiLabels.changeHistoricalDates),
                        children: const [HistoricalWindowSelector()],
                      ),
                      const SizedBox(height: 12),
                      ClimatePanel(
                        query: ClimateQuery(
                          point,
                          ref.watch(historicalWindowProvider),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ResponsivePair(
                        first: SatellitePreview(point: point),
                        second: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ActionCard(
                              title: tr('satellite'),
                              body: tr('satelliteBody'),
                              icon: Icons.layers_outlined,
                              onTap: () => context.push('/explore'),
                            ),
                            EvidenceNotice(
                              title: tr('forecast'),
                              message: tr('forecastBody'),
                              icon: Icons.cloud_outlined,
                              action: TextButton(
                                onPressed: () => context.push('/realtime'),
                                child: Text(
                                  realtimeCopy(
                                    context,
                                    'Open monitoring dashboard',
                                  ),
                                ),
                              ),
                            ),
                            if (showingFarm)
                              OutlinedButton.icon(
                                onPressed: () => context.push('/photos'),
                                icon: const Icon(Icons.photo_library_outlined),
                                label: const Text(UiLabels.fieldPhotos),
                              ),
                          ],
                        ),
                      ),
                      if (!showingFarm)
                        TextButton(
                          onPressed: () => context.push('/area'),
                          child: const Text(UiLabels.switchArea),
                        ),
                    ],
                  ),
                ],
                const SourceNote(),
                TextButton(
                  onPressed: () => context.push('/sources'),
                  child: Text(tr('sources')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DemoNavigation extends StatelessWidget {
  const DemoNavigation({super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth >= 800
              ? (constraints.maxWidth - 24) / 3
              : constraints.maxWidth;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final item in const [
                (
                  '1. Check the weather',
                  'Latest observations, forecasts and official alerts.',
                  '/realtime',
                  Icons.cloud_outlined,
                ),
                (
                  '2. Find my field',
                  'Place a pin and optionally draw your field outline.',
                  '/location',
                  Icons.map_outlined,
                ),
                (
                  '3. Ask EarthSync',
                  'Get a plain-language explanation of your data.',
                  '/assistant',
                  Icons.chat_bubble_outline,
                ),
              ])
                SizedBox(
                  width: width,
                  child: Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => context.push(item.$3),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(item.$4),
                            const SizedBox(height: 12),
                            Text(
                              item.$1,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(item.$2),
                            const SizedBox(height: 8),
                            const Icon(Icons.arrow_forward, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      ExpansionTile(
        key: const PageStorageKey('dashboard.more-tools'),
        tilePadding: EdgeInsets.zero,
        title: const Text('Explore more tools'),
        subtitle: const Text(
          'Satellite map, crop search, photos, soil tests and saved records',
        ),
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final item in const [
                ('Real-time monitoring', '/realtime', Icons.update),
                ('Satellite NDVI map', '/ndvi', Icons.layers_outlined),
                ('Crop intelligence', '/crop-intelligence', Icons.spa_outlined),
                (
                  'Soil & laboratory reports',
                  '/lab-reports',
                  Icons.science_outlined,
                ),
                (
                  'Image analysis',
                  '/image-analysis',
                  Icons.photo_camera_outlined,
                ),
                ('Farm explorer', '/location', Icons.map_outlined),
                ('Rotation comparison', '/rotations', Icons.compare_arrows),
                ('Farmer history', '/season', Icons.history),
              ])
                OutlinedButton.icon(
                  onPressed: () => context.push(item.$2),
                  icon: Icon(item.$3),
                  label: Text(item.$1),
                ),
            ],
          ),
        ],
      ),
    ],
  );
}
