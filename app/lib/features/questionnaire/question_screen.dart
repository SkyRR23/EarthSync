import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/strings.dart';
import '../../data/models/farmer_input.dart';
import '../../design/components/buttons.dart';
import '../../design/components/choice.dart';
import '../../design/components/page.dart';
import '../../design/components/scenario.dart' show cropEmoji;
import '../../design/tokens.dart';
import '../../state/providers.dart';

/// Only the three answers the engine uses (crop, water, drainage).
const kQuestionCount = 3;

final _cropChoices = [
  for (final e in Crops.options.entries)
    FsChoice(e.key, '${cropEmoji(e.key)}  ${e.value}'),
];

/// One widget for all questions; [step] is 1-based.
/// [editing] = opened from Home's "Your answers": return there after.
class QuestionScreen extends ConsumerWidget {
  const QuestionScreen({super.key, required this.step, this.editing = false});
  final int step;
  final bool editing;

  static const _autoAdvanceDelay = Duration(milliseconds: 350);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(farmerDraftProvider);
    final n = ref.read(farmerDraftProvider.notifier);
    final last = step == kQuestionCount;

    void next() {
      final analysis = ref.read(analysisProvider.notifier);
      if (editing) {
        analysis.run(ref.read(farmerDraftProvider).toInput());
        context.pop();
      } else if (last) {
        analysis.run(ref.read(farmerDraftProvider).toInput());
        context.go('/home');
      } else {
        context.push('/question/${step + 1}');
      }
    }

    /// One tap answers and moves on (button stays available too).
    void answerThenAdvance(VoidCallback save) {
      final route = ModalRoute.of(context);
      save();
      Future<void>.delayed(_autoAdvanceDelay, () {
        if (!context.mounted || route == null || !route.isCurrent) return;
        next();
      });
    }

    final (String question, Widget body, bool answered) = switch (step) {
      1 => (
        S.qCurrentCrop,
        FsChoiceList<String>(
          choices: _cropChoices,
          unknownValue: kUnknown,
          selected: {?d.currentCrop},
          onChanged: (s) => answerThenAdvance(() => n.setCurrentCrop(s.first)),
        ),
        d.currentCrop != null,
      ),
      2 => (
        S.qIrrigation,
        FsChoiceList<Irrigation>(
          choices: const [
            FsChoice(Irrigation.full, 'Yes, all year', CupertinoIcons.drop_fill),
            FsChoice(Irrigation.partial, 'Sometimes', CupertinoIcons.drop),
            FsChoice(Irrigation.none, 'No, only rain', CupertinoIcons.cloud_rain),
          ],
          unknownValue: Irrigation.unknown,
          selected: {?d.irrigation},
          onChanged: (s) => answerThenAdvance(() => n.setIrrigation(s.first)),
        ),
        d.irrigation != null,
      ),
      _ => (
        S.qDrainage,
        FsChoiceList<Drainage>(
          choices: const [
            FsChoice(Drainage.poor, 'Yes, for many days', CupertinoIcons.drop_fill),
            FsChoice(Drainage.moderate, 'For a day or two', CupertinoIcons.drop),
            FsChoice(Drainage.good, 'No, it dries fast', CupertinoIcons.sun_max),
          ],
          unknownValue: Drainage.unknown,
          selected: {?d.drainage},
          onChanged: (s) => answerThenAdvance(() => n.setDrainage(s.first)),
        ),
        d.drainage != null,
      ),
    };

    return FsPage(
      title: question,
      largeTitle: false,
      navMiddle: S.stepOf(step, kQuestionCount),
      below: FsProgressLine(
        step / kQuestionCount,
        semanticLabel: S.stepSemantic(step, kQuestionCount),
      ),
      bottomBar: FsButton(
        editing ? S.done : (last ? S.seeResults : S.next),
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
          child: Semantics(
            header: true,
            child: Text(question, style: context.type.title1),
          ),
        ),
        body,
      ],
    );
  }
}
