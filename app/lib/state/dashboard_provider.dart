import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/environment/area_climate.dart';
import '../data/environment/nasa_power_client.dart';
import '../data/models/farmer_input.dart';

final dashboardClimateClientProvider = Provider<NasaPowerClient>(
  (ref) => NasaPowerClient(
    baseUrl: const String.fromEnvironment('BACKEND_URL').isNotEmpty
        ? const String.fromEnvironment('BACKEND_URL')
        : kIsWeb
        ? Uri.base.origin
        : 'http://127.0.0.1:8000',
  ),
);

/// Key includes point AND period. Last-known values can only be shown for that
/// exact query; a changed area/farm/window never inherits another query's data.
final dashboardClimateProvider = FutureProvider.autoDispose
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
