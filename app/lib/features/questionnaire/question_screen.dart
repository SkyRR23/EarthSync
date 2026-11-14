import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/strings.dart';
import '../../data/models/farmer_input.dart';
import '../../design/components/buttons.dart';
import '../../design/components/choice.dart';
import '../../design/components/page.dart';
import '../../design/components/scenario.dart' show cropIcon, monthShort;
import '../../design/tokens.dart';
import '../../state/providers.dart';

const kQuestionCount = 6;

final _cropChoices = [
  for (final e in Crops.options.entries)
    FsChoice(e.key, e.value, cropIcon(e.key)),
];

/// One widget for all six questions; [step] is 1-based.
/// [editing] = opened from Review's rows: return there after answering.
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
    /// so farmers can answer with one tap. The button stays available too.
    void answerThenAdvance(VoidCallback save) {
      final route = ModalRoute.of(context);
      save();
      Future<void>.delayed(_autoAdvanceDelay, () {
        if (!context.mounted || route == null || !route.isCurrent) return;
        next();
      });
    }

    final (
      String question,
      String? hint,
      Widget body,
      bool answered,
    ) = switch (step) {
      1 => (
        S.qCurrentCrop,
        null,
        FsChoiceList<String>(
          header: S.crops,
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
        FsChoiceList<String>(
          header: S.crops,
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
        FsChoiceGrid<int>(
          header: S.months,
          choices: [
            for (var m = 1; m <= 12; m++) FsChoice(m, monthShort[m - 1]),
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
        FsChoiceList<Irrigation>(
          choices: const [
            FsChoice(
              Irrigation.full,
              'Yes, all year',
              CupertinoIcons.drop_fill,
            ),
            FsChoice(
              Irrigation.partial,
              'Sometimes or a little',
              CupertinoIcons.drop,
            ),
            FsChoice(
              Irrigation.none,
              'No, only rain',
              CupertinoIcons.cloud_rain,
            ),
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
        FsChoiceList<Drainage>(
          choices: const [
            FsChoice(
              Drainage.poor,
              'Yes, for many days',
              CupertinoIcons.drop_fill,
            ),
            FsChoice(
              Drainage.moderate,
              'For a day or two',
              CupertinoIcons.drop,
            ),
            FsChoice(
              Drainage.good,
              'No, it drains fast',
              CupertinoIcons.sun_max,
            ),
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
    final t = context.type;
    return FsPage(
      title: question,
      largeTitle: false,
      navMiddle: S.stepOf(step, kQuestionCount),
      below: FsProgressLine(
        step / kQuestionCount,
        semanticLabel: S.stepSemantic(step, kQuestionCount),
      ),
      bottomBar: FsButton(
        editing ? S.done : (last ? S.reviewAnswers : S.next),
        onPressed: answered ? next : null,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FsSpace.gutter + FsSpace.xs,
            FsSpace.xxl,
            FsSpace.gutter,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(header: true, child: Text(question, style: t.title1)),
              if (hint != null) ...[
                const SizedBox(height: FsSpace.xs),
                Text(
                  hint,
                  style: t.body.copyWith(color: context.fs.secondaryLabel),
                ),
              ],
            ],
          ),
        ),
        body,
      ],
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
    return FsChoiceList<Priority?>(
      multi: true,
      choices: const [
        FsChoice(
          Priority.income,
          'More income',
          CupertinoIcons.money_dollar_circle,
        ),
        FsChoice(Priority.lessWater, 'Use less water', CupertinoIcons.drop),
        FsChoice(Priority.soilHealth, 'Healthier soil', Icons.eco_outlined),
        FsChoice(
          Priority.lowerRisk,
          'Lower risk of crop loss',
          CupertinoIcons.shield,
        ),
        FsChoice(
          Priority.foodForFamily,
          'Food for my family',
          CupertinoIcons.house,
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
