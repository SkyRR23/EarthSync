import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Theme;

import '../tokens.dart';

/// iOS sliding segmented control with the app's palette and type.
class FsSegmented<T extends Object> extends StatelessWidget {
  const FsSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  final Map<T, String> segments;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    return SizedBox(
      width: double.infinity,
      child: CupertinoSlidingSegmentedControl<T>(
        groupValue: value,
        backgroundColor: p.fill,
        // Dark: lift the thumb above the track (Apple uses a lighter grey).
        thumbColor: Theme.of(context).brightness == Brightness.dark
            ? p.fillStrong
            : p.surfaceRaised,
        padding: const EdgeInsets.all(3),
        onValueChanged: (v) {
          if (v != null) onChanged(v);
        },
        children: {
          for (final e in segments.entries)
            e.key: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: FsSpace.sm,
                horizontal: FsSpace.xs,
              ),
              child: Text(
                e.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.type.subhead.copyWith(
                  fontWeight: e.key == value
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: p.label,
                ),
              ),
            ),
        },
      ),
    );
  }
}
