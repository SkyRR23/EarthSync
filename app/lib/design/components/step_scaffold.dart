import 'package:flutter/material.dart';

import '../../app/strings.dart';
import '../tokens.dart';

/// Wraps one question: progress, title, body, and a sticky Next button.
class FsStepScaffold extends StatelessWidget {
  const FsStepScaffold({
    super.key,
    required this.title,
    required this.child,
    required this.onNext,
    this.progressLabel,
    this.progress,
    this.subtitle,
    this.nextLabel = S.next,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  /// null disables Next (question not answered yet).
  final VoidCallback? onNext;
  final String? progressLabel;
  final double? progress;
  final String nextLabel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: progressLabel == null
            ? null
            : Text(progressLabel!, style: t.bodyMedium),
        bottom: progress == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(value: progress, minHeight: 4),
              ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(FsSpace.gutter),
                    children: [
                      Text(title, style: t.headlineMedium),
                      if (subtitle != null) ...[
                        const SizedBox(height: FsSpace.xs),
                        Text(
                          subtitle!,
                          style: t.bodyLarge?.copyWith(
                            color: FsColors.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: FsSpace.lg),
                      child,
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(FsSpace.gutter),
                  child: FilledButton(
                    onPressed: onNext,
                    child: Text(nextLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
