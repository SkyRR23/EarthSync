import '../../data/environment/platform_climate.dart';
import '../../app/ui_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/ui_copy.dart';
import '../../data/environment/area_climate.dart';
import '../../design/components/product.dart';
import '../../state/home_provider.dart';
import '../../state/providers.dart';
import '../../state/integration_provider.dart';
import '../dashboard/climate_panel.dart';
import '../dashboard/satellite_preview.dart';
import 'evidence_panels.dart';

class FieldScreen extends ConsumerWidget {
  const FieldScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final farm = ref.watch(homeProfileProvider).value?.farm;
    if (farm == null) {
      return const Scaffold(
        body: Center(child: Text(UiLabels.confirmAFarmFirst)),
      );
    }
    String tr(String k) => UiCopy.text(context, k);
    final target = environmentalKey(farm.point, farmId: farm.id);
    return Scaffold(
      appBar: AppBar(
        title: const Text(UiLabels.fieldSituation),
        actions: [
          IconButton(
            tooltip: UiLabels.editMyFarm,
            onPressed: () => context.push('/location'),
            icon: const Icon(Icons.edit_location_alt_outlined),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (platformUrl.isNotEmpty)
                OutlinedButton(
                  onPressed: () => context.push('/farm-evidence'),
                  child: const Text('Persisted farm evidence'),
                ),
              PageHeader(
                eyebrow: tr('point'),
                title: farm.name ?? tr('farm'),
                subtitle: '${farm.point.label} · ${tr('fieldBody')}',
              ),
              ResponsivePair(
                first: ActionCard(
                  title: tr('planning'),
                  body: tr('planningBody'),
                  icon: Icons.spa_outlined,
                  onTap: () => context.push('/assessment'),
                ),
                second: ActionCard(
                  title: UiLabels.fieldPhotos,
                  body: tr('photoBody'),
                  icon: Icons.photo_library_outlined,
                  onTap: () => context.push('/photos'),
                ),
              ),
              EvidenceNotice(
                title: UiLabels.fieldConditionIsUnknown,
                message: UiLabels.regionalEstimatesAndPhotosDoNotEstablishSoil,
                icon: Icons.info_outline,
              ),
              ClimatePanel(
                query: ClimateQuery(
                  farm.point,
                  ref.watch(historicalWindowProvider),
                ),
              ),
              const SizedBox(height: 16),
              EnvironmentalPanel(target: target),
              const SizedBox(height: 16),
              SatellitePreview(point: farm.point),
              SatelliteEvidencePanel(target: target),
              ActionCard(
                title: tr('ask'),
                body: tr('askBody'),
                icon: Icons.chat_outlined,
                onTap: () => context.push('/assistant'),
              ),
              const SourceNote(),
            ],
          ),
        ),
      ),
    );
  }
}
