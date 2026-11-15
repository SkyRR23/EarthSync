import 'dart:convert';
import 'dart:typed_data';
import 'package:sqflite_common/sqlite_api.dart';
import '../farm_journal.dart' show journalId;
import 'farm_task.dart';

class LocalFarmStore {
  LocalFarmStore(this.db);
  final Database db;
  Map<String, dynamic> _decode(Map row) =>
      Map<String, dynamic>.from(jsonDecode(row['body'] as String) as Map);
  Future<List<Map<String, dynamic>>> records(String scope, String kind) async =>
      [
        for (final row in await db.query(
          'records',
          where: 'scope=? AND kind=?',
          whereArgs: [scope, kind],
          orderBy: 'updated_at DESC',
        ))
          _decode(row),
      ];
  Future<Map<String, dynamic>?> setting(String id) async {
    final rows = await db.query('settings', where: 'id=?', whereArgs: [id]);
    return rows.isEmpty ? null : _decode(rows.single);
  }

  Future<void> saveSetting(String id, Map<String, dynamic> value) async {
    final raw = jsonEncode(value);
    if (utf8.encode(raw).length > 8 * 1024 * 1024) {
      throw StateError('Saved evidence exceeds the local cache limit.');
    }
    await db.insert('settings', {
      'id': id,
      'body': raw,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _put(
    DatabaseExecutor tx,
    String scope,
    String kind,
    Map<String, dynamic> value, {
    bool queue = false,
  }) async {
    final raw = jsonEncode(value);
    if (utf8.encode(raw).length > 4 * 1024 * 1024) {
      throw StateError('Record exceeds the local size limit.');
    }
    await tx.insert('records', {
      'scope': scope,
      'kind': kind,
      'id': value['id'],
      'body': raw,
      'updated_at':
          value['updated_at'] ?? DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    if (queue) {
      final versions = await tx.query(
        'sync_versions',
        where: 'scope=? AND kind=? AND entity_id=?',
        whereArgs: [scope, kind, value['id']],
      );
      await tx.delete(
        'outbox',
        where: 'scope=? AND kind=? AND entity_id=? AND status=?',
        whereArgs: [scope, kind, value['id'], 'pending'],
      );
      await tx.insert('outbox', {
        'operation_id': journalId(),
        'scope': scope,
        'kind': kind,
        'entity_id': value['id'],
        'body': raw,
        'base_version': versions.isEmpty ? 0 : versions.single['version'],
        'status': 'pending',
      });
    }
  }

  Future<void> put(
    String scope,
    String kind,
    Map<String, dynamic> value, {
    bool queue = false,
  }) => db.transaction((tx) => _put(tx, scope, kind, value, queue: queue));
  Future<void> remove(String scope, String kind, String id) async {
    await db.delete(
      'records',
      where: 'scope=? AND kind=? AND id=?',
      whereArgs: [scope, kind, id],
    );
  }

  Future<List<FarmTask>> tasks(String farm) async => [
    for (final row in await records(farm, 'task'))
      if (row['deleted'] != true) FarmTask(row),
  ];
  Future<void> saveTask(FarmTask task) =>
      put(task.farmId, 'task', task.data, queue: true);
  Future<void> setTaskStatus(FarmTask task, String status, DateTime now) =>
      db.transaction((tx) async {
        final rows = await tx.query(
          'records',
          where: 'scope=? AND kind=? AND id=?',
          whereArgs: [task.farmId, 'task', task.id],
        );
        if (rows.isEmpty) throw StateError('This task was removed.');
        final current = FarmTask(_decode(rows.single));
        if (current.status == status) return;
        final changed = current.withChanges({
          'status': status,
          'completed_at': status == 'completed'
              ? now.toUtc().toIso8601String()
              : null,
          'updated_at': now.toUtc().toIso8601String(),
        });
        await _put(tx, task.farmId, 'task', changed.data, queue: true);
        if (status == 'completed' || status == 'skipped') {
          final next = current.next(now);
          if (next != null) {
            final existing = await tx.query(
              'records',
              where: 'scope=? AND kind=? AND id=?',
              whereArgs: [task.farmId, 'task', next.id],
            );
            if (existing.isEmpty) {
              await _put(tx, task.farmId, 'task', next.data, queue: true);
            }
          }
        }
      });
  Future<void> deleteTask(FarmTask task) => saveTask(
    task.withChanges({
      'deleted': true,
      'status': 'canceled',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }),
  );

  Future<int> reminderId(String occurrence) => db.transaction((tx) async {
    final rows = await tx.query(
      'reminder_ids',
      where: 'occurrence=?',
      whereArgs: [occurrence],
    );
    if (rows.isNotEmpty) return rows.single['id'] as int;
    final max = await tx.rawQuery(
      'SELECT COALESCE(MAX(id),0)+1 AS next FROM reminder_ids',
    );
    final id = max.single['next'] as int;
    await tx.insert('reminder_ids', {'occurrence': occurrence, 'id': id});
    return id;
  });
  Future<void> notify(
    String scope,
    String id,
    String category,
    String title,
    String body,
    DateTime at, {
    String? taskId,
  }) async {
    await db.insert('records', {
      'scope': scope,
      'kind': 'notification',
      'id': id,
      'body': jsonEncode({
        'id': id,
        'category': category,
        'title': title,
        'body': body,
        'farm_id': scope,
        'task_id': taskId,
        'timestamp': at.toUtc().toIso8601String(),
        'read': false,
      }),
      'updated_at': at.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> savePhoto(
    String scope,
    String id,
    String mime,
    Uint8List bytes,
    Map<String, dynamic> metadata,
  ) async {
    if (!['image/jpeg', 'image/png', 'image/webp'].contains(mime) ||
        bytes.length > 8 * 1024 * 1024) {
      throw StateError('Use a JPEG, PNG or WebP photo smaller than 8 MB.');
    }
    await db.insert('photos', {
      'scope': scope,
      'id': id,
      'mime': mime,
      'bytes': bytes,
      'body': jsonEncode(metadata),
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<List<Map<String, Object?>>> photos(String scope) => db.query(
    'photos',
    columns: ['id', 'body'],
    where: 'scope=?',
    whereArgs: [scope],
  );
  Future<Uint8List?> photo(String scope, String id) async {
    final rows = await db.query(
      'photos',
      columns: ['bytes'],
      where: 'scope=? AND id=?',
      whereArgs: [scope, id],
    );
    return rows.isEmpty ? null : rows.single['bytes'] as Uint8List;
  }

  Future<Map<String, dynamic>> exportFarm(String scope) async => {
    'schema_version': 'earthsync.local-export.v1',
    'exported_at': DateTime.now().toUtc().toIso8601String(),
    'records': [
      for (final row in await db.query(
        'records',
        where: 'scope=?',
        whereArgs: [scope],
      ))
        {'kind': row['kind'], 'data': _decode(row)},
    ],
    'photos': [
      for (final row in await db.query(
        'photos',
        where: 'scope=?',
        whereArgs: [scope],
      ))
        {
          'id': row['id'],
          'mime': row['mime'],
          'metadata': _decode(row),
          'base64': base64Encode(row['bytes'] as Uint8List),
        },
    ],
    'cached_farm_evidence': [
      for (final row in await db.query('settings'))
        if ((row['id'] as String).startsWith('earthsync.journal.v1.') &&
            (row['id'] as String).contains('.$scope.'))
          _decode(row),
    ],
  };
  Future<void> deleteFarm(String scope) => db.transaction((tx) async {
    for (final table in ['records', 'photos', 'outbox', 'sync_versions']) {
      await tx.delete(table, where: 'scope=?', whereArgs: [scope]);
    }
    for (final row in await tx.query('settings', columns: ['id'])) {
      final key = row['id'] as String;
      if (key.startsWith('earthsync.journal.v1.') && key.contains('.$scope.')) {
        await tx.delete('settings', where: 'id=?', whereArgs: [key]);
      }
    }
  });
}
