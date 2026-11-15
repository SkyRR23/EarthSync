# Added runtime assets

Existing font/image licenses remain in their original asset locations. No new production farm imagery or downloaded global agricultural dataset is included.

`app/web/sqflite_sw.js` and `app/web/sqlite3.wasm` were produced by the official `dart run sqflite_common_ffi_web:setup` command for `sqflite_common_ffi_web` 1.2.2. Setup downloaded the SQLite WASM runtime from the sqlite3.dart release named `sqlite3-3.6.0`. These are application execution assets, not farmer databases or soil/crop datasets.

- [sqflite_common_ffi_web source/license](https://github.com/tekartik/sqflite/tree/master/packages_web/sqflite_common_ffi_web): MIT.
- [sqlite3.dart](https://github.com/simolus3/sqlite3.dart): MIT Dart bindings; underlying [SQLite copyright statement](https://sqlite.org/copyright.html).
- Generated worker contains Dart runtime code; [Dart SDK license](https://github.com/dart-lang/sdk/blob/main/LICENSE) is BSD 3-Clause.
- [flutter_local_notifications](https://github.com/MaikuB/flutter_local_notifications): BSD 3-Clause. No push credential is part of its local scheduling integration.

Flutter's generated application notices retain dependency license text. Keep these source pointers and the generated runtime asset notices when updating the lockfile or worker.
