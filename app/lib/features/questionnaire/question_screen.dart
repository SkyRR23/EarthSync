import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/strings.dart';
import '../../data/models/farmer_input.dart';
import '../../design/components/buttons.dart';
import '../../design/components/picture_tiles.dart';
import '../../design/components/page.dart';
import '../../design/components/scenario.dart' show cropEmoji;
import '../../design/tokens.dart';
import '../../state/providers.dart';

/// Only the three answers the engine uses (crop, water, drainage).
const kQuestionCount = 3;

final _cropChoices = [
  for (final e in Crops.options.entries)
    FsPicture(e.key, cropEmoji(e.key), e.value),
];

const _unsureCrop = FsPicture(kUnknown, '🤔', S.dontKnow);

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
        FsPictureGrid<String>(
          choices: _cropChoices,
          unsure: _unsureCrop,
          columns: 3,
          tileHeight: 104,
          selected: d.currentCrop,
          onSelect: (v) => answerThenAdvance(() => n.setCurrentCrop(v)),
        ),
        d.currentCrop != null,
      ),
      2 => (
        S.qIrrigation,
        FsPictureGrid<Irrigation>(
          choices: const [
            FsPicture(Irrigation.none, '🌧️', S.waterRain),
            FsPicture(Irrigation.partial, '💧', S.waterSome),
            FsPicture(Irrigation.full, '🚰', S.waterAll),
          ],
          unsure: const FsPicture(Irrigation.unknown, '🤔', S.dontKnow),
          columns: 3,
          selected: d.irrigation,
          onSelect: (v) => answerThenAdvance(() => n.setIrrigation(v)),
        ),
        d.irrigation != null,
      ),
      _ => (
        S.qDrainage,
        FsPictureGrid<Drainage>(
          choices: const [
            FsPicture(Drainage.good, '☀️', S.drainFast),
            FsPicture(Drainage.moderate, '⏳', S.drainDays),
            FsPicture(Drainage.poor, '🌊', S.drainLong),
          ],
          unsure: const FsPicture(Drainage.unknown, '🤔', S.dontKnow),
          columns: 3,
          selected: d.drainage,
          onSelect: (v) => answerThenAdvance(() => n.setDrainage(v)),
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
            FsSpace.xl,
            FsSpace.gutter,
            0,
          ),
          child: Semantics(
            header: true,
            child: Text(question, style: context.type.largeTitle),
          ),
        ),
        body,
      ],
    );
  }
}
