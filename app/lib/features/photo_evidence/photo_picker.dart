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

/// Read bounded dimensions before allocating decoded pixels. Flutter Web's
/// encoded ImageDescriptor.width/height getters throw UnsupportedError.
/// This is only a preflight; the codec and server still validate the image.
(int, int) encodedPhotoDimensions(Uint8List bytes, {required bool png}) {
  final data = ByteData.sublistView(bytes);
  if (png) {
    if (bytes.length < 33 ||
        data.getUint32(8) != 13 ||
        !listEquals(bytes.sublist(12, 16), [73, 72, 68, 82])) {
      throw const PhotoEvidenceException('PNG has no valid image-size header.');
    }
    return (data.getUint32(16), data.getUint32(20));
  }
  var offset = 2;
  (int, int)? dimensions;
  const starts = {
    0xc0,
    0xc1,
    0xc2,
    0xc3,
    0xc5,
    0xc6,
    0xc7,
    0xc9,
    0xca,
    0xcb,
    0xcd,
    0xce,
    0xcf,
  };
  while (offset < bytes.length) {
    if (bytes[offset++] != 255) break;
    while (offset < bytes.length && bytes[offset] == 255) {
      offset++;
    }
    if (offset >= bytes.length) break;
    final marker = bytes[offset++];
    if (marker == 0xda || marker == 0xd9) break;
    if (marker == 1 || marker >= 0xd0 && marker <= 0xd7) continue;
    if (offset + 2 > bytes.length) break;
    final length = data.getUint16(offset);
    if (length < 2 || offset + length > bytes.length) break;
    if (starts.contains(marker)) {
      if (length < 8 || dimensions != null) {
        throw const PhotoEvidenceException('Ambiguous JPEG image-size header.');
      }
      dimensions = (data.getUint16(offset + 5), data.getUint16(offset + 3));
    }
    offset += length;
  }
  if (dimensions == null) {
    throw const PhotoEvidenceException('JPEG has no valid image-size header.');
  }
  return dimensions;
}

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
  final (width, height) = encodedPhotoDimensions(bytes, png: png);
  if (width < 1 ||
      height < 1 ||
      width > 8192 ||
      height > 8192 ||
      width * height > maxPhotoPixels) {
    throw const PhotoEvidenceException(
      'Image exceeds 8192 pixels per side or 16 megapixels.',
    );
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
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
