import 'package:flutter/cupertino.dart';

import '../tokens.dart';
import 'pressable.dart';

/// One big picture answer: emoji + 1–3 words.
class FsPicture<T> {
  const FsPicture(this.value, this.emoji, this.label);
  final T value;
  final String emoji;
  final String label;
}

/// Big picture tiles in a grid — the farmer taps a picture, not a list row.
/// An optional "Not sure" tile spans the full width under the grid.
class FsPictureGrid<T> extends StatelessWidget {
  const FsPictureGrid({
    super.key,
    required this.choices,
    required this.selected,
    required this.onSelect,
    this.unsure,
    this.columns = 2,
    this.tileHeight = 112,
  });

  final List<FsPicture<T>> choices;
  final T? selected;
  final ValueChanged<T> onSelect;
  final FsPicture<T>? unsure;
  final int columns;
  final double tileHeight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FsSpace.gutter,
        FsSpace.lg,
        FsSpace.gutter,
        0,
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = ((box.maxWidth - FsSpace.sm * (columns - 1)) / columns)
              .clamp(0.0, double.infinity);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: FsSpace.sm,
                runSpacing: FsSpace.sm,
                children: [
                  for (final c in choices)
                    SizedBox(
                      width: w,
                      child: FsPictureTile(
                        emoji: c.emoji,
                        label: c.label,
                        selected: c.value == selected,
                        height: tileHeight,
                        onTap: () => onSelect(c.value),
                      ),
                    ),
                ],
              ),
              if (unsure != null) ...[
                const SizedBox(height: FsSpace.sm),
                FsPictureTile(
                  emoji: unsure!.emoji,
                  label: unsure!.label,
                  selected: unsure!.value == selected,
                  height: 64,
                  horizontal: true,
                  onTap: () => onSelect(unsure!.value),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class FsPictureTile extends StatelessWidget {
  const FsPictureTile({
    super.key,
    required this.emoji,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.height = 112,
    this.horizontal = false,
  });

  final String emoji;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final double height;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    final text = Text(
      label,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: t.headline.copyWith(color: selected ? p.tint : p.label),
    );
    final emojiText = Text(
      emoji,
      style: TextStyle(fontSize: horizontal ? 26 : 40, height: 1.1),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: FsPressable(
        onTap: onTap,
        scale: 0.96,
        child: AnimatedContainer(
          duration: FsMotion.of(context, FsMotion.fast),
          constraints: BoxConstraints(minHeight: height),
          padding: const EdgeInsets.symmetric(
            horizontal: FsSpace.sm,
            vertical: FsSpace.md,
          ),
          decoration: BoxDecoration(
            color: selected ? p.tintSoft : p.surface,
            borderRadius: BorderRadius.circular(FsRadius.lg),
            border: Border.all(
              color: selected ? p.tint : p.separator.withValues(alpha: 0.6),
              width: selected ? 2.5 : 1,
            ),
            boxShadow: selected ? null : FsShadow.soft(p),
          ),
          child: horizontal
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    emojiText,
                    const SizedBox(width: FsSpace.md),
                    Flexible(child: text),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    emojiText,
                    const SizedBox(height: FsSpace.sm),
                    text,
                  ],
                ),
        ),
      ),
    );
  }
}
