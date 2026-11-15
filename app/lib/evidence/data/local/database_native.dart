import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'database.dart' show createFarmSchema;

Future<Database> openFarmDatabase() async {
  sqfliteFfiInit();
  final root = await getApplicationSupportDirectory();
  return databaseFactoryFfi.openDatabase(
    path.join(root.path, 'earthsync-farmer-v2.sqlite3'),
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: createFarmSchema,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys=ON');
      },
    ),
  );
}
