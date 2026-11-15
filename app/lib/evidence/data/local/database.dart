import 'package:sqflite_common/sqlite_api.dart';
import 'database_native.dart'
    if (dart.library.js_interop) 'database_web.dart'
    as platform;

Future<Database> openFarmDatabase() => platform.openFarmDatabase();

Future<void> createFarmSchema(Database db, int version) async {
  await db.execute(
    'CREATE TABLE records (scope TEXT NOT NULL, kind TEXT NOT NULL, id TEXT NOT NULL, body TEXT NOT NULL, updated_at TEXT NOT NULL, PRIMARY KEY(scope, kind, id))',
  );
  await db.execute(
    'CREATE TABLE photos (scope TEXT NOT NULL, id TEXT NOT NULL, mime TEXT NOT NULL, bytes BLOB NOT NULL, body TEXT NOT NULL, PRIMARY KEY(scope, id))',
  );
  await db.execute(
    'CREATE TABLE settings (id TEXT PRIMARY KEY, body TEXT NOT NULL)',
  );
  await db.execute(
    'CREATE TABLE reminder_ids (occurrence TEXT PRIMARY KEY, id INTEGER UNIQUE NOT NULL)',
  );
  await db.execute(
    'CREATE TABLE outbox (operation_id TEXT PRIMARY KEY, scope TEXT NOT NULL, kind TEXT NOT NULL, entity_id TEXT NOT NULL, body TEXT NOT NULL, base_version INTEGER NOT NULL, status TEXT NOT NULL DEFAULT \'pending\')',
  );
  await db.execute(
    'CREATE TABLE sync_versions (scope TEXT NOT NULL, kind TEXT NOT NULL, entity_id TEXT NOT NULL, version INTEGER NOT NULL, PRIMARY KEY(scope, kind, entity_id))',
  );
}
