import 'package:earthsync/data/local/profile_store.dart';
import 'package:earthsync/data/location/device_location.dart';
import 'package:earthsync/data/models/home_profile.dart';

class MemoryProfileStore implements ProfileStore {
  MemoryProfileStore([this.profile = const HomeProfile()]);
  HomeProfile profile;
  bool failWrites = false;
  @override
  Future<HomeProfile> load() async => HomeProfile.fromJson(profile.toJson());
  @override
  Future<void> save(HomeProfile value) async {
    if (failWrites) throw StateError('storage unavailable');
    profile = HomeProfile.fromJson(value.toJson());
  }
}

class FakeDeviceLocation implements DeviceLocation {
  FakeDeviceLocation({this.failure});
  final LocationFailure? failure;
  int calls = 0;
  @override
  Future<GeoPoint> locate() async {
    calls++;
    if (failure != null) throw failure!;
    return GeoPoint(-1.29, 36.82);
  }
}

HomeProfile confirmedProfile() => HomeProfile(
  onboarded: true,
  activeFarmId: 'field-1',
  farms: [
    ConfirmedFarm(
      id: 'field-1',
      point: GeoPoint(-1.3, 36.8),
      confirmedAt: DateTime.utc(2026, 1, 1),
      name: 'North field',
    ),
  ],
);
