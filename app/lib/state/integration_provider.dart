import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../data/models/home_profile.dart';
import '../data/service_client.dart';
import '../data/engine/v03_engine.dart';
import '../features/photo_evidence/photo_evidence_client.dart';
import '../features/photo_evidence/photo_evidence_models.dart';
import 'home_provider.dart';

final integrationHttpProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});
final serviceClientProvider = Provider<ServiceClient>(
  (ref) => ServiceClient(ref.watch(integrationHttpProvider)),
);

/// Family key includes the complete target, including farm point revisions.
String environmentalKey(GeoPoint point, {String? farmId}) =>
    '${farmId ?? 'area'}|${point.latitude}|${point.longitude}';

Map<String, dynamic> environmentalQuery(String key) {
  final parts = key.split('|');
  final point = {
    'latitude': double.parse(parts[1]),
    'longitude': double.parse(parts[2]),
  };
  return {
    'schema_version': 'environmental-context/1.0-proposal',
    'timezone': 'UTC',
    'target': parts[0] == 'area'
        ? {'kind': 'selected_area', 'representative_point': point}
        : {
            'kind': 'confirmed_farm',
            'field_id': parts[0],
            'farmer_confirmed': true,
            'point': point,
          },
  };
}

final environmentalProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>(
      (ref, key) => ref
          .watch(serviceClientProvider)
          .json('/api/environmental/v1/context', body: environmentalQuery(key)),
      retry: (_, _) => null,
    );

final catalogProvider = FutureProvider<Map<String, dynamic>>(
  (ref) => ref.watch(serviceClientProvider).json('/api/catalog/v1/profiles'),
  retry: (_, _) => null,
);

class WorkspaceToken extends Notifier<String?> {
  @override
  String? build() => null;
  void connect(String? token) => state = token;
}

// Session memory only. Tokens never enter local farm persistence, URLs or assets.
final workspaceTokenProvider = NotifierProvider<WorkspaceToken, String?>(
  WorkspaceToken.new,
);
final photoRepositoryProvider = Provider<HttpPhotoEvidenceRepository?>((ref) {
  final token = ref.watch(workspaceTokenProvider);
  if (token == null) return null;
  return HttpPhotoEvidenceRepository(
    baseUri: serviceBaseUri(),
    token: token,
    client: ref.watch(integrationHttpProvider),
  );
});
final workspacePhotosProvider = FutureProvider.autoDispose<List<StoredPhoto>>(
  (ref) async => await ref.watch(photoRepositoryProvider)?.list() ?? [],
  retry: (_, _) => null,
);

final satelliteProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, target) {
      final query =
          environmentalQuery(target)['target'] as Map<String, dynamic>;
      final end = DateTime.now().toUtc();
      String day(DateTime value) => value.toIso8601String().substring(0, 10);
      final token = ref.watch(workspaceTokenProvider);
      return ref
          .watch(serviceClientProvider)
          .json(
            token == null
                ? '/api/satellite/v1/timeline'
                : '/api/evidence/v1/timeline',
            headers: token == null
                ? const {}
                : {'Authorization': 'Bearer $token'},
            body: {
              'schema_version': 'evidence.v1',
              'field': {
                'farm_id': query['field_id'],
                'confirmed_by_farmer': true,
                'point': query['point'],
              },
              'start': day(end.subtract(const Duration(days: 90))),
              'end': day(end),
            },
          );
    }, retry: (_, _) => null);

class AssessmentState {
  const AssessmentState({
    this.result,
    this.running = false,
    this.error,
    this.reference,
  });
  final V03Result? result;
  final bool running;
  final String? error;
  final Map<String, dynamic>? reference;
}

class AssessmentNotifier extends Notifier<AssessmentState> {
  int _generation = 0;
  @override
  AssessmentState build() {
    // Any farm edit invalidates results and in-flight callbacks, even if ID stays.
    ref.watch(homeProfileProvider.select((p) => p.value?.farm));
    ++_generation;
    ref.onDispose(() => ++_generation);
    return const AssessmentState();
  }

  Future<void> run({
    String? profileId,
    DateTime? start,
    DateTime? end,
    bool synthetic = false,
  }) async {
    final generation = ++_generation;
    final farm = ref.read(homeProfileProvider).value?.farm;
    final service = ref.read(serviceClientProvider);
    state = const AssessmentState(running: true);
    try {
      late Map<String, dynamic> request;
      Map<String, dynamic>? reference;
      if (synthetic) {
        request = await service.json('/api/demo/synthetic-v03');
        if (request['mode'] != 'software_test') {
          throw const FormatException('Expected labeled software test.');
        }
      } else {
        if (farm == null || profileId == null || start == null || end == null) {
          throw const ServiceFailure(
            'Confirm a farm and enter a profile and exact growing dates first.',
          );
        }
        final adapted = await service.json(
          '/api/catalog/v1/assessment-request',
          body: {
            'profile_id': profileId,
            'farm': {
              'field_id': farm.id,
              'point': farm.point.toJson(),
              'confirmed_on': farm.confirmedAt
                  .toUtc()
                  .toIso8601String()
                  .substring(0, 10),
            },
            'start': start.toIso8601String().substring(0, 10),
            'end': end.toIso8601String().substring(0, 10),
          },
        );
        request = adapted['request'] as Map<String, dynamic>;
        reference = adapted;
      }
      final result = await V03Engine(
        service,
      ).analyze(V03Request.fromJson(request));
      if (ref.mounted && generation == _generation) {
        state = AssessmentState(result: result, reference: reference);
      }
    } catch (error) {
      if (ref.mounted && generation == _generation) {
        state = AssessmentState(error: error.toString());
      }
    }
  }
}

final assessmentProvider =
    NotifierProvider<AssessmentNotifier, AssessmentState>(
      AssessmentNotifier.new,
    );
