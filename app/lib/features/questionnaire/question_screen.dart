import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/strings.dart';
import '../../data/models/farmer_input.dart';
import '../../design/components/choice_group.dart';
import '../../design/components/step_scaffold.dart';
import '../../state/providers.dart';

const kQuestionCount = 6;

IconData _cropIcon(String id) => switch (id) {
  'rice' => Icons.grass,
  'mung_bean' || 'black_gram' || 'chickpea' => Icons.spa_outlined,
  'groundnut' || 'sesame' => Icons.grain,
  'maize' => Icons.agriculture,
  'vegetables' => Icons.eco_outlined,
  'fallow' => Icons.landscape_outlined,
  _ => Icons.grass,
};

final _cropChoices = [
  for (final e in Crops.options.entries)
    FsChoice(e.key, e.value, _cropIcon(e.key)),
];

const _monthShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// One widget for all six questions; [step] is 1-based.
/// [editing] = opened from the review screen's "Change": return there after.
class QuestionScreen extends ConsumerWidget {
  const QuestionScreen({super.key, required this.step, this.editing = false});
  final int step;
  final bool editing;

  static const _autoAdvanceDelay = Duration(milliseconds: 350);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(farmerDraftProvider);
    final n = ref.read(farmerDraftProvider.notifier);

    void next() {
      if (editing) {
        context.pop();
      } else {
        context.push(
          step < kQuestionCount ? '/question/${step + 1}' : '/review',
        );
      }
    }

    /// Single-choice questions move on by themselves after a short pause,
    /// so farmers can answer with one tap. Next stays available too.
    void answerThenAdvance(VoidCallback save) {
      final route = ModalRoute.of(context);
      save();
      Future<void>.delayed(_autoAdvanceDelay, () {
        // Only advance if the user is still on this question.
        if (!context.mounted || route == null || !route.isCurrent) return;
        next();
      });
    }

    final (
      String title,
      String? subtitle,
      Widget body,
      bool answered,
    ) = switch (step) {
      1 => (
        S.qCurrentCrop,
        null,
        FsChoiceGroup<String>(
          columns: 2,
          choices: _cropChoices,
          unknownValue: kUnknown,
          selected: {?d.currentCrop},
          onChanged: (s) => answerThenAdvance(() => n.setCurrentCrop(s.first)),
        ),
        d.currentCrop != null,
      ),
      2 => (
        S.qRecentRotation,
        null,
        FsChoiceGroup<String>(
          columns: 2,
          choices: _cropChoices,
          unknownValue: kUnknown,
          selected: {?d.previousCrop},
          onChanged: (s) => answerThenAdvance(() => n.setPreviousCrop(s.first)),
        ),
        d.previousCrop != null,
      ),
      3 => (
        S.qPlantingMonth,
        null,
        FsChoiceGroup<int>(
          columns: 3,
          choices: [
            for (var m = 1; m <= 12; m++) FsChoice(m, _monthShort[m - 1]),
          ],
          unknownValue: 0,
          selected: {?d.plantingMonth},
          onChanged: (s) =>
              answerThenAdvance(() => n.setPlantingMonth(s.first)),
        ),
        d.plantingMonth != null,
      ),
      4 => (
        S.qIrrigation,
        null,
        FsChoiceGroup<Irrigation>(
          choices: const [
            FsChoice(Irrigation.full, 'Yes, all year', Icons.water_drop),
            FsChoice(
              Irrigation.partial,
              'Sometimes / a little',
              Icons.water_drop_outlined,
            ),
            FsChoice(Irrigation.none, 'No, only rain', Icons.cloud_outlined),
          ],
          unknownValue: Irrigation.unknown,
          selected: {?d.irrigation},
          onChanged: (s) => answerThenAdvance(() => n.setIrrigation(s.first)),
        ),
        d.irrigation != null,
      ),
      5 => (
        S.qDrainage,
        null,
        FsChoiceGroup<Drainage>(
          choices: const [
            FsChoice(Drainage.poor, 'Yes, for many days', Icons.water),
            FsChoice(Drainage.moderate, 'For a day or two', Icons.waves),
            FsChoice(Drainage.good, 'No, it drains fast', Icons.check),
          ],
          unknownValue: Drainage.unknown,
          selected: {?d.drainage},
          onChanged: (s) => answerThenAdvance(() => n.setDrainage(s.first)),
        ),
        d.drainage != null,
      ),
      _ => (
        S.qPriorities,
        S.chooseAny,
        _PrioritiesQuestion(
          selected: d.priorities,
          onChanged: n.setPriorities,
          onCleared: n.clearPriorities,
        ),
        d.priorities != null,
      ),
    };

    final last = step == kQuestionCount;
    return FsStepScaffold(
      progressLabel: S.stepOf(step, kQuestionCount),
      progress: step / kQuestionCount,
      title: title,
      subtitle: subtitle,
      nextLabel: editing ? S.done : (last ? S.reviewAnswers : S.next),
      onNext: answered ? next : null,
      child: body,
    );
  }
}

/// Multi-select. "I don't know" is stored as an empty set; unticking
/// everything returns to "not answered".
class _PrioritiesQuestion extends StatelessWidget {
  const _PrioritiesQuestion({
    required this.selected,
    required this.onChanged,
    required this.onCleared,
  });
  final Set<Priority>? selected;
  final ValueChanged<Set<Priority>> onChanged;
  final VoidCallback onCleared;

  @override
  Widget build(BuildContext context) {
    final sel = selected;
    final current = <Priority?>{if (sel != null && sel.isEmpty) null, ...?sel};
    return FsChoiceGroup<Priority?>(
      multi: true,
      choices: const [
        FsChoice(Priority.income, 'More income', Icons.payments_outlined),
        FsChoice(
          Priority.lessWater,
          'Use less water',
          Icons.water_drop_outlined,
        ),
        FsChoice(Priority.soilHealth, 'Healthier soil', Icons.eco_outlined),
        FsChoice(
          Priority.lowerRisk,
          'Lower risk of crop loss',
          Icons.shield_outlined,
        ),
        FsChoice(
          Priority.foodForFamily,
          'Food for my family',
          Icons.restaurant,
        ),
      ],
      unknownValue: null,
      selected: current,
      onChanged: (s) {
        if (s.contains(null)) {
          onChanged({}); // "I don't know"
        } else if (s.isEmpty) {
          onCleared();
        } else {
          onChanged(s.whereType<Priority>().toSet());
        }
      },
    );
  }
}
