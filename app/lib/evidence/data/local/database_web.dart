import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'database.dart' show createFarmSchema;

Future<Database> openFarmDatabase() => databaseFactoryFfiWeb.openDatabase(
  'earthsync-farmer-v2.sqlite3',
  options: OpenDatabaseOptions(version: 1, onCreate: createFarmSchema),
);
