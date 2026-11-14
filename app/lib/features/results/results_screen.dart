import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../app/strings.dart';
import '../../data/models/field_analysis.dart';
import '../../design/components/badges.dart';
import '../../design/components/feedback.dart';
import '../../design/components/scenario.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';
import '../map/gibs_layer.dart';
import 'climate_tab.dart';
import 'climate_provenance.dart';

/// Shows the analysis state machine: loading -> results tabs | error.
class ResultsScreen extends ConsumerStatefulWidget {
  const ResultsScreen({super.key});

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(analysisProvider);
    final notifier = ref.read(analysisProvider.notifier);

    return switch (state) {
      AnalysisIdle() ||
      AnalysisRunning() => const Scaffold(body: FsStateView.loading()),
      AnalysisFailed(:final error, :final lastGood) => Scaffold(
        appBar: AppBar(),
        body: FsStateView.error(
          title: S.errorTitle,
          message: error.message,
          actions: [
            if (error.retryable)
              FilledButton(
                onPressed: () =>
                    notifier.run(ref.read(farmerDraftProvider).toInput()),
                child: const Text(S.retry),
              ),
            if (lastGood != null)
              OutlinedButton(
                onPressed: notifier.showLastGood,
                child: const Text(S.showLast),
              ),
            OutlinedButton(
              onPressed: notifier.runDemo,
              child: const Text(S.useDemo),
            ),
          ],
        ),
      ),
      AnalysisReady(:final analysis, :final fromCache) => Scaffold(
        appBar: AppBar(
          title: Text(analysis.location.name ?? S.appName),
          actions: [
            IconButton(
              tooltip: S.sources,
              icon: const Icon(Icons.menu_book),
              onPressed: () => context.push('/sources'),
            ),
          ],
        ),
        body: SafeArea(
          child: switch (_tab) {
            0 => _OverviewTab(
              analysis: analysis,
              fromCache: fromCache,
              onCompare: () => setState(() => _tab = 3),
            ),
            1 => _MapTab(analysis: analysis),
            2 => ClimateTab(analysis: analysis),
            _ => _RotationsTab(analysis: analysis),
          },
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: S.tabOverview,
            ),
            NavigationDestination(
              icon: Icon(Icons.satellite_alt),
              label: S.tabMap,
            ),
            NavigationDestination(
              icon: Icon(Icons.water_drop_outlined),
              selectedIcon: Icon(Icons.water_drop),
              label: S.tabClimate,
            ),
            NavigationDestination(
              icon: Icon(Icons.autorenew),
              label: S.tabRotations,
            ),
          ],
        ),
      ),
    };
  }
}

List<Widget> _qualityBanners(FieldAnalysis a, bool fromCache) => [
  if (a.dataQuality.isDemo)
    const FsDataQualityBanner(message: S.demoData, kind: FsBannerKind.warning),
  if (fromCache && a.dataQuality.fetchedAt != null)
    FsDataQualityBanner(
      message: S.savedData(DateFormat.yMMMd().format(a.dataQuality.fetchedAt!)),
    ),
  if (a.dataGaps.isNotEmpty) const FsDataQualityBanner(message: S.partialData),
];

/// "rain_mm.july" -> "Rainfall, July"; "drainage" -> "Drainage".
String dataGapLabel(String field) {
  const names = {
    'rain_mm': 'Rainfall',
    'temp_mean_c': 'Temperature',
    'drainage': 'Drainage',
    'irrigation': 'Water for the field',
    'current_crop': 'Current crop',
    'planting_month': 'Planting month',
    'soil': 'Soil',
  };
  String nice(String p) {
    final s = names[p] ?? p.replaceAll('_', ' ');
    return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  }

  return field.split('.').map(nice).join(', ');
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.analysis,
    required this.fromCache,
    required this.onCompare,
  });
  final FieldAnalysis analysis;
  final bool fromCache;
  final VoidCallback onCompare;

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    return ListView(
      padding: const EdgeInsets.all(FsSpace.gutter),
      children: [
        for (final b in _qualityBanners(a, fromCache))
          Padding(
            padding: const EdgeInsets.only(bottom: FsSpace.sm),
            child: b,
          ),
        ClimateProvenance(analysis: a),
        const FsSectionTitle(S.atAGlance),
        if (a.scenarios.isEmpty)
          const Text(
            'Climate-only result. Crop suitability and rotations are unknown; no crop constraints supplied.',
          ),
        FsScenarioSummaryList(scenarios: a.scenarios),
        const SizedBox(height: FsSpace.sm),
        OutlinedButton.icon(
          onPressed: onCompare,
          icon: const Icon(Icons.compare_arrows),
          label: const Text(S.compareOptions),
        ),
        const FsSectionTitle(S.alerts),
        if (a.alerts.isEmpty) const Text(S.noAlerts),
        for (final al in a.alerts)
          Padding(
            padding: const EdgeInsets.only(bottom: FsSpace.sm),
            child: FsAlertCard(al),
          ),
        if (a.dataGaps.isNotEmpty) ...[
          const FsSectionTitle(S.dataGaps),
          FsBulletList(
            [
              for (final g in a.dataGaps)
                '${dataGapLabel(g.field)}: ${g.reason}',
            ],
            icon: Icons.help_outline,
            color: FsColors.unknown,
          ),
        ],
        if (a.notices.isNotEmpty) ...[
          const FsSectionTitle(S.notices),
          FsBulletList(
            a.notices,
            icon: Icons.info_outline,
            color: FsColors.sky,
          ),
        ],
        if (a.assumptions.isNotEmpty) ...[
          const FsSectionTitle(S.assumptions),
          FsBulletList(a.assumptions),
        ],
      ],
    );
  }
}

