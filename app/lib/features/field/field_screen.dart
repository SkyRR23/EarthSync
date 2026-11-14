import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/environment/area_climate.dart';
import '../../state/home_provider.dart';
import '../../state/providers.dart';
import '../../state/integration_provider.dart';
import '../dashboard/climate_panel.dart';
import 'evidence_panels.dart';

class FieldScreen extends ConsumerWidget {
  const FieldScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final farm = ref.watch(homeProfileProvider).value?.farm;
    if (farm == null) {
      return const Scaffold(body: Center(child: Text('Confirm a farm first.')));
    }
    final target = environmentalKey(farm.point, farmId: farm.id);
    return Scaffold(
      appBar: AppBar(title: const Text('Field situation')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                farm.name ?? 'My Farm',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Text('Farmer-confirmed point · ${farm.point.label}'),
              const Text(
                'Field condition is unknown. Regional estimates and photos do not establish soil health, crop stress or disease.',
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => context.push('/photos'),
                    child: const Text('Field photos'),
                  ),
                  OutlinedButton(
                    onPressed: () => context.push('/assessment'),
                    child: const Text('Crop assessment'),
                  ),
                  OutlinedButton(
                    onPressed: () => context.push('/assistant'),
                    child: const Text('Ask the assistant'),
                  ),
                ],
              ),
              ClimatePanel(
                query: ClimateQuery(
                  farm.point,
                  ref.watch(historicalWindowProvider),
                ),
              ),
              const SizedBox(height: 20),
              EnvironmentalPanel(target: target),
              const SizedBox(height: 20),
              SatelliteEvidencePanel(target: target),
            ],
          ),
        ),
      ),
    );
  }
}
