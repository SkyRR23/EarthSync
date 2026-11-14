import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/strings.dart';
import '../../data/models/farmer_input.dart';
import '../../design/components/scenario.dart' show monthNames;
import '../../design/components/step_scaffold.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';

String _crop(String? v) =>
    (v == null || v == kUnknown) ? S.notAnswered : Crops.label(v);

class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(farmerDraftProvider);
    final rows = <(String, String, String)>[
      (
        'Field',
        d.hasLocation
            ? '${d.latitude!.toStringAsFixed(4)}, ${d.longitude!.toStringAsFixed(4)}'
            : S.notAnswered,
        '/location?edit=1',
      ),
      ('Now growing', _crop(d.currentCrop), '/question/1?edit=1'),
      ('Grew before', _crop(d.previousCrop), '/question/2?edit=1'),
      (
        'Plant in',
        (d.plantingMonth == null || d.plantingMonth == 0)
            ? S.notAnswered
            : monthNames[d.plantingMonth! - 1],
        '/question/3?edit=1',
      ),
      (
        'Water',
        switch (d.irrigation) {
          Irrigation.full => 'All year',
          Irrigation.partial => 'Sometimes',
          Irrigation.none => 'Rain only',
          _ => S.notAnswered,
        },
        '/question/4?edit=1',
      ),
      (
        'Drainage',
        switch (d.drainage) {
          Drainage.poor => 'Water stays many days',
          Drainage.moderate => 'Water stays 1–2 days',
          Drainage.good => 'Drains fast',
          _ => S.notAnswered,
        },
        '/question/5?edit=1',
      ),
      (
        'Priorities',
        (d.priorities == null || d.priorities!.isEmpty)
            ? S.notAnswered
            : '${d.priorities!.length} chosen',
        '/question/6?edit=1',
      ),
    ];

    return FsStepScaffold(
      title: S.reviewTitle,
      nextLabel: S.analyze,
      onNext: d.hasLocation
          ? () {
              ref.read(analysisProvider.notifier).run(d.toInput());
              context.push('/results');
            }
          : null,
      child: Card(
        child: Column(
          children: [
            for (final (label, value, route) in rows)
              ListTile(
                minTileHeight: FsSpace.minTouch + 8,
                title: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                subtitle: Text(
                  value,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                trailing: TextButton(
                  onPressed: () => context.push(route),
                  child: const Text(S.edit),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
