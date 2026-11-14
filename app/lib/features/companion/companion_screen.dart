import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/farm_journal.dart';
import '../../data/engine/v03_engine.dart';
import '../../design/components/product.dart';
import '../../state/home_provider.dart';
import '../../state/journal_provider.dart';
import '../../state/platform_provider.dart';
import '../field/assessment_screen.dart';
import '../field/evidence_panels.dart';
import 'companion_copy.dart';
import 'journal_form.dart';

class CompanionScreen extends ConsumerWidget {
  const CompanionScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String tr(String s) => CompanionCopy.text(context, s);
    final farm = ref.watch(homeProfileProvider).value?.farm;
    final state = ref.watch(journalProvider);
    final snapshot = state.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Season & records')),
        actions: [
          IconButton(
            tooltip: tr('Refresh'),
            onPressed: state.isLoading
                ? null
                : () => ref.invalidate(journalProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              PageHeader(
                title: farm?.name ?? tr('Farm records'),
                subtitle:
                    'Farmer reports, plans and source evidence stay distinct. Refresh is on demand; no background monitoring is running.',
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final route in const {
                    '/field': 'Map & environment',
                    '/farm-evidence': 'Reassess with selected evidence',
                    '/crops': 'Crop references',
                    '/farm-photos': 'Photos',
                    '/assistant': 'Assistant',
                  }.entries)
                    OutlinedButton(
                      onPressed: () => context.push(route.key),
                      child: Text(tr(route.value)),
                    ),
                ],
              ),
              if (state.isLoading) const LinearProgressIndicator(),
              if (state.hasError)
                EvidenceNotice(
                  title: tr('Not connected'),
                  message:
                      'Saved data could not be retrieved. No values have been substituted. A previously saved offline copy is used only after a network outage.',
                  action: TextButton(
                    onPressed: () => ref.invalidate(journalProvider),
                    child: Text(tr('Refresh')),
                  ),
                ),
              if (snapshot == null && !state.isLoading && !state.hasError)
                EvidenceNotice(
                  title: tr('Not connected'),
                  message:
                      'Save this confirmed farm to the private local service first. You can keep a draft on this device.',
                  action: TextButton(
                    onPressed: () => context.push('/farm-evidence'),
                    child: Text(tr('Connect this farm')),
                  ),
                ),
              if (snapshot != null) ...[
                EvidenceNotice(
                  title: snapshot.cached
                      ? tr('Cached copy · may be stale')
                      : tr('Last retrieved'),
                  message:
                      '${snapshot.retrieved}\n${snapshot.cached ? 'Read only · source times remain unchanged. Reconnect and refresh before reassessing or submitting records.' : 'Source acquisition and issue times remain attached to each source. Retrieval does not establish current conditions.'}',
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: snapshot.cached
                          ? null
                          : () async {
                              try {
                                final client = ref.read(
                                  platformFarmClientProvider,
                                )!;
                                final cache = ref.read(journalCacheProvider);
                                await cache.save(
                                  cache.key(
                                    farm!,
                                    client.transport.baseUri.origin,
                                  ),
                                  snapshot.data,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Offline copy saved on this device. No photo pixels or tokens included.',
                                      ),
                                    ),
                                  );
                                }
                              } catch (_) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Could not save offline copy.',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                      child: Text(tr('Keep for offline viewing')),
                    ),
                    TextButton(
                      onPressed: () async {
                        final cache = ref.read(journalCacheProvider);
                        final origin =
                            ref
                                .read(platformFarmClientProvider)
                                ?.transport
                                .baseUri
                                .origin ??
                            'unconfigured';
                        try {
                          await cache.remove(cache.key(farm!, origin));
                          if (context.mounted) ref.invalidate(journalProvider);
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Could not remove offline copy.'),
                              ),
                            );
                          }
                        }
                      },
                      child: Text(tr('Remove offline copy')),
                    ),
                  ],
                ),
                _SeasonSummary(snapshot: snapshot),
                SectionCard(
                  title: tr('Risk & warnings'),
                  icon: Icons.warning_amber_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('No official alerts loaded')),
                      const Text(
                        'A missing alert is not an all-clear. Inspect dated forecasts and their coverage in Map & environment. Historical climate cannot issue a current warning.',
                      ),
                      TextButton(
                        onPressed: () => context.push('/field'),
                        child: Text(tr('Map & environment')),
                      ),
                    ],
                  ),
                ),
                _Calendar(snapshot: snapshot),
                _Timeline(snapshot: snapshot),
              ],
              JournalForm(
                key: ValueKey('${farm?.id}:${farm?.confirmedAt}'),
                snapshot: snapshot,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeasonSummary extends StatelessWidget {
  const _SeasonSummary({required this.snapshot});
  final FarmJournalSnapshot snapshot;
  @override
  Widget build(BuildContext context) {
    final seasons =
        snapshot.rows('entries').where((e) => e['kind'] == 'season').toList()
          ..sort(
            (a, b) => (b['occurred_on'] as String).compareTo(
              a['occurred_on'] as String,
            ),
          );
    final current = seasons.where((e) => e['harvest_on'] == null).firstOrNull;
    final stages =
        snapshot
            .rows('entries')
            .where(
              (e) =>
                  e['kind'] == 'stage' &&
                  e['crop_name'] == current?['crop_name'],
            )
            .toList()
          ..sort(
            (a, b) => (b['occurred_on'] as String).compareTo(
              a['occurred_on'] as String,
            ),
          );
    final stage =
        stages.firstOrNull?['stage'] ?? current?['stage'] ?? 'unknown';
    final planted = DateTime.tryParse(current?['occurred_on'] as String? ?? '');
    final today = DateUtils.dateOnly(DateTime.now());
    return SectionCard(
      title: CompanionCopy.text(context, 'Actual crop season'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            current?['crop_name'] as String? ??
                CompanionCopy.text(context, 'Unknown'),
          ),
          Text('Reported planting: ${current?['occurred_on'] ?? 'Unknown'}'),
          if (planted != null)
            Text(
              '${today.difference(planted).inDays} calendar days since reported planting. This does not identify biological stage.',
            ),
          Text('Farmer-reported stage: $stage'),
          const Text(
            'Expected harvest belongs to a saved plan. An actual harvest must be reported separately; no crop-specific duration is assumed.',
          ),
        ],
      ),
    );
  }
}

