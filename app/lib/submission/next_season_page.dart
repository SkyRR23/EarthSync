import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../design/components/page.dart';
import '../design/components/buttons.dart';
import '../design/tokens.dart';
import '../features/home/crops_tab.dart';
import '../state/providers.dart';

class NextSeasonPage extends ConsumerWidget {
  const NextSeasonPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(analysisProvider);
    if (state is AnalysisReady) {
      return CropsTab(analysis: state.analysis, fromCache: state.fromCache);
    }
    return FsPage(
      title: 'Next season',
      children: [
        Padding(
          padding: const EdgeInsets.all(FsSpace.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Plan your crop rotation', style: context.type.title2),
              const SizedBox(height: FsSpace.md),
              const Text(
                'Compare crop sequences and save your decision on this device. Available source evidence can support your review; suitability remains unknown without reviewed requirements.',
              ),
              const SizedBox(height: FsSpace.lg),
              FsButton(
                'Compare crop rotations & save my decision',
                onPressed: () => context.push('/rotation-plans'),
              ),
              const SizedBox(height: FsSpace.sm),
              FsButton(
                'Explore the historical timeline',
                kind: FsButtonKind.tinted,
                onPressed: () => context.push('/historical'),
              ),
              const SizedBox(height: FsSpace.md),
              Text(
                state is AnalysisFailed
                    ? 'Environmental evidence could not refresh. Your saved plans and local tasks remain available.'
                    : 'Environmental analysis is not ready. You can continue planning locally.',
              ),
              TextButton(
                onPressed: () => context.push('/sources'),
                child: const Text('Sources & data'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
