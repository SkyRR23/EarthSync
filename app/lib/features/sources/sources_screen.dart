import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/strings.dart';
import '../../data/models/field_analysis.dart';
import '../../design/components/grouped.dart';
import '../../design/components/page.dart';
import '../../design/components/status.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';

class SourcesScreen extends ConsumerWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(analysisProvider);
    final a = state is AnalysisReady ? state.analysis : null;
    final indent = FsSpace.lg + 22 + FsSpace.md;

    return FsPage(
      title: S.sources,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FsSpace.gutter + FsSpace.xs,
            FsSpace.sm,
            FsSpace.gutter,
            0,
          ),
          child: Text(
            S.sourcesIntro,
            style: context.type.callout.copyWith(
              color: context.fs.secondaryLabel,
            ),
          ),
        ),
        if (a != null && a.references.isNotEmpty)
          FsGroupedSection(
            header: S.sourcesUsed,
            separatorIndent: indent,
            children: [for (final r in a.references) FsEvidenceRow(r)],
          ),
        FsGroupedSection(
          header: S.evidenceTypes,
          separatorIndent: indent,
          children: [
            for (final type in EvidenceType.values)
              FsListRow(
                leading: Icon(
                  evidenceStyle(type).$1,
                  color: evidenceColor(context, type),
                  size: 22,
                ),
                title: evidenceStyle(type).$2,
              ),
          ],
        ),
        if (a != null && a.assumptions.isNotEmpty)
          FsGroupedSection(
            header: S.assumptions,
            separatorIndent: indent,
            children: [
              for (final s in a.assumptions)
                FsListRow(
                  leading: Icon(
                    CupertinoIcons.text_quote,
                    color: context.fs.secondaryLabel,
                    size: 22,
                  ),
                  title: s,
                  titleStyle: context.type.callout,
                ),
            ],
          ),
      ],
    );
  }
}