class _Timeline extends ConsumerWidget {
  const _Timeline({required this.snapshot});
  final FarmJournalSnapshot snapshot;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String tr(String s) => CompanionCopy.text(context, s);
    final items = <({String date, Widget child})>[];
    for (final e in snapshot.rows('entries')) {
      items.add((
        date: e['occurred_on'] as String,
        child: ExpansionTile(
          title: Text(
            '${tr(journalKinds[e['kind']] ?? 'Farm records')} · ${e['occurred_on']}',
          ),
          subtitle: Text(
            '${e['crop_name'] ?? ''} · ${tr('Farmer reported')}${e['kind'] == 'plan' ? ' · Planned, not completed' : ''}',
          ),
          childrenPadding: const EdgeInsets.all(12),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(e['notes'] as String? ?? ''),
            Text(
              'Harvest: ${e['harvest_on'] ?? 'Unknown'} · stage: ${e['stage']}',
            ),
            Text(
              'Irrigation: ${e['irrigation']} · drainage: ${e['drainage']} · water: ${e['water_access']}',
            ),
            Text(
              'Priorities: ${(e['priorities'] as List).join(', ')}\nResources: ${e['resources'] ?? 'Unknown'}',
            ),
            if (e['soil_test'] case final Map test)
              Text(
                'Farmer-supplied soil test: ${test['property']} ${test['value']} ${test['unit']} · ${test['top_cm']}–${test['bottom_cm']} cm · ${test['source']}',
              ),
            Text(
              'Recorded ${e['recorded_at']} · ${(e['photo_ids'] as List).length} farm-owned photo links · ${(e['evidence_ids'] as List).length} source links',
            ),
            if ((e['photo_ids'] as List).isNotEmpty)
              TextButton(
                onPressed: () => context.push('/farm-photos'),
                child: Text(tr('Photos')),
              ),
            if (e['kind'] == 'season' &&
                e['harvest_on'] != null &&
                e['crop_id'] != null)
              OutlinedButton(
                onPressed: snapshot.cached
                    ? null
                    : () async {
                        if (!await confirmAction(
                              context,
                              title:
                                  'Copy completed season to assessment history?',
                              message:
                                  'Only the reported crop identity and actual planting/harvest dates enter Rust history. Your report remains farmer-reported, never independently verified.',
                              confirmLabel: 'Confirm history',
                            ) ||
                            !context.mounted) {
                          return;
                        }
                        try {
                          await FarmJournalClient(
                            ref.read(platformFarmClientProvider)!,
                          ).confirmHistory(snapshot.farmId, e['id'] as String);
                          ref.invalidate(platformContextProvider);
                          ref.invalidate(platformAssistantProvider);
                          ref.invalidate(journalProvider);
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('History not confirmed: $error'),
                              ),
                            );
                          }
                        }
                      },
                child: const Text('Confirm completed season for Rust history'),
              ),
            EvidenceDetails(title: tr('Evidence & sources'), data: e),
          ],
        ),
      ));
    }
    for (final e in snapshot.rows('evidence')) {
      final time = e['temporal'] as Map;
      items.add((
        date:
            '${time['end'] ?? time['observed_at'] ?? time['acquired_at'] ?? time['retrieved_at']}',
        child: ExpansionTile(
          title: Text('${e['dataset']} · ${e['data_type']}'),
          subtitle: Text(
            '${time['start'] ?? time['acquired_at'] ?? 'Time unknown'} – ${time['end'] ?? ''}\nRetrieved ${time['retrieved_at']}',
          ),
          children: [
            Text('${e['spatial']['support']}'),
            Text((e['limitations'] as List).join('\n')),
            EvidenceDetails(title: tr('Evidence & sources'), data: e),
          ],
        ),
      ));
    }
    for (final d in snapshot.rows('decisions')) {
      final assessment = d['assessment'] as Map;
      items.add((
        date:
            '${assessment['created_at'] ?? assessment['request']?['end'] ?? ''}',
        child: ExpansionTile(
          title: Text(tr('Saved assessments')),
          subtitle: Text('${d['id']}'),
          children: [
            V03ResultPanel(
              result: V03Result.decode(
                Map<String, dynamic>.from(assessment['result'] as Map),
              ),
            ),
            EvidenceDetails(title: tr('Evidence & sources'), data: d),
          ],
        ),
      ));
    }
    items.sort((a, b) => b.date.compareTo(a.date));
    return SectionCard(
      title: tr('Timeline'),
      icon: Icons.timeline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (items.isEmpty) Text(tr('No records yet')),
          for (final i in items) i.child,
        ],
      ),
    );
  }
}

