import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/strings.dart';
import '../../data/models/farmer_input.dart';
import '../../design/components/badges.dart';
import '../../design/components/feedback.dart';
import '../../design/components/scenario.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';

class ScenarioDetailScreen extends ConsumerWidget {
  const ScenarioDetailScreen({super.key, required this.scenarioId});
  final String scenarioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(analysisProvider);
    if (state is! AnalysisReady) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(
          child: Text(
            'Run a field analysis to view this option. Results are not retained after refresh.',
          ),
        ),
      );
    }
    final a = state.analysis;
    final s = a.scenarios.where((x) => x.id == scenarioId).firstOrNull;
    if (s == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const FsStateView.error(
          title: S.errorTitle,
          message: 'Option not found.',
        ),
      );
    }
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.isBaseline ? S.yourPractice : S.option),
        actions: [
          IconButton(
            tooltip: S.sources,
            icon: const Icon(Icons.menu_book),
            onPressed: () => context.push('/sources'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(FsSpace.gutter),
        children: [
          Text(s.title, style: t.headlineMedium),
          const SizedBox(height: FsSpace.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: FsFeasibilityBadge(s.eligibility),
          ),
          const SizedBox(height: FsSpace.lg),
          FsRotationTimeline(s.steps),
          const SizedBox(height: FsSpace.sm),
          for (final step in s.steps)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.grass),
              title: Text(
                _stepTitle(step.cropId, step.startMonth, step.endMonth),
              ),
              trailing: FsFeasibilityBadge(step.feasibility),
            ),
          if (s.likelyBenefits.isNotEmpty) ...[
            const FsSectionTitle(S.benefits),
            FsBulletList(
              s.likelyBenefits,
              icon: Icons.check,
              color: FsColors.supported,
            ),
          ],
          if (s.risks.isNotEmpty) ...[
            const FsSectionTitle(S.risks),
            for (final r in s.risks)
              Padding(
                padding: const EdgeInsets.only(bottom: FsSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FsRiskBadge(hazard: r.hazard, level: r.level),
                    const SizedBox(height: FsSpace.xs),
                    Text(r.note, style: t.bodyLarge),
                  ],
                ),
              ),
          ],
          if (s.limitations.isNotEmpty) ...[
            const FsSectionTitle(S.limitations),
            FsBulletList(
              s.limitations,
              icon: Icons.info_outline,
              color: FsColors.unknown,
            ),
          ],
          const FsSectionTitle(S.evidence),
          Wrap(
            spacing: FsSpace.sm,
            runSpacing: FsSpace.sm,
            children: [
              for (final id in s.evidenceIds)
                if (a.reference(id) case final r?) FsEvidenceChip(r),
            ],
          ),
        ],
      ),
    );
  }
}

String _stepTitle(String? crop, int? start, int? end) {
  final name = Crops.label(crop);
  if (start == null || end == null) return '$name — planting window unknown';
  return '$name — ${monthNames[start - 1]} to ${monthNames[end - 1]}';
}
