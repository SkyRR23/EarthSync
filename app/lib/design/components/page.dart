import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app/strings.dart';
import '../tokens.dart';

/// Standard screen: iOS navigation bar (large collapsing title by default),
/// grouped background, content centred and width-limited on tablets,
/// optional translucent bottom bar for the primary action.
class FsPage extends StatelessWidget {
  const FsPage({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.trailing,
    this.bottomBar,
    this.largeTitle = true,
    this.showBack = true,
    this.navMiddle,
    this.below,
  });

  /// Large title (or plain bar title when [largeTitle] is false).
  final String title;
  final List<Widget> children;
  final String? subtitle;
  final Widget? trailing;
  final Widget? bottomBar;
  final bool largeTitle;
  final bool showBack;

  /// Small centred bar text when [largeTitle] is false (defaults to [title]).
  final String? navMiddle;

  /// Pinned under the nav bar (e.g. a progress bar).
  final PreferredSizeWidget? below;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    // Team design: no hairline under the bar; it melts into the page.
    const border = Border();
    final back = showBack && Navigator.of(context).canPop()
        ? FsBackArrow(onTap: () => Navigator.of(context).maybePop())
        : null;

    final content = SliverLayoutBuilder(
      builder: (ctx, constraints) {
        final extra = math.max(
          0.0,
          (constraints.crossAxisExtent - FsSpace.maxContent) / 2,
        );
        return SliverPadding(
          padding: EdgeInsets.only(
            left: extra,
            right: extra,
            bottom: FsSpace.xxxl + MediaQuery.paddingOf(ctx).bottom,
          ),
          sliver: SliverList.list(
            children: [
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    FsSpace.gutter + FsSpace.xs,
                    0,
                    FsSpace.gutter,
                    0,
                  ),
                  child: Text(
                    subtitle!,
                    style: ctx.type.subhead.copyWith(color: p.secondaryLabel),
                  ),
                ),
              ...children,
            ],
          ),
        );
      },
    );

    if (largeTitle) {
      return Scaffold(
        backgroundColor: p.background,
        body: CustomScrollView(
          slivers: [
            CupertinoSliverNavigationBar(
              largeTitle: Text(title),
              trailing: trailing,
              leading: back,
              automaticallyImplyLeading: false,
              backgroundColor: p.barBackground,
              border: border,
              transitionBetweenRoutes: false,
              heroTag: 'nav-$title',
            ),
            if (below != null)
              SliverPersistentHeader(pinned: true, delegate: _Pinned(below!)),
            content,
          ],
        ),
        bottomNavigationBar: bottomBar == null
            ? null
            : FsBottomBar(child: bottomBar!),
      );
    }

    return Scaffold(
      backgroundColor: p.background,
      appBar: CupertinoNavigationBar(
        middle: Text(navMiddle ?? title),
        trailing: trailing,
        leading: back,
        automaticallyImplyLeading: false,
        backgroundColor: p.barBackground,
        border: border,
        transitionBetweenRoutes: false,
        heroTag: 'bar-$title',
        bottom: below,
      ),
      body: CustomScrollView(slivers: [content]),
      bottomNavigationBar: bottomBar == null
          ? null
          : FsBottomBar(child: bottomBar!),
    );
  }
}

class _Pinned extends SliverPersistentHeaderDelegate {
  _Pinned(this.child);
  final PreferredSizeWidget child;

  @override
  double get minExtent => child.preferredSize.height;
  @override
  double get maxExtent => child.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      child;

  @override
  bool shouldRebuild(_Pinned old) => old.child != child;
}

/// Translucent, blurred bar pinned to the bottom (primary actions).
class FsBottomBar extends StatelessWidget {
  const FsBottomBar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: p.barBackground,
            border: Border(top: BorderSide(color: p.separator, width: 0.5)),
          ),
          child: SafeArea(
            top: false,
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: FsSpace.maxContent),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    FsSpace.gutter,
                    FsSpace.md,
                    FsSpace.gutter,
                    FsSpace.md,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin progress line used under the bar on question screens.
class FsProgressLine extends StatelessWidget implements PreferredSizeWidget {
  const FsProgressLine(this.value, {super.key, this.semanticLabel});
  final double value;
  final String? semanticLabel;

  @override
  Size get preferredSize => const Size.fromHeight(3);

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    return Semantics(
      label: semanticLabel,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: value),
        duration: FsMotion.of(context, FsMotion.normal),
        curve: FsMotion.curve,
        builder: (_, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: 3,
          color: p.tint,
          backgroundColor: p.fill,
        ),
      ),
    );
  }
}

/// The team design's back control: a plain arrow.
class FsBackArrow extends StatelessWidget {
  const FsBackArrow({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: S.back,
    child: CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size.square(FsSpace.minTouch),
      onPressed: onTap,
      child: Icon(
        CupertinoIcons.arrow_left,
        size: 26,
        color: context.fs.heading,
      ),
    ),
  );
}
