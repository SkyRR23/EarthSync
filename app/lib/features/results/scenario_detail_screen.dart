import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/strings.dart';
import '../../design/components/feedback.dart';
import '../../design/components/page.dart';
import '../../design/components/scenario.dart';
import '../../state/providers.dart';

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
    if (match == null) {
      return const FsPage(
        title: S.notFound,
        children: [
          FsMessageView(
            icon: CupertinoIcons.exclamationmark_circle,
            title: S.notFound,
            message: S.notFound,
          ),
        ],
      );
    }
    final (scenario, label, _) = match;
    return FsPage(
      title: cropSequence(scenario),
      largeTitle: false,
      navMiddle: label,
      children: [
        ScenarioDetailBody(scenario: scenario, label: label, analysis: a!),
      ],
    );
  }
}
