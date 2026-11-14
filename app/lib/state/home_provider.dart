import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/local/profile_store.dart';
import '../data/location/device_location.dart';
import '../data/models/home_profile.dart';
import '../data/models/farm_boundary.dart';

final profileStoreProvider = Provider<ProfileStore>(
  (ref) => LocalProfileStore(),
);
final deviceLocationProvider = Provider<DeviceLocation>(
  (ref) => GeolocatorDeviceLocation(),
);
final homeProfileProvider =
    AsyncNotifierProvider<HomeProfileNotifier, HomeProfile>(
      HomeProfileNotifier.new,
    );

class HomeProfileNotifier extends AsyncNotifier<HomeProfile> {
  Future<void> _pending = Future.value();
  @override
  Future<HomeProfile> build() async {
    try {
      return await ref.watch(profileStoreProvider).load();
    } catch (_) {
      return const HomeProfile(
        storageNotice:
            'Saved choices could not be read. You can continue and save them again.',
      );
    }
  }

  /// Serialize writes and derive each update from the latest profile so an area
  /// update cannot drop a farm saved at the same time. Publish only after saving.
  Future<void> _update(HomeProfile Function(HomeProfile) change) {
    final operation = _pending.then((_) async {
      final current = await future;
      final next = change(current);
      await ref.read(profileStoreProvider).save(next);
      if (ref.mounted) state = AsyncData(next);
    });
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> setArea(ApproximateArea area) =>
      _update((p) => p.withLocation(area));
  Future<void> skip([
    LocationUnavailableReason reason = LocationUnavailableReason.skipped,
  ]) => _update((p) => p.withLocation(UnknownLocation(reason)));
  Future<void> confirmFarm(
    GeoPoint point,
    String name, {
    FarmBoundary? boundary,
  }) => _update((p) {
    if (boundary != null && !boundary.covers(point)) {
      throw const FormatException(
        'The confirmed farm point must be inside its boundary.',
      );
    }
    final now = DateTime.now().toUtc();
    return p.withFarm(
      ConfirmedFarm(
        id: p.farm?.id ?? 'farm-${now.microsecondsSinceEpoch}',
        point: point,
        boundary: boundary,
        confirmedAt: now,
        name: name.trim().isEmpty ? null : name.trim(),
      ),
    );
  });
}
