import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';

/// Inset grouped section (iOS Settings style): optional header and footer,
/// rows on a rounded surface separated by hairlines.
class FsGroupedSection extends StatelessWidget {
  const FsGroupedSection({
    super.key,
    this.header,
    this.footer,
    required this.children,
    this.separatorIndent = FsSpace.lg,
    this.padded = false,
  });

  final String? header;
  final String? footer;
  final List<Widget> children;

  /// Left inset of the hairline between rows (aligns with row text).
  final double separatorIndent;

  /// Wrap children in inner padding (for non-row content like charts).
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        items.add(
          Padding(
            padding: EdgeInsets.only(left: separatorIndent),
            child: Container(height: 0.5, color: p.separator),
          ),
        );
      }
      items.add(children[i]);
    }

    return Padding(
      padding: const EdgeInsets.only(top: FsSpace.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FsSpace.gutter + FsSpace.lg,
                0,
                FsSpace.gutter + FsSpace.lg,
                FsSpace.sm - 1,
              ),
              child: Semantics(
                header: true,
                child: Text(
                  header!.toUpperCase(),
                  style: context.type.footnote.copyWith(letterSpacing: 0.4),
                ),
              ),
            ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: FsSpace.gutter),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(FsRadius.md),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: padded
                  ? const EdgeInsets.all(FsSpace.lg)
                  : EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: items,
              ),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FsSpace.gutter + FsSpace.lg,
                FsSpace.sm - 1,
                FsSpace.gutter + FsSpace.lg,
                0,
              ),
              child: Text(footer!, style: context.type.footnote),
            ),
        ],
      ),
    );
  }
}

/// One row in a grouped section.
class FsListRow extends StatelessWidget {
  const FsListRow({
    super.key,
    required this.title,
    this.overline,
    this.subtitle,
    this.below,
    this.leading,
    this.value,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.chevron,
    this.titleStyle,
    this.semanticLabel,
    this.titleMaxLines,
  });

  final String title;
  final String? overline;
  final String? subtitle;

  /// Extra content under the title (e.g. status labels).
  final Widget? below;
  final Widget? leading;

  /// Right-aligned secondary value (Settings style).
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Shows an accent checkmark.
  final bool selected;

  /// Defaults to true when tappable and not a selection row.
  final bool? chevron;
  final TextStyle? titleStyle;
  final String? semanticLabel;
  final int? titleMaxLines;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    final showChevron = chevron ?? (onTap != null && !selected);

    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: FsSpace.minTouch),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FsSpace.lg,
          vertical: FsSpace.md - 1,
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: FsSpace.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (overline != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: FsSpace.xxs),
                      child: Text(overline!, style: t.footnote),
                    ),
                  Text(
                    title,
                    style: titleStyle ?? t.body,
                    maxLines: titleMaxLines,
                    overflow: titleMaxLines != null
                        ? TextOverflow.ellipsis
                        : null,
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: FsSpace.xxs),
                      child: Text(subtitle!, style: t.footnote),
                    ),
                  if (below != null)
                    Padding(
                      padding: const EdgeInsets.only(top: FsSpace.sm),
                      child: below!,
                    ),
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: FsSpace.sm),
              Flexible(
                child: Text(
                  value!,
                  textAlign: TextAlign.end,
                  style: t.body.copyWith(color: p.secondaryLabel),
                ),
              ),
            ],
            if (trailing != null) ...[
              const SizedBox(width: FsSpace.sm),
              trailing!,
            ],
            if (selected) ...[
              const SizedBox(width: FsSpace.sm),
              Icon(CupertinoIcons.checkmark_alt, color: p.tint, size: 22),
            ] else if (showChevron) ...[
              const SizedBox(width: FsSpace.sm),
              Icon(
                CupertinoIcons.chevron_forward,
                color: p.tertiaryLabel,
                size: 17,
              ),
            ],
          ],
        ),
      ),
    );

    return Semantics(
      button: onTap != null,
      selected: selected,
      label: semanticLabel,
      child: onTap == null
          ? row
          : Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
                child: row,
              ),
            ),
    );
  }
}

/// Settings-style rounded-square icon.
class FsIconBadge extends StatelessWidget {
  const FsIconBadge(this.icon, {super.key, this.color, this.size = 30});
  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.fs.tint;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.6),
    );
  }
}
