import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/home_profile.dart';
import 'platform_farms.dart';
import 'platform_transport.dart';

String journalId() {
  final random = Random.secure();
  final b = List<int>.generate(16, (_) => random.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Explicit device snapshots. No tokens, image pixels, write queues or replay.
class FarmJournalCache {
  String key(ConfirmedFarm farm, String origin) =>
      'earthsync.journal.v1.${Uri.encodeComponent(origin)}.${farm.id}.${farmRevision(farm)}';
  Future<Map<String, dynamic>?> read(String key) async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<void> save(String key, Map<String, dynamic> value) async {
    final raw = jsonEncode(value);
    if (raw.length > 4000000) {
      throw StateError('Offline snapshot is too large.');
    }
    if (!await (await SharedPreferences.getInstance()).setString(key, raw)) {
      throw StateError('Device storage unavailable.');
    }
  }

  Future<void> remove(String key) async {
    if (!await (await SharedPreferences.getInstance()).remove(key)) {
      throw StateError('Could not remove device snapshot.');
    }
  }
}

class FarmJournalClient {
  const FarmJournalClient(this.platform);
  final PlatformFarmClient platform;
  String path(String farm) => '${PlatformFarmClient.prefix}/farms/$farm';
  Future<List<Map<String, dynamic>>> list(String id) async =>
      List<Map<String, dynamic>>.from(
        await platform.transport.request(
              'GET',
              '${path(id)}/journal',
              expectedStatus: 200,
            )
            as List,
      );
  Future<List<Map<String, dynamic>>> photos(String id) async =>
      List<Map<String, dynamic>>.from(
        await platform.transport.request(
              'GET',
              '${path(id)}/photos',
              expectedStatus: 200,
            )
            as List,
      );
  Future<void> save(String id, Map<String, dynamic> value) async {
    await platform.transport.request(
      'POST',
      '${path(id)}/journal',
      expectedStatus: 201,
      body: value,
    );
  }

  Future<void> confirmHistory(String id, String entry) async {
    await platform.transport.request(
      'POST',
      '${path(id)}/journal/$entry/confirm-history',
      expectedStatus: 201,
    );
  }
}

class FarmJournalSnapshot {
  const FarmJournalSnapshot(this.data, {this.cached = false});
  final Map<String, dynamic> data;
  final bool cached;
  String get farmId => data['farm_id'] as String;
  List<Map<String, dynamic>> rows(String key) =>
      List<Map<String, dynamic>>.from(data[key] as List? ?? []);
  String get retrieved => data['retrieved_at'] as String;
}

Future<FarmJournalSnapshot?> loadFarmJournal(
  ConfirmedFarm farm,
  PlatformFarmClient? client,
  FarmJournalCache cache,
) async {
  final key = cache.key(
    farm,
    client?.transport.baseUri.origin ?? 'unconfigured',
  );
  try {
    if (client == null) return null;
    final linked = await client.link(farm);
    if (linked == null) return null;
    final journal = FarmJournalClient(client);
    final values = await Future.wait([
      journal.list(linked.id),
      client.context(linked.id),
      client.decisions(linked.id),
      journal.photos(linked.id),
      client.transport.request(
        'GET',
        '${journal.path(linked.id)}/timeline',
        expectedStatus: 200,
      ),
      client.transport.request(
        'GET',
        '${journal.path(linked.id)}/comparisons',
        expectedStatus: 200,
      ),
    ]);
    final context = values[1] as Map<String, dynamic>;
    return FarmJournalSnapshot({
      'farm_id': linked.id,
      'retrieved_at': DateTime.now().toUtc().toIso8601String(),
      'entries': values[0],
      'history': context['history'],
      'evidence': context['evidence'],
      'decisions': values[2],
      'photos': values[3],
      'timeline': values[4],
      'comparisons': values[5],
    });
  } on PlatformFailure catch (error) {
    // Never retain access after a missing farm, rejected origin or permission failure.
    if (error.code != 'NETWORK_UNAVAILABLE' &&
        !error.code.startsWith('HTTP_5')) {
      rethrow;
    }
    final saved = await cache.read(key);
    if (saved == null) rethrow;
    return FarmJournalSnapshot(saved, cached: true);
  }
}
