/// User area and farm confirmation are independent, versioned local records.
class GeoPoint {
  GeoPoint(this.latitude, this.longitude) {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw const FormatException('Enter valid latitude and longitude.');
    }
  }
  final double latitude, longitude;
  String get label =>
      '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
  };
  factory GeoPoint.fromJson(Map<String, dynamic> json) => GeoPoint(
    (json['latitude'] as num).toDouble(),
    (json['longitude'] as num).toDouble(),
  );
  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      latitude == other.latitude &&
      longitude == other.longitude;
  @override
  int get hashCode => Object.hash(latitude, longitude);
}

enum LocationUnavailableReason { unknown, skipped, denied, unavailable }

enum AreaSource { device, manual, example }

sealed class UserLocation {
  const UserLocation();
  Map<String, dynamic> toJson();
  factory UserLocation.fromJson(Map<String, dynamic> json) =>
      json['kind'] == 'area'
      ? ApproximateArea(
          point: GeoPoint.fromJson(json['point'] as Map<String, dynamic>),
          label: json['label'] as String,
          source: AreaSource.values.byName(json['source'] as String),
        )
      : UnknownLocation(
          LocationUnavailableReason.values.byName(json['reason'] as String),
        );
}

class UnknownLocation extends UserLocation {
  const UnknownLocation([this.reason = LocationUnavailableReason.unknown]);
  final LocationUnavailableReason reason;
  @override
  Map<String, dynamic> toJson() => {'kind': 'unknown', 'reason': reason.name};
}

class ApproximateArea extends UserLocation {
  const ApproximateArea({
    required this.point,
    required this.label,
    required this.source,
  });
  final GeoPoint point;
  final String label;
  final AreaSource source;
  @override
  Map<String, dynamic> toJson() => {
    'kind': 'area',
    'point': point.toJson(),
    'label': label,
    'source': source.name,
  };
}

/// A point the farmer explicitly confirmed. No inferred polygon or boundary.
class ConfirmedFarm {
  const ConfirmedFarm({
    required this.id,
    required this.point,
    required this.confirmedAt,
    this.name,
  });
  final String id;
  final GeoPoint point;
  final DateTime confirmedAt;
  final String? name;
  Map<String, dynamic> toJson() => {
    'id': id,
    'point': point.toJson(),
    'confirmed_at': confirmedAt.toUtc().toIso8601String(),
    'name': name,
  };
  factory ConfirmedFarm.fromJson(Map<String, dynamic> json) => ConfirmedFarm(
    id: json['id'] as String,
    point: GeoPoint.fromJson(json['point'] as Map<String, dynamic>),
    confirmedAt: DateTime.parse(json['confirmed_at'] as String),
    name: json['name'] as String?,
  );
}

class HomeProfile {
  const HomeProfile({
    this.onboarded = false,
    this.userLocation = const UnknownLocation(),
    this.farms = const [],
    this.activeFarmId,
    this.storageNotice,
    this.approximateDeviceLocation,
  });
  final bool onboarded;
  final UserLocation userLocation;
  final List<ConfirmedFarm> farms;
  final String? activeFarmId;
  final String? storageNotice;
  final GeoPoint? approximateDeviceLocation;
  ConfirmedFarm? get farm {
    for (final farm in farms) {
      if (farm.id == activeFarmId) return farm;
    }
    return null;
  }

  HomeProfile withLocation(UserLocation location) => HomeProfile(
    onboarded: true,
    userLocation: location,
    farms: farms,
    activeFarmId: activeFarmId,
    approximateDeviceLocation:
        location is ApproximateArea && location.source == AreaSource.device
        ? location.point
        : approximateDeviceLocation,
  );
  HomeProfile withFarm(ConfirmedFarm farm) => HomeProfile(
    onboarded: true,
    userLocation: userLocation,
    activeFarmId: farm.id,
    farms: List.unmodifiable([...farms.where((f) => f.id != farm.id), farm]),
    approximateDeviceLocation: approximateDeviceLocation,
  );
  Map<String, dynamic> toJson() => {
    'version': 1,
    'onboarded': onboarded,
    'user_location': userLocation.toJson(),
    'farms': farms.map((f) => f.toJson()).toList(),
    'active_farm_id': activeFarmId,
    'approximate_device_location': approximateDeviceLocation?.toJson(),
  };
  factory HomeProfile.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unknown profile version');
    }
    return HomeProfile(
      onboarded: json['onboarded'] as bool,
      userLocation: UserLocation.fromJson(
        json['user_location'] as Map<String, dynamic>,
      ),
      farms: List.unmodifiable(
        (json['farms'] as List).map(
          (f) => ConfirmedFarm.fromJson(f as Map<String, dynamic>),
        ),
      ),
      activeFarmId: json['active_farm_id'] as String?,
      approximateDeviceLocation: json['approximate_device_location'] == null
          ? null
          : GeoPoint.fromJson(
              json['approximate_device_location'] as Map<String, dynamic>,
            ),
    );
  }
}
