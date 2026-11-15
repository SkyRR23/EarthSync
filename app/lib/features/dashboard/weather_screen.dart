import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/environment/area_climate.dart';
import '../../data/models/home_profile.dart';
import '../../design/components/product.dart';
import '../../design/tokens.dart';
import '../../state/home_provider.dart';
import '../../state/providers.dart';
import '../realtime/realtime_panel.dart';
import '../questionnaire/historical_window_selector.dart';
import 'climate_panel.dart';

class WeatherScreen extends ConsumerWidget {
  const WeatherScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(homeProfileProvider).value;
    final area = profile?.userLocation;
    final point =
        profile?.farm?.point ?? (area is ApproximateArea ? area.point : null);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Weather & climate'),
        actions: [
          IconButton(
            tooltip: 'Weather sources',
            onPressed: () => context.push('/sources'),
            icon: const Icon(Icons.info_outline),
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
                'Weather with a clear source.',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Text(
                profile?.farm?.name ?? 'Select your field or explore an area',
              ),
              const SizedBox(height: FsSpace.lg),
              const SectionCard(
                title: 'Observations, forecasts & official alerts',
                child: Text(
                  'Current observations, model forecasts and official warnings remain separate. Each source shows its place, issue/valid time and freshness. Availability depends on geographic coverage and connection.',
                ),
              ),
              RealtimePanel(fieldOnly: profile?.farm != null),
              const SizedBox(height: FsSpace.lg),
              SectionCard(
                title: 'Historical NASA climate',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Past rainfall and temperature, for the selected historical period. These records are not today’s weather and never generate emergency warnings.',
                    ),
                    const HistoricalWindowSelector(),
                    if (point == null)
                      const Text(
                        'Choose a farm or area to retrieve its historical climate.',
                      )
                    else
                      ClimatePanel(
                        query: ClimateQuery(
                          point,
                          ref.watch(historicalWindowProvider),
                        ),
                      ),
                    TextButton(
                      onPressed: () => context.push('/daily-climate?farm=1'),
                      child: const Text('Open historical daily evidence'),
                    ),
                    TextButton(
                      onPressed: () => context.push('/sources'),
                      child: const Text('About these weather sources'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
