import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Photos the farmer takes, kept in the app's own folder on the phone.
/// Photos are evidence for people to look at — the app never measures
/// anything from the pixels.
class PhotoStore {
  PhotoStore(this.dir);
  final Directory dir;

  /// Null where there is no app folder (web, tests).
  static Future<PhotoStore?> open() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/photos');
      await dir.create(recursive: true);
      return PhotoStore(dir);
    } catch (_) {
      return null;
    }
  }

  File file(String name) => File('${dir.path}/$name');

  /// Copies a picked photo in as `<id>.jpg` and returns its file name.
  Future<String> save(XFile picked, String id) async {
    final name = '$id.jpg';
    await picked.saveTo(file(name).path);
    return name;
  }

  /// Removes every photo the app saved on this phone.
  Future<void> deleteAll() async {
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
  }

  Future<void> delete(String? name) async {
    if (name == null) return;
    final f = file(name);
    if (await f.exists()) await f.delete();
  }
}

/// Camera or gallery. Resized for slow rural data; full metadata not
/// requested.
Future<XFile?> pickPhoto(ImageSource source) => ImagePicker().pickImage(
  source: source,
  maxWidth: 1600,
  maxHeight: 1600,
  imageQuality: 80,
  requestFullMetadata: false,
);
