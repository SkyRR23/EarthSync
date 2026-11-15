import 'package:earthsync/evidence/data/local/profile_store.dart';
import 'package:earthsync/evidence/data/location/device_location.dart';
import 'package:earthsync/evidence/data/models/home_profile.dart';
import 'package:earthsync/evidence/data/local/database.dart';
import 'package:earthsync/evidence/data/local/farm_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<LocalFarmStore> memoryFarmStore(WidgetTester tester) async {
  final store = (await tester.runAsync(() async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: createFarmSchema,
        singleInstance: false,
      ),
    );
    return LocalFarmStore(db);
  }))!;
  addTearDown(store.db.close);
  return store;
}

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
