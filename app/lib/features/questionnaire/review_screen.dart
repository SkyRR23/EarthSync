import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/strings.dart';
import '../../data/models/farmer_input.dart';
import '../../design/components/buttons.dart';
import '../../design/components/grouped.dart';
import '../../design/components/page.dart';
import '../../design/components/scenario.dart' show monthNames;
import '../../design/tokens.dart';
import '../../state/providers.dart';

String _crop(String? v) =>
    (v == null || v == kUnknown) ? S.notAnswered : Crops.label(v);

/// Settings-style summary of every answer; each row edits its question.
class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(farmerDraftProvider);
    final p = context.fs;

    FsListRow row(
      IconData icon,
      Color color,
      String label,
      String value,
      String route,
    ) => FsListRow(
      leading: FsIconBadge(icon, color: color),
      title: label,
      value: value,
      onTap: () => context.push(route),
      semanticLabel: '$label: $value. Change',
    );

    return FsPage(
      title: S.reviewTitle,
      bottomBar: FsButton(
        S.analyze,
        onPressed: d.hasLocation
            ? () {
                ref.read(analysisProvider.notifier).run(d.toInput());
                context.push('/results');
              }
            : null,
      ),
      children: [
        FsGroupedSection(
          header: 'Field',
          separatorIndent: FsSpace.lg + 30 + FsSpace.md,
          children: [
            row(
              CupertinoIcons.location_solid,
              p.crop3,
              'Location',
              d.hasLocation
                  ? '${d.latitude!.toStringAsFixed(3)}, ${d.longitude!.toStringAsFixed(3)}'
                  : S.notAnswered,
              '/location?edit=1',
            ),
          ],
        ),
        FsGroupedSection(
          header: 'Crops',
          separatorIndent: FsSpace.lg + 30 + FsSpace.md,
          children: [
            row(
              Icons.grass_rounded,
              p.crop1,
              'Now growing',
              _crop(d.currentCrop),
              '/question/1?edit=1',
            ),
            row(
              Icons.history_rounded,
              p.crop2,
              'Grew before',
              _crop(d.previousCrop),
              '/question/2?edit=1',
            ),
            row(
              CupertinoIcons.calendar,
              p.crop4,
              'Planting month',
              (d.plantingMonth == null || d.plantingMonth == 0)
                  ? S.notAnswered
                  : monthNames[d.plantingMonth! - 1],
              '/question/3?edit=1',
            ),
          ],
        ),
        FsGroupedSection(
          header: 'Water and soil',
          footer: S.reviewFooter,
          separatorIndent: FsSpace.lg + 30 + FsSpace.md,
          children: [
            row(
              CupertinoIcons.drop_fill,
              p.rain,
              'Water',
              switch (d.irrigation) {
                Irrigation.full => 'All year',
                Irrigation.partial => 'Sometimes',
                Irrigation.none => 'Rain only',
                _ => S.notAnswered,
              },
              '/question/4?edit=1',
            ),
            row(
              CupertinoIcons.cloud_rain,
              p.crop3,
              'Drainage',
              switch (d.drainage) {
                Drainage.poor => 'Stays many days',
                Drainage.moderate => 'Stays 1–2 days',
                Drainage.good => 'Drains fast',
                _ => S.notAnswered,
              },
              '/question/5?edit=1',
            ),
            row(
              CupertinoIcons.star_fill,
              p.heat,
              'Priorities',
              (d.priorities == null || d.priorities!.isEmpty)
                  ? S.notAnswered
                  : '${d.priorities!.length} chosen',
              '/question/6?edit=1',
            ),
          ],
        ),
      ],
    );
  }
}
