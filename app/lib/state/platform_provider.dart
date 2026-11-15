import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/environment/platform_climate.dart';
import '../data/platform_transport.dart';
import '../data/platform_farms.dart';
import 'home_provider.dart';
import 'integration_provider.dart';

final platformFarmClientProvider = Provider<PlatformFarmClient?>(
  (ref) => platformUrl.isEmpty
      ? null
      : PlatformFarmClient(
          PlatformTransport(
            ref.watch(integrationHttpProvider),
            baseUri: Uri.parse(platformUrl),
          ),
        ),
);

/// A farm edit creates a new confirmation revision. Never inherit evidence,
/// photos or in-flight responses belonging to the previous confirmation.
final platformFarmProvider = FutureProvider.autoDispose<PlatformFarm?>((
  ref,
) async {
  final local = ref.watch(homeProfileProvider).value?.farm;
  final client = ref.watch(platformFarmClientProvider);
  return local == null || client == null ? null : client.link(local);
});
final platformContextProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
      final client = ref.watch(platformFarmClientProvider);
      final farm = await ref.watch(platformFarmProvider.future);
      return farm == null || client == null || !ref.mounted
          ? null
          : client.context(farm.id);
    });
final platformDecisionsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final client = ref.watch(platformFarmClientProvider);
      final farm = await ref.watch(platformFarmProvider.future);
      return farm == null || client == null || !ref.mounted
          ? []
          : client.decisions(farm.id);
    });
final platformAssistantProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
      final client = ref.watch(platformFarmClientProvider);
      final farm = await ref.watch(platformFarmProvider.future);
      return farm == null || client == null || !ref.mounted
          ? null
          : client.assistant(farm.id);
    });
