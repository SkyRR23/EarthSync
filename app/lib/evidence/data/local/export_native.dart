import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

Future<String> saveFarmExport(String contents) async {
  final directory =
      await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  final file = File(
    path.join(
      directory.path,
      'EarthSync-farm-export-${DateTime.now().microsecondsSinceEpoch}.json',
    ),
  );
  await file.writeAsString(contents, flush: true);
  return file.path;
}
