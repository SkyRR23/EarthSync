import 'package:flutter/material.dart';

import '../../app/strings.dart';
import '../../data/models/field_analysis.dart';
import '../tokens.dart';
import 'badges.dart';

enum FsBannerKind { info, warning }

/// Top-of-results notice: demo / saved / partial data.
class FsDataQualityBanner extends StatelessWidget {
  const FsDataQualityBanner({
    super.key,
    required this.message,
    this.kind = FsBannerKind.info,
  });
  final String message;
  final FsBannerKind kind;

  @override
  Widget build(BuildContext context) {
    final color = kind == FsBannerKind.warning
        ? FsColors.constrained
        : FsColors.sky;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FsSpace.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color),
        borderRadius: const BorderRadius.all(FsRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            kind == FsBannerKind.warning
                ? Icons.warning_amber
                : Icons.info_outline,
            color: color,
          ),
          const SizedBox(width: FsSpace.sm),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// Alerts always stay visible (not dismissible).
class FsAlertCard extends StatelessWidget {
  const FsAlertCard(this.alert, {super.key});
  final Alert alert;

  @override
  Widget build(BuildContext context) {
    final color = riskColor(alert.level);
    return Container(
      decoration: BoxDecoration(
        color: FsColors.surface,
        border: Border(left: BorderSide(color: color, width: 6)),
      ),
      padding: const EdgeInsets.all(FsSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FsRiskBadge(hazard: alert.hazard, level: alert.level),
          const SizedBox(height: FsSpace.sm),
          Text(alert.message, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

/// Full-screen loading / error state.
class FsStateView extends StatelessWidget {
  const FsStateView.loading({super.key, this.message = S.analyzing})
    : title = null,
      actions = const [],
      loading = true;

  const FsStateView.error({
    super.key,
    required this.title,
    required this.message,
    this.actions = const [],
  }) : loading = false;

  final String? title;
  final String message;
  final List<Widget> actions;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FsSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox.square(
                dimension: 56,
                child: CircularProgressIndicator(strokeWidth: 5),
              )
            else
              const Icon(Icons.cloud_off, size: 56, color: FsColors.riskHigh),
            const SizedBox(height: FsSpace.lg),
            if (title != null) ...[
              Text(title!, style: t.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: FsSpace.sm),
            ],
            Text(message, style: t.bodyLarge, textAlign: TextAlign.center),
            const SizedBox(height: FsSpace.lg),
            for (final a in actions)
              Padding(
                padding: const EdgeInsets.only(bottom: FsSpace.sm),
                child: a,
              ),
          ],
        ),
      ),
    );
  }
}

/// Section title used inside result screens.
class FsSectionTitle extends StatelessWidget {
  const FsSectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: FsSpace.lg, bottom: FsSpace.sm),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );
}

/// Bullet list with a leading icon.
class FsBulletList extends StatelessWidget {
  const FsBulletList(
    this.items, {
    super.key,
    this.icon = Icons.circle,
    this.color = FsColors.textSecondary,
  });
  final List<String> items;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final i in items)
        Padding(
          padding: const EdgeInsets.only(bottom: FsSpace.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(
                  icon,
                  size: icon == Icons.circle ? 8 : 20,
                  color: color,
                ),
              ),
              const SizedBox(width: FsSpace.sm),
              Expanded(
                child: Text(i, style: Theme.of(context).textTheme.bodyLarge),
              ),
            ],
          ),
        ),
    ],
  );
}
