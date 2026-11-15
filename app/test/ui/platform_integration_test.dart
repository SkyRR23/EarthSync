import 'package:flutter/material.dart';
import 'package:earthsync/features/field/platform_farm_screen.dart';
import 'package:earthsync/state/integration_provider.dart';
import 'dart:async';
import 'dart:convert';
import 'package:earthsync/data/environment/platform_climate.dart';
import 'package:earthsync/data/models/home_profile.dart';
import 'package:earthsync/data/platform_transport.dart';
import 'package:earthsync/data/platform_farms.dart';
import 'package:earthsync/state/home_provider.dart';
import 'package:earthsync/state/platform_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../home_test_support.dart';

Map<String, dynamic> job(String status) => {
  'id': 'job-1',
  'status': status,
  'retryable': false,
  'error': null,
  'result': null,
};
void main() {
  final base = Uri.parse('http://127.0.0.1:8021');
  test(
    '201 farm link, 200 recovery and 204 deletion have endpoint-specific contracts',
    () async {
      final local = confirmedProfile().farm!;
      var requests = 0;
      final transport = PlatformTransport(
        MockClient((r) async {
          requests++;
          if (r.method == 'DELETE') return http.Response('', 204);
          if (r.method == 'POST') {
            final body = jsonDecode(r.body);
            expect(body['local_profile_id'], local.id);
            expect(body['farm']['confirmed_point'], local.point.toJson());
            expect(body.containsKey('owner'), false);
            return http.Response('{}', 201);
          }
          expect(r.url.queryParameters['revision'], farmRevision(local));
          return http.Response(
            jsonEncode({
              'local_profile_id': local.id,
              'revision': farmRevision(local),
              'farm': {
                'id': 'database-uuid',
                'confirmed_point': local.point.toJson(),
                'production_system': 'rainfed',
              },
            }),
            200,
          );
        }),
        baseUri: base,
      );
      final client = PlatformFarmClient(transport);
      await client.confirm(local, 'rainfed');
      expect((await client.link(local))!.id, 'database-uuid');
      expect(
        await transport.request(
          'DELETE',
          '/api/platform/v1/farms/id/photos/id',
          expectedStatus: 204,
        ),
        null,
      );
      expect(requests, 3);
    },
  );
  test(
    'mutating transport error does not retry and preserves retryability',
    () async {
      var calls = 0;
      final transport = PlatformTransport(
        MockClient((r) async {
          calls++;
          return http.Response(
            '{"error":{"code":"JOB_CAPACITY","retryable":true}}',
            429,
          );
        }),
        baseUri: base,
      );
      await expectLater(
        transport.request(
          'POST',
          '/api/platform/v1/climate/jobs',
          expectedStatus: 202,
          body: {},
        ),
        throwsA(
          isA<PlatformFailure>().having((e) => e.retryable, 'retryable', true),
        ),
      );
      expect(calls, 1);
    },
  );
  test(
    'polling is bounded, preserves running status, and stops when selection changes',
    () async {
      var calls = 0;
      final client = PlatformClimateClient(
        MockClient((r) async {
          calls++;
          return http.Response(jsonEncode(job('running')), 200);
        }),
        baseUri: base,
      );
      final pending = ClimateJob.fromJson(job('queued'));
      final result = await client.poll(
        pending,
        maxAttempts: 2,
        interval: Duration.zero,
      );
      expect(result.status, ClimateJobStatus.running);
      expect(calls, 2);
      await client.poll(
        result,
        maxAttempts: 10,
        interval: Duration.zero,
        isCurrent: () => false,
      );
      expect(calls, 2);
    },
  );
  test(
    'farm association survives queued/running/succeeded lifecycle and cancellation',
    () async {
      var gets = 0;
      final client = PlatformClimateClient(
        MockClient((r) async {
          if (r.method == 'POST') {
            expect(jsonDecode(r.body)['farm_id'], 'database-uuid');
            return http.Response(jsonEncode(job('queued')), 202);
          }
          if (r.method == 'DELETE') {
            return http.Response(jsonEncode(job('cancelled')), 200);
          }
          return http.Response(
            jsonEncode(job(++gets == 1 ? 'running' : 'succeeded')),
            200,
          );
        }),
        baseUri: base,
      );
      final queued = await client.submit(
        point: GeoPoint(42, -93),
        start: DateTime(2024, 2, 1),
        end: DateTime(2024, 2, 29),
        farmId: 'database-uuid',
      );
      expect(queued.pending, true);
      expect(
        (await client.poll(queued, interval: Duration.zero)).status,
        ClimateJobStatus.succeeded,
      );
      expect(
        (await client.cancel(queued.id)).status,
        ClimateJobStatus.cancelled,
      );
    },
  );
  test(
    'a farm edit discards a delayed response for the old confirmation',
    () async {
      final old = Completer<http.Response>();
      final store = MemoryProfileStore(confirmedProfile());
      final client = PlatformFarmClient(
        PlatformTransport(MockClient((r) => old.future), baseUri: base),
      );
      final container = ProviderContainer(
        overrides: [
          profileStoreProvider.overrideWithValue(store),
          platformFarmClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);
      await container.read(homeProfileProvider.future);
      final sub = container.listen(platformFarmProvider, (_, _) {});
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);
      await container
          .read(homeProfileProvider.notifier)
          .confirmFarm(GeoPoint(1, 2), 'New confirmation');
      old.complete(
        http.Response('{"error":{"code":"NOT_FOUND","retryable":false}}', 404),
      );
      final farm = await container.read(platformFarmProvider.future);
      expect(farm, null);
      expect(
        container.read(homeProfileProvider).value!.farm!.point,
        GeoPoint(1, 2),
      );
    },
  );
  testWidgets('phone farm linking is explicit and displays restored records', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final local = confirmedProfile().farm!;
    var linked = false;
    var writes = 0;
    final client = PlatformFarmClient(
      PlatformTransport(
        MockClient((r) async {
          if (r.method == 'POST') {
            linked = true;
            writes++;
            return http.Response('{}', 201);
          }
          if (r.url.path.contains('/farm-links/')) {
            return linked
                ? http.Response(
                    jsonEncode({
                      'local_profile_id': local.id,
                      'revision': farmRevision(local),
                      'farm': {
                        'id': 'saved-farm',
                        'confirmed_point': local.point.toJson(),
                        'production_system': 'rainfed',
                      },
                    }),
                    200,
                  )
                : http.Response(
                    '{"error":{"code":"NOT_FOUND","retryable":false}}',
                    404,
                  );
          }
          if (r.url.path.endsWith('/context')) {
            return http.Response('{"evidence":[],"history":[]}', 200);
          }
          return http.Response('[]', 200);
        }),
        baseUri: base,
      ),
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          profileStoreProvider.overrideWithValue(
            MemoryProfileStore(confirmedProfile()),
          ),
          platformFarmClientProvider.overrideWithValue(client),
          catalogProvider.overrideWith(
            (ref) async => {
              'reference': {'profiles': []},
            },
          ),
        ],
        child: const MaterialApp(home: PlatformFarmScreen()),
      ),
    );
    await t.pumpAndSettle();
    expect(writes, 0);
    await t.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await t.tap(find.byType(DropdownButtonFormField<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('rainfed').last);
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Confirm local farm persistence'));
    await t.tap(find.text('Confirm local farm persistence'));
    await t.pumpAndSettle();
    expect(writes, 1);
    expect(find.textContaining('Database farm: saved-farm'), findsOneWidget);
    expect(
      find.textContaining('No saved evidence for this farm revision.'),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });
}
