import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../app/strings.dart';
import '../tokens.dart';
import 'grouped.dart';
import 'pressable.dart';

class FsChoice<T> {
  const FsChoice(this.value, this.label, [this.icon]);
  final T value;
  final String label;
  final IconData? icon;
}

Set<T> _toggle<T>(Set<T> selected, T v, T unknown, bool multi) {
  if (!multi || v == unknown) return {v};
  final next = {...selected}..remove(unknown);
  next.contains(v) ? next.remove(v) : next.add(v);
  return next;
}

/// Grouped list of answers with checkmarks (iOS Settings style), plus a
/// separate "Not sure?" section holding "I don't know".
class FsChoiceList<T> extends StatelessWidget {
  const FsChoiceList({
    super.key,
    required this.choices,
    required this.unknownValue,
    required this.selected,
    required this.onChanged,
    this.header,
    this.multi = false,
  });

  final List<FsChoice<T>> choices;
  final T unknownValue;
  final Set<T> selected;
  final ValueChanged<Set<T>> onChanged;
  final String? header;
  final bool multi;

  Widget _row(BuildContext context, FsChoice<T> c) {
    final p = context.fs;
    final on = selected.contains(c.value);
    return FsListRow(
      leading: c.icon == null
          ? null
          : Icon(c.icon, color: on ? p.tint : p.secondaryLabel, size: 22),
      title: c.label,
      titleStyle: on
          ? context.type.body.copyWith(fontWeight: FontWeight.w600)
          : null,
      selected: !multi && on,
      chevron: false,
      trailing: multi
          ? Icon(
              on ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
              color: on ? p.tint : p.fillStrong,
              size: 24,
            )
          : null,
      onTap: () => onChanged(_toggle(selected, c.value, unknownValue, multi)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final indent = choices.any((c) => c.icon != null)
        ? FsSpace.lg + 22 + FsSpace.md
        : FsSpace.lg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FsGroupedSection(
          header: header,
          separatorIndent: indent,
          children: [for (final c in choices) _row(context, c)],
        ),
        FsGroupedSection(

          separatorIndent: indent,
          children: [
            _row(
              context,
              FsChoice(
                unknownValue,
                S.dontKnow,
                CupertinoIcons.question_circle,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Grid of capsule chips for short, numerous options (months).
class FsChoiceGrid<T> extends StatelessWidget {
  const FsChoiceGrid({
    super.key,
    required this.choices,
    required this.unknownValue,
    required this.selected,
    required this.onChanged,
    this.header,
    this.columns = 3,
  });

  final List<FsChoice<T>> choices;
  final T unknownValue;
  final Set<T> selected;
  final ValueChanged<Set<T>> onChanged;
  final String? header;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final rows = <Widget>[];
    for (var i = 0; i < choices.length; i += columns) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: FsSpace.sm),
          child: Row(
            children: [
              for (var j = 0; j < columns; j++) ...[
                if (j > 0) const SizedBox(width: FsSpace.sm),
                Expanded(
                  child: i + j < choices.length
                      ? _Chip(
                          label: choices[i + j].label,
                          selected: selected.contains(choices[i + j].value),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onChanged({choices[i + j].value});
                          },
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FsSpace.gutter,
            FsSpace.xxl,
            FsSpace.gutter,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (header != null)
                Padding(
                  padding: const EdgeInsets.only(
                    left: FsSpace.lg,
                    bottom: FsSpace.sm - 1,
                  ),
                  child: Text(
                    header!.toUpperCase(),
                    style: context.type.footnote.copyWith(letterSpacing: 0.4),
                  ),
                ),
              ...rows,
            ],
          ),
        ),
        FsGroupedSection(

          separatorIndent: FsSpace.lg + 22 + FsSpace.md,
          children: [
            FsListRow(
              leading: Icon(
                CupertinoIcons.question_circle,
                color: selected.contains(unknownValue)
                    ? p.tint
                    : p.secondaryLabel,
              ),
              title: S.dontKnow,
              selected: selected.contains(unknownValue),
              chevron: false,
              onTap: () => onChanged({unknownValue}),
            ),
          ],
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    return Semantics(
      selected: selected,
      child: FsPressable(
        onTap: onTap,
        semanticLabel: label,
        haptic: false,
        child: AnimatedContainer(
          duration: FsMotion.of(context, FsMotion.fast),
          height: FsSpace.minTouch,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? p.tint : p.surface,
            borderRadius: BorderRadius.circular(FsRadius.md),
          ),
          child: Text(
            label,
            style: context.type.headline.copyWith(
              color: selected ? p.onTint : p.label,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
