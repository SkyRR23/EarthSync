import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/strings.dart';
import '../../design/components/feedback.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';

/// Tells the farmer when they are looking at a saved result (no internet)
/// or while a fresh check runs behind it. Tap to try again.
class FreshnessBanner extends ConsumerWidget {
  const FreshnessBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(analysisProvider);
    if (s is! AnalysisReady || (!s.fromCache && !s.refreshing)) {
      return const SizedBox.shrink();
    }
    void retry() => ref
        .read(analysisProvider.notifier)
        .run(ref.read(farmerDraftProvider).toInput(), quiet: true);
    final when = s.savedAt == null
        ? null
        : DateFormat('d MMM, h:mm a').format(s.savedAt!.toLocal());
    final Widget banner = s.refreshing
        ? FsBanner(
            message: S.updating,
            icon: CupertinoIcons.arrow_2_circlepath,
            detail: when == null ? null : S.savedResult(when),
          )
        : FsBanner(
            message: when == null ? S.showLast : S.savedResult(when),
            detail: s.refreshFailed ? S.noInternet : null,
            tone: s.refreshFailed ? FsTone.caution : FsTone.info,
            icon: s.refreshFailed
                ? CupertinoIcons.wifi_slash
                : CupertinoIcons.clock,
            onTap: retry,
          );
    return Padding(
      padding: const EdgeInsets.only(top: FsSpace.md),
      child: Semantics(liveRegion: true, child: banner),
    );
  }
}
