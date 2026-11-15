import 'dart:async';
import '../../data/farm_journal.dart';
import '../../data/models/home_profile.dart';
import '../../data/platform_farms.dart';
import '../../data/platform_transport.dart';

const historicalPrefix = '/api/platform/v1';
String historicalDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Each selection owns its request cancellation and job. Never replay writes.
class HistoricalClient {
  HistoricalClient(this.platform);
  final PlatformFarmClient platform;
  int _generation = 0;
  String? _job;
  Completer<void>? _abort;
  bool _disposed = false;
  PlatformTransport get transport => platform.transport;
  void cancel() {
    _generation++;
    if (_abort?.isCompleted == false) _abort!.complete();
    final id = _job;
    _job = null;
    if (id != null) {
      unawaited(
        transport
            .request(
              'DELETE',
              '$historicalPrefix/jobs/$id',
              expectedStatus: 200,
            )
            .catchError((Object _) => null),
      );
    }
  }

  void dispose() {
    cancel();
    _disposed = true;
  }

  Future<Map<String, dynamic>?> run(
    String kind,
    Map<String, dynamic> body,
  ) async {
    cancel();
    final generation = _generation;
    final abort = Completer<void>();
    _abort = abort;
    bool active() => !_disposed && generation == _generation;
    try {
      final job = Map<String, dynamic>.from(
        await transport.request(
              'POST',
              '$historicalPrefix/$kind/jobs',
              expectedStatus: 202,
              body: body,
              abortTrigger: abort.future,
            )
            as Map,
      );
      if (!active()) {
        unawaited(
          transport
              .request(
                'DELETE',
                '$historicalPrefix/jobs/${job['id']}',
                expectedStatus: 200,
              )
              .catchError((Object _) => null),
        );
        return null;
      }
      _job = job['id'] as String;
      for (var attempt = 0; attempt < 180 && active(); attempt++) {
        final value = Map<String, dynamic>.from(
          await transport.request(
                'GET',
                '$historicalPrefix/jobs/$_job',
                expectedStatus: 200,
                abortTrigger: abort.future,
              )
              as Map,
        );
        if (!active()) return null;
        if (value['status'] == 'succeeded') {
          _job = null;
          return Map<String, dynamic>.from(value['result'] as Map);
        }
        if (['failed', 'cancelled'].contains(value['status'])) {
          _job = null;
          throw PlatformFailure(value['error'] as String? ?? 'CANCELLED');
        }
        await Future.any([
          Future<void>.delayed(const Duration(seconds: 1)),
          abort.future,
        ]);
      }
      if (!active()) return null;
      cancel();
      throw const PlatformFailure('TIMEOUT', retryable: true);
    } catch (_) {
      if (!active()) return null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> replay(String farmId, String id) async =>
      Map<String, dynamic>.from(
        await transport.request(
              'GET',
              '$historicalPrefix/farms/$farmId/historical/$id',
              expectedStatus: 200,
            )
            as Map,
      );
}

class HistoricalSnapshot {
  const HistoricalSnapshot(this.data, {this.cached = false});
  final Map<String, dynamic> data;
  final bool cached;
  String get farmId => data['farm_id'] as String;
  List<Map<String, dynamic>> rows(String name) =>
      List<Map<String, dynamic>>.from(data[name] as List? ?? []);
}

String historicalCacheKey(ConfirmedFarm farm, PlatformFarmClient client) =>
    '${FarmJournalCache().key(farm, client.transport.baseUri.origin)}.historical.v1';

Future<HistoricalSnapshot?> loadHistorical(
  ConfirmedFarm farm,
  PlatformFarmClient client,
  FarmJournalCache cache,
) async {
  final key = historicalCacheKey(farm, client);
  try {
    final linked = await client.link(farm);
    if (linked == null) return null;
    final base = '$historicalPrefix/farms/${linked.id}';
    final values = await Future.wait([
      for (final path in [
        'historical',
        'simulations',
        'timeline',
        'intelligence',
        'comparisons',
      ])
        client.transport.request('GET', '$base/$path', expectedStatus: 200),
    ]);
    return HistoricalSnapshot({
      'farm_id': linked.id,
      'revision': farmRevision(farm),
      'retrieved_at': DateTime.now().toUtc().toIso8601String(),
      'windows': values[0],
      'simulations': values[1],
      'timeline': values[2],
      'intelligence': values[3],
      'comparisons': values[4],
    });
  } on PlatformFailure catch (e) {
    if (e.code != 'NETWORK_UNAVAILABLE' && !e.code.startsWith('HTTP_5')) {
      rethrow;
    }
    final saved = await cache.read(key);
    if (saved == null) rethrow;
    if (saved['revision'] != farmRevision(farm)) {
      throw const FormatException('Revision mismatch');
    }
    return HistoricalSnapshot(saved, cached: true);
  }
}
