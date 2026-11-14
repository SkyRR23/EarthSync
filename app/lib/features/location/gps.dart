import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../app/strings.dart';

/// One GPS reading. Returns the point, or a plain message saying why not.
Future<({LatLng? point, String? message})> readGps() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return (point: null, message: S.gpsOff);
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return (point: null, message: S.gpsDenied);
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: Duration(seconds: 20),
      ),
    );
    return (point: LatLng(pos.latitude, pos.longitude), message: null);
  } catch (_) {
    return (point: null, message: S.gpsFailed);
  }
}
