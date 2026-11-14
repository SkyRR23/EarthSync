import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/home_profile.dart';

abstract interface class ProfileStore {
  Future<HomeProfile> load();
  Future<void> save(HomeProfile profile);
}

/// One local record; never synchronizes coordinates to an account or cloud.
class LocalProfileStore implements ProfileStore {
  static const key = 'earthsync.home.v1';
  @override
  Future<HomeProfile> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    return raw == null
        ? const HomeProfile()
        : HomeProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> save(HomeProfile profile) async {
    final saved = await (await SharedPreferences.getInstance()).setString(
      key,
      jsonEncode(profile.toJson()),
    );
    if (!saved) throw StateError('Local storage is unavailable.');
  }
}
