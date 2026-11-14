import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/strings.dart';
import '../../design/components/feedback.dart';
import '../../design/components/page.dart';
import '../../design/components/scenario.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';

/// Stand-alone detail page for one option (deep link / sidebar).
class ScenarioDetailScreen extends ConsumerWidget {
  const ScenarioDetailScreen({super.key, required this.scenarioId});
  final String scenarioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(analysisProvider);
    final a = state is AnalysisReady ? state.analysis : null;
    final match = a == null
        ? null
        : labelledScenarios(
            a.scenarios,
          ).where((e) => e.$1.id == scenarioId).firstOrNull;

    if (a == null || match == null) {
      return Scaffold(
        backgroundColor: context.fs.background,
        appBar: const CupertinoNavigationBar(previousPageTitle: S.back),
        body: const FsMessageView(
          icon: CupertinoIcons.question_circle_fill,
          title: S.errorTitle,
          message: S.notFound,
        ),
      );
    }
    final (scenario, label) = match;
    return FsPage(
      title: scenario.title,
      largeTitle: false,
      navMiddle: label,
      children: [
        ScenarioDetailBody(scenario: scenario, label: label, analysis: a),
      ],
    );
  }
}
