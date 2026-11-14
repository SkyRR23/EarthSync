import 'dart:typed_data';

enum PhotoCategory { crop, soil, water }

enum PhotoOrigin { camera, gallery, browserFile }

/// Supplied by the farm owner after farmer confirmation; no location inference.
class ConfirmedFarmReference {
  ConfirmedFarmReference(this.id) {
    if (id.trim().isEmpty || id != id.trim() || id.length > 128) {
      throw ArgumentError.value(id, 'id', 'Use a confirmed farm identifier');
    }
  }
  final String id;
  Map<String, Object> toJson() => {'farm_id': id, 'confirmed_by_farmer': true};
}

class PhotoGps {
  const PhotoGps(this.latitude, this.longitude);
  final double latitude;
  final double longitude;

  Map<String, Object?> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'uncertainty_m': null,
    'source': 'consented_exif',
    'retention_authorized': true,
  };
}

class PreparedPhoto {
  const PreparedPhoto({
    required this.png,
    required this.origin,
    required this.width,
    required this.height,
    this.gps,
    this.gpsRequested = false,
  });
  final Uint8List png;
  final PhotoOrigin origin;
  final int width;
  final int height;
  final PhotoGps? gps;
  final bool gpsRequested;

  PreparedPhoto withoutGps() =>
      PreparedPhoto(png: png, origin: origin, width: width, height: height);
}

class PhotoDraft {
  const PhotoDraft({
    required this.photo,
    required this.category,
    this.caption = '',
    this.farmerObservations = '',
    this.capturedDate,
    this.farm,
    this.synthetic = false,
  });
  final PreparedPhoto photo;
  final PhotoCategory category;
  final String caption;
  final String farmerObservations;
  final DateTime? capturedDate;
  final ConfirmedFarmReference? farm;
  final bool synthetic;

  Map<String, Object?> toJson() => {
    'schema_version': 'evidence.v1',
    'data_kind': synthetic ? 'synthetic' : 'farmer_supplied',
    'source': switch (photo.origin) {
      PhotoOrigin.camera => 'camera',
      PhotoOrigin.gallery => 'gallery',
      PhotoOrigin.browserFile => 'browser_file',
    },
    'category': category.name,
    'caption': caption,
    'farmer_observations': farmerObservations,
    'captured_at': null,
    // A chosen date is never converted into an invented midnight timestamp.
    'captured_date': capturedDate == null ? null : dateLabel(capturedDate!),
    'capture_time_source': capturedDate == null ? 'unknown' : 'farmer_reported',
    'farm': farm?.toJson(),
    'position': photo.gps?.toJson(),
  };
}

String dateLabel(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

class StoredPhoto {
  StoredPhoto.fromJson(Map<String, dynamic> json)
    : data = Map.unmodifiable(json) {
    if (json['schema_version'] != 'evidence.v1' ||
        json['metadata_stripped'] != true ||
        json['mime_type'] != 'image/png' ||
        json['evidence_kind'] != 'farmer_supplied_photo' ||
        json['id'] is! String) {
      throw const FormatException('Unsupported photo evidence contract');
    }
  }
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get caption => data['caption'] as String;
  String get category => data['category'] as String;
  bool get synthetic => data['data_kind'] == 'synthetic';
  String get observations => data['farmer_observations'] as String;
  String? get farmId => (data['farm'] as Map?)?['farm_id'] as String?;
  String get captureLabel =>
      data['captured_date'] as String? ??
      data['captured_at'] as String? ??
      'Capture date unknown';
}

class PhotoEvidenceException implements Exception {
  const PhotoEvidenceException(this.message);
  final String message;
  @override
  String toString() => message;
}
