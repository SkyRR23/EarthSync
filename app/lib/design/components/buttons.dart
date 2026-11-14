import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../tokens.dart';
import 'pressable.dart';

enum FsButtonKind {
  /// Solid accent capsule. At most one per screen.
  filled,

  /// Soft accent background — secondary actions.
  tinted,

  /// Text only — tertiary actions.
  plain,
}

/// Capsule button in Apple's style.
class FsButton extends StatelessWidget {
  const FsButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.kind = FsButtonKind.filled,
    this.icon,
    this.loading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final FsButtonKind kind;
  final IconData? icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final enabled = onPressed != null && !loading;
    final (Color bg, Color fg) = switch (kind) {
      _ when onPressed == null => (p.fill, p.tertiaryLabel),
      FsButtonKind.filled => (p.tint, p.onTint),
      FsButtonKind.tinted => (p.tintSoft, p.tint),
      FsButtonKind.plain => (Colors.transparent, p.tint),
    };

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          CupertinoActivityIndicator(color: fg)
        else if (icon != null)
          Icon(icon, size: 20, color: fg),
        if (loading || icon != null) const SizedBox(width: FsSpace.sm),
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: context.type.labelLarge?.copyWith(color: fg),
          ),
        ),
      ],
    );

    return FsPressable(
      onTap: enabled ? onPressed : null,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: FsMotion.of(context, FsMotion.normal),
        width: expand ? double.infinity : null,
        constraints: const BoxConstraints(minHeight: FsSpace.minTouch),
        padding: const EdgeInsets.symmetric(
          horizontal: FsSpace.xl,
          vertical: FsSpace.md,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(FsRadius.capsule),
        ),
        child: ExcludeSemantics(
          child: Center(widthFactor: 1, heightFactor: 1, child: content),
        ),
      ),
    );
  }
}

/// Round floating control used over maps.
class FsCircleButton extends StatelessWidget {
  const FsCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    return Tooltip(
      message: tooltip,
      child: FsPressable(
        onTap: onPressed,
        semanticLabel: tooltip,
        scale: 0.92,
        child: Container(
          width: FsSpace.minTouch,
          height: FsSpace.minTouch,
          decoration: BoxDecoration(
            color: p.surfaceRaised.withValues(alpha: 0.94),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, color: p.tint, size: 22),
        ),
      ),
    );
  }
}
