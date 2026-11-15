import 'dart:convert';
import 'package:earthsync/data/farm_journal.dart';
import 'package:earthsync/data/platform_farms.dart';
import 'package:earthsync/data/platform_transport.dart';
import 'package:earthsync/state/home_provider.dart';
import 'package:earthsync/state/local_farm_provider.dart';
import 'package:earthsync/state/journal_provider.dart';
import 'package:earthsync/state/platform_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'authorization denial hides retained server evidence and keeps device records',
    (tester) async {
      final store = await memoryFarmStore(tester);
      await tester.runAsync(() async {
        await store.put('field-1', 'journal', {
          'id': 'local-note',
          'kind': 'observation',
        });
        var denied = false;
        final client = PlatformFarmClient(
          PlatformTransport(
            MockClient((_) async => http.Response('{}', 503)),
            baseUri: Uri.parse('http://127.0.0.1:8021'),
          ),
        );
        final container = ProviderContainer(
          overrides: [
            profileStoreProvider.overrideWithValue(
              MemoryProfileStore(confirmedProfile()),
            ),
            localFarmStoreProvider.overrideWith((ref) async => store),
            platformFarmClientProvider.overrideWithValue(client),
            remoteJournalProvider.overrideWith((ref) async {
              if (denied) throw const PlatformFailure('HTTP_403');
              return FarmJournalSnapshot({
                'farm_id': 'remote-farm',
                'retrieved_at': '2024-01-01T00:00:00Z',
                'evidence': [
                  {'id': 'private-server-evidence'},
                ],
              });
            }),
          ],
        );
        addTearDown(container.dispose);
        await container.read(homeProfileProvider.future);
        final subscription = container.listen(journalProvider, (_, _) {});
        addTearDown(subscription.close);
        await container.read(remoteJournalProvider.future);
        expect(
          (await container.read(journalProvider.future))!.rows('evidence'),
          isNotEmpty,
        );
        denied = true;
        container.invalidate(remoteJournalProvider);
        await container.pump();
        final after = (await container.read(journalProvider.future))!;
        expect(after.rows('evidence'), isEmpty);
        expect(after.rows('entries').single['id'], 'local-note');
        expect(after.cached, true);
      });
    },
  );
  test(
    'offline snapshot is explicit and isolated by origin and farm revision',
    () async {
      final farm = confirmedProfile().farm!;
      final cache = FarmJournalCache();
      final key = cache.key(farm, 'http://127.0.0.1:8021');
      final saved = {
        'farm_id': 'db-farm',
        'retrieved_at': '2024-01-01T00:00:00Z',
        'entries': [],
      };
      expect(await cache.read(key), null);
      await cache.save(key, saved);
      expect(await cache.read(key), saved);
      expect(await cache.read(cache.key(farm, 'http://127.0.0.1:8022')), null);
      final unavailable = PlatformFarmClient(
        PlatformTransport(
          MockClient((r) async => throw http.ClientException('offline')),
          baseUri: Uri.parse('http://127.0.0.1:8021'),
        ),
      );
      final snapshot = await loadFarmJournal(farm, unavailable, cache);
      expect(snapshot!.cached, true);
      expect(snapshot.retrieved, '2024-01-01T00:00:00Z');
      expect(snapshot.farmId, 'db-farm');
      final denied = PlatformFarmClient(
        PlatformTransport(
          MockClient(
            (r) async => http.Response('{"error":{"code":"NOT_FOUND"}}', 404),
          ),
          baseUri: Uri.parse('http://127.0.0.1:8021'),
        ),
      );
      expect(await loadFarmJournal(farm, denied, cache), null);
      await cache.remove(key);
      expect(await cache.read(key), null);
    },
  );
  test(
    'manual write uses same UUID and never replays after a network failure',
    () async {
      var calls = 0;
      final id = journalId();
      expect(
        id,
        matches(
          RegExp(
            r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
          ),
        ),
      );
      final platform = PlatformFarmClient(
        PlatformTransport(
          MockClient((r) async {
            calls++;
            expect(r.method, 'POST');
            expect(jsonDecode(r.body)['id'], id);
            throw http.ClientException('offline');
          }),
          baseUri: Uri.parse('http://127.0.0.1:8021'),
        ),
      );
      await expectLater(
        FarmJournalClient(platform).save('farm', {'id': id}),
        throwsA(isA<PlatformFailure>()),
      );
      expect(calls, 1);
    },
  );
  test('new farm and switching preserve existing farms and reports', () async {
    final store = MemoryProfileStore(confirmedProfile());
    final container = ProviderContainer(
      overrides: [profileStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    final initial = await container.read(homeProfileProvider.future);
    await container
        .read(homeProfileProvider.notifier)
        .confirmFarm(initial.farm!.point, 'Second farm', createNew: true);
    expect(store.profile.farms, hasLength(2));
    await container.read(homeProfileProvider.notifier).selectFarm('field-1');
    expect(store.profile.farm!.name, 'North field');
    expect(store.profile.farms, hasLength(2));
  });
}