/// Compact list of all options: name, status, main risk. Tap opens detail.
class FsScenarioSummaryList extends StatelessWidget {
  const FsScenarioSummaryList({super.key, required this.scenarios});
  final List<RotationScenario> scenarios;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    var alt = 0;
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < scenarios.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            Builder(
              builder: (context) {
                final s = scenarios[i];
                final label = s.isBaseline
                    ? S.yourPractice
                    : '${S.option} ${++alt}';
                final risk = s.risks.firstOrNull;
                return InkWell(
                  onTap: () => context.push('/scenario/${s.id}'),
                  child: Padding(
                    padding: const EdgeInsets.all(FsSpace.md),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(label, style: t.bodySmall),
                              const SizedBox(height: 2),
                              Text(s.title, style: t.titleMedium),
                              const SizedBox(height: FsSpace.sm),
                              Wrap(
                                spacing: FsSpace.sm,
                                runSpacing: FsSpace.sm,
                                children: [
                                  FsFeasibilityBadge(s.eligibility),
                                  if (risk != null)
                                    FsRiskBadge(
                                      hazard: risk.hazard,
                                      level: risk.level,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          color: FsColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _MapTab extends StatefulWidget {
  const _MapTab({required this.analysis});
  final FieldAnalysis analysis;

  @override
  State<_MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<_MapTab> {
  bool _nasa = true;
  final _map = MapController();
  static const _cfg = GibsLayerConfig.provisional;
  static const _zoom = 8.0;

  @override
  Widget build(BuildContext context) {
    final loc = widget.analysis.location;
    final p = LatLng(loc.latitude, loc.longitude);
    final t = Theme.of(context).textTheme;
    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: p,
            initialZoom: _zoom,
            maxZoom: 12,
          ),
          children: [
            // Street map always underneath, so a missing satellite tile
            // shows a map instead of a grey hole.
            ...baseMapLayers(),
            if (_nasa) gibsTileLayer(_cfg),
            MarkerLayer(
              markers: [
                Marker(
                  point: p,
                  width: 48,
                  height: 48,
                  alignment: Alignment.topCenter,
                  child: const Icon(
                    Icons.location_on,
                    size: 48,
                    color: FsColors.riskHigh,
                  ),
                ),
              ],
            ),
          ],
        ),
        Positioned(
          top: FsSpace.md,
          left: FsSpace.md,
          right: FsSpace.md,
          child: Row(
            children: [
              _MapButton(
                icon: Icons.my_location,
                tooltip: S.recenter,
                onTap: () => _map.move(p, _zoom),
              ),
              const Spacer(),
              Material(
                elevation: 2,
                borderRadius: const BorderRadius.all(FsRadius.md),
                color: FsColors.surface,
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: FsSpace.md,
                    right: FsSpace.xs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('NASA image'),
                      Switch(
                        value: _nasa,
                        onChanged: (v) => setState(() => _nasa = v),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Compact source line (always visible); full legend on tap.
        Positioned(
          left: FsSpace.md,
          right: FsSpace.md,
          bottom: FsSpace.md,
          child: Material(
            elevation: 2,
            color: FsColors.surface,
            borderRadius: const BorderRadius.all(FsRadius.md),
            child: InkWell(
              borderRadius: const BorderRadius.all(FsRadius.md),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (_) => SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      FsSpace.gutter,
                      0,
                      FsSpace.gutter,
                      FsSpace.lg,
                    ),
                    child: FsMapLegend(config: _cfg, showingNasa: _nasa),
                  ),
                ),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: FsSpace.minTouch),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FsSpace.md,
                    vertical: FsSpace.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _nasa ? Icons.image_outlined : Icons.map_outlined,
                        color: FsColors.evidenceImagery,
                      ),
                      const SizedBox(width: FsSpace.sm),
                      Expanded(
                        child: Text(
                          _nasa
                              ? 'NASA ${_cfg.title} · ${_cfg.dateString}'
                              : 'Street map © OpenStreetMap',
                          style: t.bodyMedium,
                        ),
                      ),
                      const Icon(
                        Icons.info_outline,
                        color: FsColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 2,
    color: FsColors.surface,
    shape: const CircleBorder(),
    child: IconButton(
      tooltip: tooltip,
      icon: Icon(icon, color: FsColors.primary),
      iconSize: 24,
      constraints: const BoxConstraints.tightFor(
        width: FsSpace.minTouch,
        height: FsSpace.minTouch,
      ),
      onPressed: onTap,
    ),
  );
}

class _RotationsTab extends StatelessWidget {
  const _RotationsTab({required this.analysis});
  final FieldAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final list = analysis.scenarios;
    var alt = 0;
    return ListView(
      padding: const EdgeInsets.all(FsSpace.gutter),
      children: [
        ClimateProvenance(analysis: analysis),
        if (list.isEmpty)
          const Text(
            'Rotations are unknown. No source-backed crop constraints or scenarios supplied.',
          ),
        if (analysis.dataQuality.isDemo)
          const Padding(
            padding: EdgeInsets.only(bottom: FsSpace.md),
            child: FsDataQualityBanner(
              message: S.demoData,
              kind: FsBannerKind.warning,
            ),
          ),
        for (final s in list)
          Padding(
            padding: const EdgeInsets.only(bottom: FsSpace.md),
            child: FsScenarioCard(
              scenario: s,
              optionNumber: s.isBaseline ? 0 : ++alt,
              onOpenDetail: () => context.push('/scenario/${s.id}'),
            ),
          ),
      ],
    );
  }
}
