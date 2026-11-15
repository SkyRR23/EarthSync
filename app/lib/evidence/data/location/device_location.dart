import 'package:geolocator/geolocator.dart';
import '../models/home_profile.dart';

class LocationFailure implements Exception {
  const LocationFailure(this.message, this.reason);
  final String message;
  final LocationUnavailableReason reason;
}

abstract interface class DeviceLocation {
  Future<GeoPoint> locate();
}

class GeolocatorDeviceLocation implements DeviceLocation {
  @override
  Future<GeoPoint> locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const LocationFailure(
          'Location is unavailable. Choose an area or skip for now.',
          LocationUnavailableReason.unavailable,
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const LocationFailure(
          'Location permission was denied. You can still choose an area or skip.',
          LocationUnavailableReason.denied,
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return GeoPoint(
        double.parse(position.latitude.toStringAsFixed(2)),
        double.parse(position.longitude.toStringAsFixed(2)),
      );
    } on LocationFailure {
      rethrow;
    } catch (_) {
      throw const LocationFailure(
        'Location is not available here. Browsers usually need HTTPS or localhost. Choose an area or skip.',
        LocationUnavailableReason.unavailable,
      );
    }
  }
}
