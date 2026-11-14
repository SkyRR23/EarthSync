import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../tokens.dart';
import 'pressable.dart';

/// Compact inline notice (one line, optional tap for details).
class FsBanner extends StatelessWidget {
  const FsBanner({
    super.key,
    required this.message,
    this.tone = FsTone.info,
    this.icon,
    this.detail,
    this.onTap,
  });

  final String message;
  final String? detail;
  final FsTone tone;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = context.fs.tone(tone);
    final body = Container(
      margin: const EdgeInsets.symmetric(horizontal: FsSpace.gutter),
      padding: const EdgeInsets.symmetric(
        horizontal: FsSpace.md + 2,
        vertical: FsSpace.md - 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(FsRadius.md),
      ),
      child: Row(
        children: [
          Icon(icon ?? CupertinoIcons.info_circle_fill, size: 18, color: fg),
          const SizedBox(width: FsSpace.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: context.type.subhead.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (detail != null)
                  Text(
                    detail!,
                    style: context.type.footnote.copyWith(color: fg),
                  ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(CupertinoIcons.chevron_forward, size: 15, color: fg),
        ],
      ),
    );
    return onTap == null
        ? Semantics(container: true, child: body)
        : FsPressable(
            onTap: onTap,
            semanticLabel: message,
            scale: 0.98,
            child: body,
          );
  }
}

/// Full-screen message: error, empty, or confirmation.
class FsMessageView extends StatelessWidget {
  const FsMessageView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.tone = FsTone.neutral,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final String message;
  final FsTone tone;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = context.fs.tone(tone);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(FsSpace.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                child: Icon(icon, size: 34, color: fg),
              ),
              const SizedBox(height: FsSpace.xl),
              Text(
                title,
                textAlign: TextAlign.center,
                style: context.type.title2,
              ),
              const SizedBox(height: FsSpace.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: context.type.body.copyWith(
                  color: context.fs.secondaryLabel,
                ),
              ),
              const SizedBox(height: FsSpace.xxl),
              for (final a in actions)
                Padding(
                  padding: const EdgeInsets.only(bottom: FsSpace.sm),
                  child: a,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Step list that advances while work runs ("Reading… → Checking… → …").
class FsProgressSteps extends StatefulWidget {
  const FsProgressSteps({
    super.key,
    required this.steps,
    this.interval = const Duration(milliseconds: 650),
  });

  final List<String> steps;
  final Duration interval;

  @override
  State<FsProgressSteps> createState() => _FsProgressStepsState();
}

class _FsProgressStepsState extends State<FsProgressSteps> {
  int _current = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) {
      if (_current < widget.steps.length - 1) {
        setState(() => _current++);
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    return Semantics(
      liveRegion: true,
      label: widget.steps[_current],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < widget.steps.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: FsSpace.sm),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: AnimatedSwitcher(
                      duration: FsMotion.of(context, FsMotion.normal),
                      child: i < _current
                          ? Icon(
                              CupertinoIcons.checkmark_circle_fill,
                              key: const ValueKey('done'),
                              color: p.tint,
                              size: 22,
                            )
                          : i == _current
                          ? const CupertinoActivityIndicator(
                              key: ValueKey('run'),
                            )
                          : Icon(
                              CupertinoIcons.circle,
                              key: const ValueKey('todo'),
                              color: p.fillStrong,
                              size: 22,
                            ),
                    ),
                  ),
                  const SizedBox(width: FsSpace.md),
                  AnimatedDefaultTextStyle(
                    duration: FsMotion.of(context, FsMotion.normal),
                    style: context.type.body.copyWith(
                      color: i <= _current ? p.label : p.tertiaryLabel,
                    ),
                    child: Text(widget.steps[i]),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Shimmering placeholder block for loading layouts.
class FsSkeleton extends StatefulWidget {
  const FsSkeleton({super.key, this.height = 16, this.width, this.radius = 6});
  final double height;
  final double? width;
  final double radius;

  @override
  State<FsSkeleton> createState() => _FsSkeletonState();
}

class _FsSkeletonState extends State<FsSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    return ExcludeSemantics(
      child: FadeTransition(
        opacity: Tween(
          begin: 0.45,
          end: 1.0,
        ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
        child: Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            color: p.fill,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      ),
    );
  }
}

/// Health-style metric tile: icon + label, big value.
class FsMetricTile extends StatelessWidget {
  const FsMetricTile({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(FsSpace.lg - 2),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(FsRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: FsSpace.xs + 2),
                Flexible(
                  child: Text(
                    label,
                    style: context.type.footnote.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: FsSpace.sm),
            Text(value, style: context.type.title2),
          ],
        ),
      ),
    );
  }
}
