import 'package:earthsync/data/local/profile_store.dart';
import 'package:earthsync/data/models/home_profile.dart';
import 'package:earthsync/state/home_provider.dart';
import 'package:earthsync/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_test_support.dart';

void main() {
  test('first launch is unknown and unconfirmed; skip is persisted', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final initial = await container.read(homeProfileProvider.future);
    expect(initial.onboarded, false);
    expect(initial.userLocation, isA<UnknownLocation>());
    expect(initial.farm, null);
    await container.read(homeProfileProvider.notifier).skip();
    final restored = await LocalProfileStore().load();
    expect(restored.onboarded, true);
    expect(
      (restored.userLocation as UnknownLocation).reason,
      LocationUnavailableReason.skipped,
    );
  });
  test('confirm, restore, edit farm; changing area never moves farm', () async {
    final store = MemoryProfileStore();
    final container = ProviderContainer(
      overrides: [profileStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    await container.read(homeProfileProvider.future);
    final notifier = container.read(homeProfileProvider.notifier);
    final farmPoint = GeoPoint(-23.55, -46.63);
    await notifier.confirmFarm(farmPoint, ' South field ');
    final farm = container.read(homeProfileProvider).value!.farm!;
    expect(farm.name, 'South field');
    final persisted = await store.load();
    expect(persisted.farm!.point, farmPoint);
    expect(persisted.farm!.confirmedAt, farm.confirmedAt);
    await notifier.setArea(
      ApproximateArea(
        point: GeoPoint(50, 0),
        label: 'Other area',
        source: AreaSource.manual,
      ),
    );
    expect(container.read(homeProfileProvider).value!.farm!.point, farmPoint);
    await notifier.skip(LocationUnavailableReason.denied);
    expect(container.read(homeProfileProvider).value!.farm!.point, farmPoint);
    await notifier.confirmFarm(GeoPoint(-23.56, -46.64), 'West field');
    final edited = container.read(homeProfileProvider).value!.farm!;
    expect(edited.id, farm.id);
    expect(container.read(homeProfileProvider).value!.farms.length, 1);
    expect(edited.name, 'West field');
    final returning = ProviderContainer(
      overrides: [profileStoreProvider.overrideWithValue(store)],
    );
    addTearDown(returning.dispose);
    expect(
      (await returning.read(homeProfileProvider.future)).farm!.point,
      edited.point,
    );
    final draft = returning.read(farmerDraftProvider);
    expect(draft.latitude, edited.point.latitude);
    expect(draft.longitude, edited.point.longitude);
  });
  test('concurrent area and farm saves do not lose either choice', () async {
    final container = ProviderContainer(
      overrides: [profileStoreProvider.overrideWithValue(MemoryProfileStore())],
    );
    addTearDown(container.dispose);
    await container.read(homeProfileProvider.future);
    final n = container.read(homeProfileProvider.notifier);
    await Future.wait([
      n.confirmFarm(GeoPoint(0, 0), ''),
      n.setArea(
        ApproximateArea(
          point: GeoPoint(80, 170),
          label: 'Area',
          source: AreaSource.manual,
        ),
      ),
    ]);
    final p = container.read(homeProfileProvider).value!;
    expect(p.farm!.point, GeoPoint(0, 0));
    expect(p.farm!.name, null);
    expect((p.userLocation as ApproximateArea).point, GeoPoint(80, 170));
  });
  test('failed save leaves last confirmed farm intact', () async {
    final store = MemoryProfileStore(confirmedProfile());
    final container = ProviderContainer(
      overrides: [profileStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    final original = await container.read(homeProfileProvider.future);
    store.failWrites = true;
    await expectLater(
      container
          .read(homeProfileProvider.notifier)
          .confirmFarm(GeoPoint(1, 1), 'New'),
      throwsStateError,
    );
    expect(
      container.read(homeProfileProvider).value!.farm!.point,
      original.farm!.point,
    );
  });
  test('invalid saved record recovers without fabricating a farm', () async {
    SharedPreferences.setMockInitialValues({LocalProfileStore.key: '{broken'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final p = await container.read(homeProfileProvider.future);
    expect(p.farm, null);
    expect(p.storageNotice, isNotNull);
  });
  test('global coordinate boundaries and nonfinite values are validated', () {
    expect(GeoPoint(-90, 180).latitude, -90);
    for (final pair in [
      [91.0, 0.0],
      [0.0, -181.0],
      [double.nan, 0.0],
      [0.0, double.infinity],
    ]) {
      expect(() => GeoPoint(pair[0], pair[1]), throwsFormatException);
    }
  });
}
