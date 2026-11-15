import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/environment/area_climate.dart';
import '../data/environment/nasa_power_client.dart';
import '../data/models/farmer_input.dart';
import 'dart:async';
import 'local_farm_provider.dart';

final dashboardClimateClientProvider = Provider<NasaPowerClient>(
  (ref) => NasaPowerClient(
    baseUrl: const String.fromEnvironment('BACKEND_URL').isNotEmpty
        ? const String.fromEnvironment('BACKEND_URL')
        : kIsWeb
        ? Uri.base.origin
        : 'https://fieldshift-yangon-2026.web.app',
  ),
);

/// Key includes point AND period. Last-known values can only be shown for that
/// exact query; a changed area/farm/window never inherits another query's data.
final liveDashboardClimateProvider = FutureProvider.autoDispose
    .family<AreaClimate, ClimateQuery>((ref, query) async {
      final evidence = await ref
          .watch(dashboardClimateClientProvider)
          .fetch(
            FarmerInput(
              latitude: query.point.latitude,
              longitude: query.point.longitude,
            ),
            query.window,
          );
      return AreaClimate(evidence, query.window);
    }, retry: (_, _) => null);

final dashboardClimateProvider = FutureProvider.autoDispose
    .family<AreaClimate, ClimateQuery>((ref, query) async {
      final client = ref.watch(dashboardClimateClientProvider);
      final live = ref.watch(liveDashboardClimateProvider(query));
      final liveFuture = ref.watch(liveDashboardClimateProvider(query).future);
      final store = ref.watch(localFarmStoreProvider).value;
      final key =
          'nasa-monthly-v1:${client.baseUrl}:${query.point.latitude}:${query.point.longitude}:${query.window.startYear}-${query.window.startMonth}:${query.window.endYear}-${query.window.endMonth}';
      if (live.hasValue && !live.hasError && !live.isLoading) {
        if (store != null) {
          unawaited(
            store
                .saveSetting(key, {'raw': live.value!.evidence.rawJson})
                .catchError((Object _) {}),
          );
        }
        return live.value!;
      }
      try {
        final saved = await store?.setting(key);
        if (saved?['raw'] is String) {
          final evidence = NasaPowerEvidence.parse(
            saved!['raw'] as String,
            FarmerInput(
              latitude: query.point.latitude,
              longitude: query.point.longitude,
            ),
            query.window,
          );
          return AreaClimate(evidence, query.window, cached: true);
        }
      } catch (_) {
        // An unreadable cache must not substitute invalid evidence or block retrieval.
      }
      return liveFuture;
    }, retry: (_, _) => null);
