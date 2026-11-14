import 'dart:ui' as ui;

import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'photo_evidence_models.dart';

const maxPhotoBytes = 10 * 1024 * 1024;
const maxPhotoPixels = 16000000;

abstract interface class FieldPhotoPicker {
  bool get supportsCamera;
  Future<PreparedPhoto?> pick(PhotoOrigin origin, {required bool readGps});
}

class PlatformFieldPhotoPicker implements FieldPhotoPicker {
  PlatformFieldPhotoPicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  @override
  bool get supportsCamera =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<PreparedPhoto?> pick(
    PhotoOrigin origin, {
    required bool readGps,
  }) async {
    if (origin == PhotoOrigin.camera && !supportsCamera) {
      throw const PhotoEvidenceException(
        'Camera selection is unavailable on this platform.',
      );
    }
    // Only request platform metadata after explicit GPS consent. It remains
    // local; the upload always consists of newly encoded pixels and approved GPS.
    final selected = await _picker.pickImage(
      source: origin == PhotoOrigin.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      requestFullMetadata: readGps,
    );
    if (selected == null) return null;
    if (await selected.length() > maxPhotoBytes) {
      throw const PhotoEvidenceException(
        'Choose a JPEG or PNG no larger than 10 MiB.',
      );
    }
    return preparePhoto(await selected.readAsBytes(), origin, readGps: readGps);
  }
}

typedef GpsReader = Future<PhotoGps?> Function(Uint8List bytes);

Future<PhotoGps?> readConsentedGps(Uint8List bytes) async {
  try {
    final tags = await readExifFromBytes(bytes, details: false);
    double? coordinate(String name, String ref, double limit) {
      final values = tags['GPS $name']?.values.toList();
      final reference = tags['GPS $ref']?.printable;
      if (values == null || values.length != 3) return null;
      final parts = values
          .map((value) => value is Ratio ? value.toDouble() : double.nan)
          .toList();
      if (parts.any((part) => !part.isFinite || part < 0) ||
          parts[1] >= 60 ||
          parts[2] >= 60) {
        return null;
      }
      final latitude = name == 'GPSLatitude';
      if (!(latitude ? ['N', 'S'] : ['E', 'W']).contains(reference)) {
        return null;
      }
      var result = parts[0] + parts[1] / 60 + parts[2] / 3600;
      if (result > limit) return null;
      if (reference == 'S' || reference == 'W') result = -result;
      return result;
    }

    final latitude = coordinate('GPSLatitude', 'GPSLatitudeRef', 90);
    final longitude = coordinate('GPSLongitude', 'GPSLongitudeRef', 180);
    return latitude == null || longitude == null
        ? null
        : PhotoGps(latitude, longitude);
  } catch (_) {
    return null; // Missing/malformed EXIF is unknown, never (0,0).
  }
}

/// Decode only bounded JPEG/PNG input and encode fresh pixels for upload.
/// Original bytes/filename/EXIF are not retained in PreparedPhoto.
Future<PreparedPhoto> preparePhoto(
  Uint8List bytes,
  PhotoOrigin origin, {
  required bool readGps,
  GpsReader gpsReader = readConsentedGps,
}) async {
  final png =
      bytes.length >= 8 &&
      listEquals(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
  final jpeg =
      bytes.length >= 3 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      bytes[2] == 255;
  if (bytes.isEmpty || bytes.length > maxPhotoBytes || (!png && !jpeg)) {
    throw const PhotoEvidenceException(
      'Choose a valid JPEG or PNG no larger than 10 MiB.',
    );
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      if (descriptor.width < 1 ||
          descriptor.height < 1 ||
          descriptor.width > 8192 ||
          descriptor.height > 8192 ||
          descriptor.width * descriptor.height > maxPhotoPixels) {
        throw const PhotoEvidenceException(
          'Image exceeds 8192 pixels per side or 16 megapixels.',
        );
      }
      final codec = await descriptor.instantiateCodec();
      try {
        if (codec.frameCount != 1) {
          throw const PhotoEvidenceException(
            'Animated images are not supported.',
          );
        }
        final frame = await codec.getNextFrame();
        try {
          final data = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (data == null || data.lengthInBytes > maxPhotoBytes) {
            throw const PhotoEvidenceException(
              'Resize the image; sanitized upload exceeds 10 MiB.',
            );
          }
          return PreparedPhoto(
            png: data.buffer.asUint8List(
              data.offsetInBytes,
              data.lengthInBytes,
            ),
            origin: origin,
            width: frame.image.width,
            height: frame.image.height,
            gps: readGps ? await gpsReader(bytes) : null,
            gpsRequested: readGps,
          );
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}
