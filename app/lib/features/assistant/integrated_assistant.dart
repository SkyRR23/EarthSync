import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/environment/area_climate.dart';
import '../../data/models/home_profile.dart';
import '../../state/home_provider.dart';
import '../../state/dashboard_provider.dart';
import '../../state/integration_provider.dart';
import '../../state/providers.dart';
import 'assistant_client.dart';
import 'assistant_models.dart';
import 'assistant_context_adapter.dart';
import 'assistant_screen.dart';

final assistantServiceProvider = Provider<AssistantService>(
  (ref) => HttpAssistantService(
    endpoint: ref
        .watch(serviceClientProvider)
        .baseUri
        .resolve('/api/assistant/v1/chat'),
    client: ref.watch(integrationHttpProvider),
    allowInsecureLocalDemo:
        kIsWeb &&
        Uri.base.scheme == 'http' &&
        Uri.base.origin == ref.watch(serviceClientProvider).baseUri.origin,
  ),
);

/// Binds only evidence actually loaded for this selection. Missing providers and
/// source metadata stay missing; private tokens and photo GPS are never included.
final integratedAssistantContextProvider = Provider.autoDispose.family<AssistantContext, bool>((
  ref,
  areaOnly,
) {
  final profile = ref.watch(homeProfileProvider).value;
  final farm = areaOnly ? null : profile?.farm;
  final area = profile?.userLocation;
  final point = farm?.point ?? (area is ApproximateArea ? area.point : null);
  final selectionId =
      farm?.id ??
      (point == null ? null : 'area:${point.latitude}:${point.longitude}');
  final evidence = <AssistantEvidence>[];
  final sources = <AssistantSource>[];
  final decisions = <AssistantDecision>[];
  final limitations = <String>[
    'No independently verified crop recommendation is available. Historical climate is not current weather.',
  ];
  final window = ref.watch(historicalWindowProvider);
  final legacy = ref.watch(analysisProvider);
  if (farm != null &&
      legacy is AnalysisReady &&
      legacy.analysis.location.latitude == point!.latitude &&
      legacy.analysis.location.longitude == point.longitude) {
    final bound = assistantContextFromAnalysis(
      contextId: 'legacy',
      analysis: legacy.analysis,
      confirmedFarm: AssistantSelection(
        id: farm.id,
        point: AssistantPoint(point.latitude, point.longitude),
      ),
    );
    evidence.addAll(bound.evidence);
    sources.addAll(bound.sources);
    decisions.addAll(bound.decisions);
    limitations.addAll(bound.limitations.take(15));
  } else if (point != null) {
    final climate = ref
        .watch(dashboardClimateProvider(ClimateQuery(point, window)))
        .value;
    if (climate != null) {
      final p = climate.evidence.provenance;
      final sourceIds = <String>[];
      final requests = (p['source_requests'] as List)
          .cast<Map<String, dynamic>>();
      for (final (i, request) in requests.indexed) {
        final id = 'power-$i';
        final url = Uri.parse(request['endpoint'] as String).replace(
          queryParameters: (request['query'] as Map).map(
            (k, v) => MapEntry('$k', '$v'),
          ),
        );
        sources.add(
          AssistantSource(
            id: id,
            provider: p['provider'] as String,
            title: p['product'] as String,
            url: url.toString(),
          ),
        );
        sourceIds.add(id);
      }
      for (final (i, row) in climate.readings.indexed) {
        for (final rain in [true, false]) {
          final value = rain ? row.rainMm : row.temperatureC;
          evidence.add(
            AssistantEvidence(
              id: 'monthly-$i-${rain ? 'rain' : 'temperature'}',
              topic: rain
                  ? AssistantTopic.rainfall
                  : AssistantTopic.temperature,
              metric: rain ? 'rainfall_total' : 'mean_temperature',
              kind: AssistantKind.modeled,
              quality: value == null
                  ? AssistantQuality.missing
                  : AssistantQuality.available,
              scope: AssistantScope.regional,
              locationId: selectionId,
              value: value,
              unit: rain ? 'mm' : 'deg_c',
              startDate: row.month.toIso8601String().substring(0, 10),
              endDate: DateTime.utc(
                row.month.year,
                row.month.month + 1,
                0,
              ).toIso8601String().substring(0, 10),
              retrievedAt: requests.first['retrieved_at'] as String?,
              spatialSupport: p['spatial_support'] as String,
              sourceIds: sourceIds,
              limitations: [
                'Historical NASA POWER MERRA-2 monthly context; not a farm measurement.',
              ],
            ),
          );
        }
      }
    } else {
      limitations.add(
        'NASA climate has not been retrieved for the current point and dates.',
      );
    }
  }
  if (point != null) {
    final target = environmentalKey(point, farmId: farm?.id);
    final context = ref.watch(environmentalProvider(target)).value;
    for (final item in context?['evidence'] as List? ?? []) {
      final id = 'environment-${item['context_kind']}';
      final source = item['source'] as Map;
      final docs = source['documentation'] as List;
      sources.add(
        AssistantSource(
          id: id,
          provider: source['provider'] as String,
          title: source['dataset'] as String,
          url: docs.isEmpty ? null : docs.first as String,
        ),
      );
      evidence.add(
        AssistantEvidence(
          id: id,
          topic: item['context_kind'] == 'soil'
              ? AssistantTopic.soil
              : item['context_kind'] == 'weather'
              ? AssistantTopic.climate
              : AssistantTopic.vegetation,
          metric: item['context_kind'] as String,
          kind: AssistantKind.unavailable,
          quality: AssistantQuality.unavailable,
          scope: AssistantScope.regional,
          locationId: selectionId,
          sourceIds: [id],
          limitations: [
            '${item['reason'] ?? item['availability']}',
            'Reference/probe values are not usable for analysis.',
          ],
        ),
      );
    }
    if (farm != null) {
      final satellite = ref.watch(satelliteProvider(target)).value;
      for (final (i, provider)
          in (satellite?['providers'] as List? ?? []).indexed) {
        final id = 'satellite-$i';
        sources.add(
          AssistantSource(
            id: id,
            provider: provider['provider'] as String,
            title: 'Satellite evidence availability',
            url: provider['source_url'] as String,
          ),
        );
        evidence.add(
          AssistantEvidence(
            id: id,
            topic: i == 0 ? AssistantTopic.vegetation : AssistantTopic.radar,
            metric: 'availability',
            kind: AssistantKind.unavailable,
            quality: AssistantQuality.unavailable,
            scope: AssistantScope.field,
            locationId: farm.id,
            sourceIds: [id],
            limitations: [provider['reason'] as String],
          ),
        );
      }
      final photos = ref
          .watch(workspacePhotosProvider)
          .value
          ?.where((p) => p.farmId == farm.id)
          .toList();
      evidence.add(
        AssistantEvidence(
          id: 'private-photo-availability',
          topic: AssistantTopic.photo,
          metric: 'farmer_photo_availability',
          kind: photos == null
              ? AssistantKind.unavailable
              : AssistantKind.farmerReported,
          quality: photos == null
              ? AssistantQuality.unavailable
              : AssistantQuality.unverified,
          scope: AssistantScope.field,
          locationId: farm.id,
          value: photos == null
              ? null
              : '${photos.length} farmer-associated photos in the connected private workspace',
          limitations: [
            'No pixels, GPS, captions or workspace token sent to the assistant. Photos do not establish health or location.',
          ],
        ),
      );
    }
  }
  final result = ref.watch(assessmentProvider).result;
  if (!areaOnly && farm != null && result != null) {
    final rustSources = (result.context?['sources'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    for (final source in rustSources) {
      sources.add(
        AssistantSource(
          id: 'v03-${source['id']}',
          provider: 'Supplied Rust v0.3 source',
          title: source['title'] as String,
          url: source['url'] as String?,
        ),
      );
    }
    for (final (i, summary) in result.summaries.indexed) {
      final ids = result.findings
          .where((f) => f['scenario_id'] == summary['scenario_id'])
          .expand((f) => (f['source_ids'] as List).cast<String>())
          .toSet();
      decisions.add(
        AssistantDecision(
          id: 'v03-$i',
          scenarioId: summary['scenario_id'] as String,
          status: summary['status'] as String,
          synthetic: result.synthetic,
          sourceIds: ids.map((id) => 'v03-$id').take(20).toList(),
          limitations: [
            if (result.synthetic) 'Fictional software test; not this farm.',
            'Full per-crop findings, missing inputs and limitations are available in Crop assessment.',
          ],
        ),
      );
    }
    if (result.validation != null) {
      limitations.add(
        'Rust v0.3 rejected the inputs. No assessment was produced.',
      );
    }
  }
  final catalog = ref.watch(catalogProvider).value;
  limitations.add(
    catalog == null
        ? 'Crop catalog has not loaded; no crop evidence assumed.'
        : 'All global catalog profiles are reference-only and recommendation_eligible=false. Daily climate, soil depth, cultivar duration and Kc gaps remain.',
  );
  final uniqueSources = {
    for (final source in sources) source.id: source,
  }.values.toList();
  final base = AssistantContext(
    contextId: 'snapshot',
    approximateLocation:
        profile?.approximateDeviceLocation == null ||
            area is! ApproximateArea ||
            area.source != AreaSource.device
        ? null
        : AssistantPoint(
            profile!.approximateDeviceLocation!.latitude,
            profile.approximateDeviceLocation!.longitude,
          ),
    selectedArea: area is ApproximateArea
        ? AssistantSelection(
            id: 'area:${area.point.latitude}:${area.point.longitude}',
            point: AssistantPoint(area.point.latitude, area.point.longitude),
          )
        : null,
    confirmedFarm: farm == null
        ? null
        : AssistantSelection(
            id: farm.id,
            point: AssistantPoint(farm.point.latitude, farm.point.longitude),
          ),
    evidence: evidence,
    decisions: decisions,
    sources: uniqueSources,
    limitations: limitations.take(30).toList(),
  );
  return AssistantContext.fromJson({
    ...base.toJson(),
    'context_id': 'selection-${jsonEncode(base.toJson()).hashCode}',
  });
});

class IntegratedAssistantScreen extends ConsumerWidget {
  const IntegratedAssistantScreen({super.key, this.areaOnly = false});
  final bool areaOnly;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('EarthSync assistant')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: FarmerAssistant(
          context: ref.watch(integratedAssistantContextProvider(areaOnly)),
          service: ref.watch(assistantServiceProvider),
        ),
      ),
    ),
  );
}
