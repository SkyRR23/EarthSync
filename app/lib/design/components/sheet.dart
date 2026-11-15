import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app/strings.dart';
import '../tokens.dart';

/// Apple-style sheet: grabber, title, Done, grouped background.
Future<T?> showFsSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
}) {
  final p = context.fs;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: p.background,
    builder: (ctx) {
      final maxH = MediaQuery.sizeOf(ctx).height * 0.86;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: FsSpace.maxContent),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    FsSpace.xl,
                    0,
                    FsSpace.sm,
                    0,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(title, style: ctx.type.title3),
                        ),
                      ),
                      CupertinoButton(
                        minimumSize: const Size.square(FsSpace.minTouch),
                        padding: const EdgeInsets.symmetric(
                          horizontal: FsSpace.md,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text(
                          S.done,
                          style: ctx.type.headline.copyWith(color: p.tint),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: FsSpace.xxxl),
                    child: builder(ctx),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
