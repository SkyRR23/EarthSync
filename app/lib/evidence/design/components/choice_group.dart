import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/strings.dart';
import '../tokens.dart';

class FsChoice<T> {
  const FsChoice(this.value, this.label, [this.icon]);
  final T value;
  final String label;
  final IconData? icon;
}

/// Big tappable answer tiles. Always ends with a full-width "I don't know".
/// Use [columns] = 2 for long lists (crops, months) so everything fits
/// on one screen.
class FsChoiceGroup<T> extends StatelessWidget {
  const FsChoiceGroup({
    super.key,
    required this.choices,
    required this.unknownValue,
    required this.selected,
    required this.onChanged,
    this.multi = false,
    this.columns = 1,
  });

  final List<FsChoice<T>> choices;
  final T unknownValue;
  final Set<T> selected;
  final ValueChanged<Set<T>> onChanged;
  final bool multi;
  final int columns;

  void _tap(T v) {
    HapticFeedback.selectionClick();
    if (!multi || v == unknownValue) {
      onChanged({v});
      return;
    }
    final next = {...selected}..remove(unknownValue);
    next.contains(v) ? next.remove(v) : next.add(v);
    onChanged(next);
  }

  Widget _tile(FsChoice<T> c, {bool compact = false}) => _Tile(
    label: c.label,
    icon: c.icon,
    selected: selected.contains(c.value),
    multi: multi,
    compact: compact,
    onTap: () => _tap(c.value),
  );

  @override
  Widget build(BuildContext context) {
    final unknown = FsChoice<T>(unknownValue, S.dontKnow, Icons.help_outline);
    final rows = <Widget>[];
    if (columns <= 1) {
      for (final c in choices) {
        rows.add(_tile(c));
      }
    } else {
      for (var i = 0; i < choices.length; i += columns) {
        rows.add(
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var j = 0; j < columns; j++) ...[
                  if (j > 0) const SizedBox(width: FsSpace.sm),
                  Expanded(
                    child: i + j < choices.length
                        ? _tile(choices[i + j], compact: true)
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        );
      }
    }
    rows.add(_tile(unknown));

    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: FsSpace.sm),
            child: r,
          ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.multi,
    required this.compact,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final bool multi;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final mark = Icon(
      selected
          ? (multi ? Icons.check_box : Icons.check_circle)
          : (multi
                ? Icons.check_box_outline_blank
                : Icons.radio_button_unchecked),
      color: selected ? FsColors.primary : FsColors.border,
      size: compact ? 20 : 24,
    );
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? FsColors.primaryContainer : FsColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(FsRadius.md),
          side: BorderSide(
            color: selected ? FsColors.primary : FsColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: const BorderRadius.all(FsRadius.md),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: FsSpace.minTouch + 8),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? FsSpace.sm + 4 : FsSpace.md,
                vertical: FsSpace.sm,
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      color: selected
                          ? FsColors.primary
                          : FsColors.textSecondary,
                      size: compact ? 22 : 24,
                    ),
                    SizedBox(width: compact ? FsSpace.sm : FsSpace.md),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      style: compact ? t.bodyMedium : t.bodyLarge,
                    ),
                  ),
                  const SizedBox(width: FsSpace.xs),
                  mark,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
