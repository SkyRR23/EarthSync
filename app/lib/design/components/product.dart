import 'package:flutter/material.dart';
import '../../app/ui_copy.dart';

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.eyebrow,
    this.action,
  });
  final String title, subtitle;
  final String? eyebrow;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          Text(
            eyebrow!.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.5,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 10),
        ],
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
        ),
        const SizedBox(height: 8),
        Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.title, this.icon});
  final Widget child;
  final String? title;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              children: [
                if (icon != null)
                  Icon(icon, color: Theme.of(context).colorScheme.primary),
                Text(title!, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
          ],
          child,
        ],
      ),
    ),
  );
}

class ActionCard extends StatelessWidget {
  const ActionCard({
    super.key,
    required this.title,
    required this.body,
    required this.icon,
    required this.onTap,
  });
  final String title, body;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.arrow_outward, size: 20),
              ],
            ),
            const SizedBox(height: 18),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(body),
          ],
        ),
      ),
    ),
  );
}

class ResponsivePair extends StatelessWidget {
  const ResponsivePair({
    super.key,
    required this.first,
    required this.second,
    this.reverseOnNarrow = false,
  });
  final Widget first, second;
  final bool reverseOnNarrow;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, box) => box.maxWidth >= 720
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: first),
              const SizedBox(width: 16),
              Expanded(child: second),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: reverseOnNarrow
                ? [second, const SizedBox(height: 16), first]
                : [first, const SizedBox(height: 4), second],
          ),
  );
}

class EvidenceNotice extends StatelessWidget {
  const EvidenceNotice({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.info_outline,
    this.action,
  });
  final String title, message;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => SectionCard(
    title: title,
    icon: icon,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(message), ?action],
    ),
  );
}

class SourceNote extends StatelessWidget {
  const SourceNote({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Text(
      UiCopy.text(context, 'sourceNote'),
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );
}

/// Decorative contour lines, deliberately not a map or environmental data.
class LandContours extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 0; i < 12; i++) {
      final offset = i * 28.0;
      canvas.drawPath(
        Path()
          ..moveTo(size.width * .4 + offset, -20)
          ..cubicTo(
            size.width * .15 + offset,
            size.height * .5,
            size.width + offset,
            size.height * .4,
            size.width * .6 + offset,
            size.height + 40,
          ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ) ??
    false;

class EvidenceLoading extends StatelessWidget {
  const EvidenceLoading({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: label,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label),
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            ExcludeSemantics(
              child: Column(
                children: [
                  for (final width in [1.0, .8, .6])
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: width,
                        child: Container(
                          height: 12,
                          margin: const EdgeInsets.only(top: 12),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
