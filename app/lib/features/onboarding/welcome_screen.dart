import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/strings.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Scrolls on small phones / large text instead of overflowing.
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(FsSpace.gutter),
                children: [
                  const SizedBox(height: FsSpace.lg),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Icon(
                      Icons.satellite_alt,
                      size: 56,
                      color: FsColors.primary,
                    ),
                  ),
                  const SizedBox(height: FsSpace.md),
                  Text(
                    S.appName,
                    style: t.titleLarge?.copyWith(color: FsColors.primary),
                  ),
                  const SizedBox(height: FsSpace.sm),
                  Text(S.welcomeTitle, style: t.headlineMedium),
                  const SizedBox(height: FsSpace.md),
                  Text(S.welcomeBody, style: t.bodyLarge),
                  const SizedBox(height: FsSpace.lg),
                  Text(S.howItWorks, style: t.titleMedium),
                  const SizedBox(height: FsSpace.sm),
                  const _Step(
                    n: 1,
                    icon: Icons.location_on_outlined,
                    text: S.how1,
                  ),
                  const _Step(n: 2, icon: Icons.checklist, text: S.how2),
                  const _Step(n: 3, icon: Icons.autorenew, text: S.how3),
                  const SizedBox(height: FsSpace.md),
                  Container(
                    padding: const EdgeInsets.all(FsSpace.md),
                    decoration: BoxDecoration(
                      color: FsColors.primaryContainer.withValues(alpha: 0.4),
                      borderRadius: const BorderRadius.all(FsRadius.md),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, color: FsColors.primary),
                        const SizedBox(width: FsSpace.sm),
                        Expanded(
                          child: Text(S.welcomeDisclaimer, style: t.bodyMedium),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(FsSpace.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Developer info only — hidden in release builds.
                  if (kDebugMode)
                    FutureBuilder<String>(
                      future: ref.read(engineProvider).engineVersion(),
                      builder: (_, snap) => Padding(
                        padding: const EdgeInsets.only(bottom: FsSpace.sm),
                        child: Text(
                          'Engine: ${snap.data ?? '…'}',
                          style: t.bodySmall,
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed: () => context.push('/location'),
                    child: const Text(S.start),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.icon, required this.text});
  final int n;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: FsSpace.xs),
    child: Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: FsColors.primaryContainer,
          child: Icon(icon, size: 20, color: FsColors.primary),
        ),
        const SizedBox(width: FsSpace.md),
        Expanded(
          child: Text(
            '$n. $text',
            style: Theme.of(context).textTheme.bodyLarge,
            semanticsLabel: 'Step $n: $text',
          ),
        ),
      ],
    ),
  );
}
