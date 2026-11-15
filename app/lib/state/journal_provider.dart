import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/farm_journal.dart';
import 'home_provider.dart';
import 'platform_provider.dart';
import 'local_farm_provider.dart';
import '../data/platform_transport.dart';

final journalCacheProvider = Provider((ref) => FarmJournalCache());
final remoteJournalProvider = FutureProvider.autoDispose<FarmJournalSnapshot?>((
  ref,
) async {
  final farm = ref.watch(homeProfileProvider).value?.farm;
  return farm == null
      ? null
      : loadFarmJournal(
          farm,
          ref.watch(platformFarmClientProvider),
          ref.watch(journalCacheProvider),
        );
}, retry: (_, _) => null);

final journalProvider = FutureProvider.autoDispose<FarmJournalSnapshot?>((
  ref,
) async {
  final farm = ref.watch(homeProfileProvider).value?.farm;
  if (farm == null) return null;
  ref.watch(localRevisionProvider);
  final remote = ref.watch(remoteJournalProvider);
  final client = ref.watch(platformFarmClientProvider);
  final cache = ref.watch(journalCacheProvider);
  final key = cache.key(
    farm,
    client?.transport.baseUri.origin ?? 'unconfigured',
  );
  final store = await ref.watch(localFarmStoreProvider.future);
  final entries = await store.records(farm.id, 'journal');
  Map<String, dynamic>? saved;
  final remoteError = remote.error;
  final denied =
      remoteError is PlatformFailure &&
      remoteError.code != 'NETWORK_UNAVAILABLE' &&
      !remoteError.code.startsWith('HTTP_5');
  if (!denied) saved = await store.setting(key);
  if (!denied &&
      !remote.hasError &&
      !remote.isLoading &&
      remote.value != null &&
      !remote.value!.cached) {
    saved = remote.value!.data;
    await store.saveSetting(key, saved);
  }
  final source = denied
      ? <String, dynamic>{}
      : remote.value?.data ?? saved ?? <String, dynamic>{};
  final merged = <String, Map<String, dynamic>>{
    for (final entry in source['entries'] as List? ?? [])
      '${entry['id']}': Map<String, dynamic>.from(entry as Map),
    for (final entry in entries) '${entry['id']}': entry,
  };
  return FarmJournalSnapshot(
    {
      'farm_id': source['farm_id'] ?? farm.id,
      'retrieved_at': source['retrieved_at'] ?? 'No server evidence retrieved',
      'entries': [
        for (final entry in merged.values)
          {
            'priorities': <String>[],
            'photo_ids': <String>[],
            'evidence_ids': <String>[],
            'irrigation': 'unknown',
            'drainage': 'unknown',
            'water_access': 'unknown',
            'local_only': entries.any((local) => local['id'] == entry['id']),
            'recorded_at':
                entry['created_at'] ?? entry['updated_at'] ?? 'Unknown',
            ...entry,
          },
      ],
      'history': source['history'] ?? [],
      'evidence': source['evidence'] ?? [],
      'decisions': source['decisions'] ?? [],
      'photos': source['photos'] ?? [],
      'timeline': source['timeline'] ?? {},
      'comparisons': source['comparisons'] ?? [],
      'intelligence': source['intelligence'] ?? [],
      'observations': source['observations'] ?? [],
    },
    cached:
        remote.hasError ||
        remote.isLoading ||
        remote.value == null ||
        remote.value!.cached,
  );
});
