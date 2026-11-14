import '../../state/platform_provider.dart';
import '../../app/ui_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/environment/platform_climate.dart';
import '../../data/models/home_profile.dart';
import '../../design/components/product.dart';
import '../../state/home_provider.dart';
import '../../state/integration_provider.dart';

class DailyClimateScreen extends ConsumerStatefulWidget {
  const DailyClimateScreen({super.key, this.farmMode = false});
  final bool farmMode;
  @override
  ConsumerState<DailyClimateScreen> createState() => _DailyClimateScreenState();
}

class _DailyClimateScreenState extends ConsumerState<DailyClimateScreen> {
  DateTimeRange? _range;
  ClimateJob? _job;
  String? _error, _selection;
  bool _busy = false;
  int _generation = 0;
  @override
  void dispose() {
    ++_generation;
    super.dispose();
  }

  Future<void> _run(Future<ClimateJob> Function() action) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final submitted = await action();
      if (mounted && generation == _generation) {
        setState(() => _job = submitted);
      }
      final client = PlatformClimateClient(
        ref.read(integrationHttpProvider),
        baseUri: Uri.parse(platformUrl),
      );
      final job = await client.poll(
        submitted,
        isCurrent: () => mounted && generation == _generation,
        onUpdate: (job) => setState(() => _job = job),
      );
      if (mounted && generation == _generation) {
        setState(() => _job = job);
        if (job.status == ClimateJobStatus.succeeded) {
          ref.invalidate(platformContextProvider);
          ref.invalidate(platformAssistantProvider);
        }
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(homeProfileProvider).value;
    final area = profile?.userLocation;
    final linkedState = widget.farmMode
        ? ref.watch(platformFarmProvider)
        : null;
    final linkedFarm = linkedState?.isLoading == false
        ? linkedState?.value
        : null;
    final point = widget.farmMode
        ? linkedFarm?.point
        : area is ApproximateArea
        ? area.point
        : profile?.farm?.point;
    // Selection changes clear all old job results and in-flight callbacks.
    final selection = point == null
        ? null
        : '${widget.farmMode}:${linkedFarm?.id}:${profile?.farm?.confirmedAt}:${point.latitude}|${point.longitude}';
    if (_selection != selection) {
      _selection = selection;
      ++_generation;
      _job = null;
      _error = null;
      _busy = false;
    }
    PlatformClimateClient? client;
    String? configurationError;
    if (platformUrl.isNotEmpty) {
      try {
        client = PlatformClimateClient(
          ref.watch(integrationHttpProvider),
          baseUri: Uri.parse(platformUrl),
        );
      } catch (_) {
        configurationError = UiLabels.platformRequiresLoopback;
      }
    }
    final configuredClient = client;
    return Scaffold(
      appBar: AppBar(title: const Text(UiLabels.dailyClimateLocalPlatform)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const PageHeader(
                title: UiLabels.dailyHistoricalClimate,
                subtitle: UiLabels.nasaPOWERMERRA2LSTExplicitLocalOnly7I,
              ),
              Text(
                '${widget.farmMode ? 'Linked farm query' : 'Regional query'}: ${point?.label ?? 'Choose an area or link a confirmed farm first'}',
              ),
              Text(
                widget.farmMode
                    ? 'Daily regional model records will be associated with this explicitly linked farm. No device coordinates or photos are sent.'
                    : UiLabels.thisQueryIsRegionalAndDoesNotUpload,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.date_range),
                label: Text(
                  _range == null
                      ? UiLabels.chooseHistoricalDates
                      : '${_range!.start.toIso8601String().substring(0, 10)} – ${_range!.end.toIso8601String().substring(0, 10)}',
                ),
                onPressed: _busy
                    ? null
                    : () async {
                        final range = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(1981),
                          lastDate: DateTime.now().subtract(
                            const Duration(days: 1),
                          ),
                          initialDateRange: _range,
                        );
                        if (mounted && range != null) {
                          setState(() {
                            _range = range;
                            _job = null;
                            ++_generation;
                          });
                        }
                      },
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed:
                    _busy ||
                        configuredClient == null ||
                        point == null ||
                        _range == null ||
                        _job?.pending == true
                    ? null
                    : () => _run(
                        () => configuredClient.submit(
                          point: point,
                          start: _range!.start,
                          end: _range!.end,
                          farmId: linkedFarm?.id,
                        ),
                      ),
                child: const Text(UiLabels.requestDailyClimate),
              ),
              if (configurationError != null) Text(configurationError),
              if (configuredClient == null)
                const Text(
                  UiLabels.theLocalPlatformIsNotConfiguredExistingMonthly,
                ),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                EvidenceNotice(
                  title: UiLabels.dailyClimateUnavailable,
                  message:
                      '$_error · No example or synthetic data were substituted. Check the local service and its allowed browser origin, then retry.',
                ),
              if (_job case final job?) ...[
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Job: ${job.status.name}',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (job.error != null)
                        Text('${job.error} · retryable: ${job.retryable}'),
                      if (job.pending)
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _run(
                                      () => configuredClient!.refresh(job.id),
                                    ),
                              child: const Text(UiLabels.refreshJobStatus),
                            ),
                            TextButton(
                              onPressed: () =>
                                  _run(() => configuredClient!.cancel(job.id)),
                              child: const Text(UiLabels.cancelJob),
                            ),
                          ],
                        ),
                      const Text(
                        UiLabels
                            .completedProcessingCanStillContainMissingOrRejected,
                      ),
                    ],
                  ),
                ),
                for (final gap in job.gaps)
                  EvidenceNotice(
                    title: 'Source gap: ${gap['parameter']}',
                    message: '${gap['code']}',
                  ),
                for (final evidence in job.records)
                  SectionCard(
                    title:
                        '${evidence.provider} · ${evidence.dataset} · ${evidence.raw['source_metadata']['parameter']}',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Version: ${evidence.raw['dataset_version']} · review: ${evidence.raw['review']}',
                        ),
                        Text(
                          'Spatial support: ${evidence.raw['spatial']['support']}',
                        ),
                        Text(
                          'Period: ${evidence.raw['temporal']['start']} – ${evidence.raw['temporal']['end']} · retrieved: ${evidence.raw['temporal']['retrieved_at']}',
                        ),
                        Text(
                          'Review scope: ${evidence.raw['source_metadata']['review_scope']}',
                        ),
                        SelectableText(evidence.sourceUrl),
                        for (final limit in evidence.raw['limitations'] as List)
                          Text('$limit'),
                        ExpansionTile(
                          title: const Text(
                            UiLabels.dailyValuesSourceUnitsQuality,
                          ),
                          children: [
                            for (final m in evidence.measurements)
                              ListTile(
                                title: Text('${m.date} · ${m.variable}'),
                                subtitle: Text(
                                  '${m.value ?? 'Unknown'} ${m.unit} · ${m.quality}\nOriginal: ${m.originalValue ?? 'Unknown'} ${m.originalUnit}${m.missingReason == null ? '' : '\n${m.missingReason}'}',
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
              const SourceNote(),
            ],
          ),
        ),
      ),
    );
  }
}
