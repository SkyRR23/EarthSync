import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';

/// Apple-style press feedback: a gentle scale + dim instead of a ripple.
/// Keyboard-activatable (Enter/Space) and announced as a button.
class FsPressable extends StatefulWidget {
  const FsPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.scale = 0.97,
    this.semanticLabel,
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final String? semanticLabel;
  final bool haptic;

  @override
  State<FsPressable> createState() => _FsPressableState();
}

class _FsPressableState extends State<FsPressable> {
  bool _down = false;
  bool _focused = false;

  bool get _enabled => widget.onTap != null;

  void _activate() {
    if (!_enabled) return;
    if (widget.haptic) HapticFeedback.lightImpact();
    widget.onTap!();
  }

  void _setDown(bool v) {
    if (_enabled && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = context.reduceMotion;
    final duration = FsMotion.of(context, FsMotion.fast);
    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: _enabled,
        onShowFocusHighlight: (f) => setState(() => _focused = f),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setDown(true),
          onTapUp: (_) => _setDown(false),
          onTapCancel: () => _setDown(false),
          onTap: _enabled ? _activate : null,
          child: AnimatedScale(
            scale: _down && !reduce ? widget.scale : 1,
            duration: duration,
            curve: FsMotion.curve,
            child: AnimatedOpacity(
              opacity: _down ? 0.82 : 1,
              duration: duration,
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(FsRadius.md),
                  border: _focused
                      ? Border.all(color: context.fs.tint, width: 2)
                      : null,
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
