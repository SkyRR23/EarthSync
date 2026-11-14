import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/farm_journal.dart';
import 'home_provider.dart';
import 'platform_provider.dart';

final journalCacheProvider = Provider((ref) => FarmJournalCache());
final journalProvider = FutureProvider.autoDispose<FarmJournalSnapshot?>((
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
});
