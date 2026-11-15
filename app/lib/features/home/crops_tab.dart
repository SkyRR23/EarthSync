import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

import '../../app/strings.dart';
import '../../data/models/field_analysis.dart';
import '../../design/components/buttons.dart';
import '../../design/components/feedback.dart';
import '../../design/components/page.dart';
import '../../design/components/scenario.dart';
import '../../design/components/sheet.dart';
import '../../design/tokens.dart';
import 'field_tab.dart' show showAboutResults;
import 'freshness_banner.dart';

/// "Check my crops": the crop plans the engine checked, best fit first.
class CropsTab extends StatelessWidget {
  const CropsTab({
    super.key,
    required this.analysis,
    this.fromCache = false,
    this.showBack = true,
  });

  final FieldAnalysis analysis;
  final bool fromCache;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    final items = sortedByFit(a.scenarios);
    return FsPage(
      title: S.nextSeason,
      showBack: showBack,
      subtitle: items.isEmpty ? null : S.bestFirst,
      children: [
        if (a.dataQuality.isDemo) ...[
          const SizedBox(height: FsSpace.md),
          FsBanner(
            message: S.demoData,
            tone: FsTone.caution,
            icon: CupertinoIcons.exclamationmark_circle_fill,
            onTap: () => showAboutResults(context, a),
          ),
        ],
        const FreshnessBanner(),
        Padding(
          padding: const EdgeInsets.all(FsSpace.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FsButton(
                'Compare crop rotations & save my decision',
                icon: CupertinoIcons.arrow_2_squarepath,
                onPressed: () => context.push('/rotation-plans'),
              ),
              const SizedBox(height: FsSpace.sm),
              FsButton(
                'Explore the historical timeline',
                kind: FsButtonKind.tinted,
                icon: CupertinoIcons.calendar,
                onPressed: () => context.push('/historical'),
              ),
            ],
          ),
        ),
        const SizedBox(height: FsSpace.lg),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FsSpace.gutter,
              FsSpace.xl,
              FsSpace.gutter,
              0,
            ),
            child: Column(
              children: [
                const Text('🌱❔', style: TextStyle(fontSize: 48)),
                const SizedBox(height: FsSpace.md),
                Text(
                  S.cropsUnknownTitle,
                  textAlign: TextAlign.center,
                  style: context.type.title2,
                ),
                const SizedBox(height: FsSpace.sm),
                Text(
                  S.cropsUnknownBody,
                  textAlign: TextAlign.center,
                  style: context.type.body.copyWith(
                    color: context.fs.secondaryLabel,
                  ),
                ),
              ],
            ),
          ),
        for (final (i, (s, label, _)) in items.indexed)
          FsCropCard(
            scenario: s,
            highlight: i == 0 && s.eligibility == Feasibility.supported,
            onTap: () => showPlanSheet(context, s, label, a),
          ),
        if (items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FsSpace.gutter,
              FsSpace.xs,
              FsSpace.gutter,
              0,
            ),
            child: Text(
              S.tapForWhy,
              textAlign: TextAlign.center,
              style: context.type.footnote,
            ),
          ),
      ],
    );
  }
}

/// Short "why" sheet for one plan; "More details" opens the full page.
void showPlanSheet(
  BuildContext context,
  RotationScenario s,
  String label,
  FieldAnalysis a,
) {
  showFsSheet<void>(
    context,
    title: label,
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScenarioDetailBody(
          scenario: s,
          label: label,
          analysis: a,
          compact: true,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FsSpace.gutter,
            FsSpace.lg,
            FsSpace.gutter,
            0,
          ),
          child: FsButton(
            S.moreDetails,
            kind: FsButtonKind.tinted,
            onPressed: () {
              Navigator.of(ctx).pop();
              context.push('/scenario/${s.id}');
            },
          ),
        ),
      ],
    ),
  );
}
