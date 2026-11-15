import '../../app/ui_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/ui_copy.dart';
import '../../data/environment/area_climate.dart';
import '../../data/models/home_profile.dart';
import '../../design/components/product.dart';
import '../../state/providers.dart';
import '../../state/home_provider.dart';
import '../../state/dashboard_provider.dart';
import '../results/climate_provenance.dart';
import '../field/evidence_panels.dart';
import '../../state/integration_provider.dart';
import 'source_directory.dart';

class SourcesScreen extends ConsumerWidget {
  const SourcesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String tr(String k) => UiCopy.text(context, k);
    final profile = ref.watch(homeProfileProvider).value;
    final area = profile?.userLocation;
    final point =
        profile?.farm?.point ?? (area is ApproximateArea ? area.point : null);
    final legacy = ref.watch(analysisProvider);
    final analysis = legacy is AnalysisReady ? legacy.analysis : null;
    final climate = point == null
        ? null
        : ref.watch(
            dashboardClimateProvider(
              ClimateQuery(point, ref.watch(historicalWindowProvider)),
            ),
          );
    final provenance = climate?.value?.evidence.provenance;
    return Scaffold(
      appBar: AppBar(title: Text(tr('sources'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SourceDirectory(),
              PageHeader(title: tr('sources'), subtitle: tr('sourceNote')),
              EvidenceNotice(
                title: UiLabels.readTheEvidenceInContext,
                message: UiLabels.availableMeansASourceReturnedDataNotThat,
              ),
              if (point == null)
                const EvidenceNotice(
                  title: UiLabels.noLocationSpecificEvidenceLoaded,
                  message: UiLabels.chooseAnAreaOrConfirmAFarmTo,
                  icon: Icons.location_off_outlined,
                ),
              if (climate?.isLoading == true)
                const LinearProgressIndicator(
                  semanticsLabel: UiLabels.loadingClimateSourceInformation,
                ),
              if (climate?.hasError == true)
                const EvidenceNotice(
                  title: UiLabels.climateSourceUnavailable,
                  message: UiLabels.theClimateServiceDidNotReturnAValidated,
                ),
              if (provenance != null)
                SectionCard(
                  title: UiLabels.nasaPOWERHistoricalClimate,
                  icon: Icons.water_drop_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Provider: ${provenance['provider']}'),
                      Text('Dataset: ${provenance['product']}'),
                      Text('Spatial support: ${provenance['spatial_support']}'),
                      const Text(
                        UiLabels.unitsRainfallMmPerMonthTemperatureMonthlyMean,
                      ),
                      for (final request
                          in provenance['source_requests'] as List) ...[
                        Text('Retrieved: ${request['retrieved_at']}'),
                        SelectableText(
                          Uri.parse(request['endpoint'] as String)
                              .replace(
                                queryParameters: (request['query'] as Map).map(
                                  (k, v) => MapEntry('$k', '$v'),
                                ),
                              )
                              .toString(),
                        ),
                      ],
                      EvidenceDetails(
                        title: UiLabels.sourceDatesCoverageQualityLimitations,
                        data: provenance,
                      ),
                    ],
                  ),
                ),
              SectionCard(
                title: UiLabels.nasaGIBSDisplayImagery,
                icon: Icons.satellite_alt_outlined,
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(UiLabels.modisTerraTrueColourProvisionalDisplayLayer),
                    Text(UiLabels.requestedImageDatesAreShownWithEachView),
                    SelectableText('https://gibs.earthdata.nasa.gov'),
                  ],
                ),
              ),
              if (point != null)
                EnvironmentalPanel(
                  target: environmentalKey(point, farmId: profile?.farm?.id),
                ),
              if (analysis != null) ...[
                ClimateProvenance(analysis: analysis),
                for (final source in analysis.references)
                  SectionCard(
                    title: source.title,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Evidence type: ${source.type.name}'),
                        if (source.period != null) Text(source.period!),
                        if (source.spatialScale != null)
                          Text(source.spatialScale!),
                        if (source.url != null) SelectableText(source.url!),
                        if (source.note != null) Text(source.note!),
                      ],
                    ),
                  ),
                if (analysis.trace != null)
                  EvidenceDetails(
                    title: UiLabels.technicalIntegrationTrace,
                    data: {
                      'backend': analysis.trace!.backendResponseJson,
                      'rustRequest': analysis.trace!.rustRequestJson,
                      'rustResult': analysis.trace!.rustResultJson,
                    },
                  ),
              ],
              const EvidenceNotice(
                title: UiLabels.cropProfilesRemainReferenceOnly,
                message:
                    UiLabels.theGlobalCatalogIsRecommendationIneligibleAProfile,
              ),
              const SourceNote(),
            ],
          ),
        ),
      ),
    );
  }
}