class _Calendar extends StatelessWidget {
  const _Calendar({required this.snapshot});
  final FarmJournalSnapshot snapshot;
  @override
  Widget build(BuildContext context) {
    final data = snapshot.data['timeline'] as Map?;
    return SectionCard(
      title: 'Seasonal coverage & reported conflicts',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final p in data?['periods'] as List? ?? [])
            Text(
              '${p['start']} → ${p['end'] ?? 'Harvest not reported'} · ${p['label']} · farmer reported',
            ),
          for (final gap in data?['unknown_gaps'] as List? ?? [])
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: Text('${gap['start']} → ${gap['end']} · Unknown'),
              subtitle: Text(gap['explanation'] as String),
            ),
          for (final overlap in data?['overlaps'] as List? ?? [])
            ListTile(
              leading: const Icon(Icons.warning_amber),
              title: Text(
                '${overlap['start']} → ${overlap['end']} · Reported overlap',
              ),
              subtitle: Text(overlap['explanation'] as String),
            ),
          const Text(
            'Only explicitly reported fallow or bare-field periods carry those labels. Missing dates never prove bare soil.',
          ),
          ExpansionTile(
            title: const Text('How to read environmental evidence'),
            children: const [
              ListTile(
                title: Text('Rainfall & reference ET0'),
                subtitle: Text(
                  'Rainfall is water depth for the stated period. Reference ET0 is atmospheric demand over reference grass, calculated by Rust FAO-56. It is not crop water demand or an irrigation prescription. Missing days stay unknown.',
                ),
              ),
              ListTile(
                title: Text('Soil & moisture'),
                subtitle: Text(
                  'Modeled soil properties describe a grid and depth. They are not a laboratory sample from your field. Soil moisture uses the provider’s stated depth and units.',
                ),
              ),
              ListTile(
                title: Text('NDVI & risk'),
                subtitle: Text(
                  'NDVI measures vegetation greenness for an acquisition and sensor pixel. Clouds and missing data limit it. Color does not diagnose disease, yield or nutrient deficiency. Forecasts and official alerts require valid times and coverage.',
                ),
              ),
              ListTile(
                title: Text('Sources stay distinct'),
                subtitle: Text(
                  'Satellite observations, regional models, farmer reports and laboratory results are different evidence. Each retains its source, date, units, resolution and quality.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
