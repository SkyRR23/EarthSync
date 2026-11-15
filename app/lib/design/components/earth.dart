import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../features/map/gibs_layer.dart';
import '../tokens.dart';
import 'pressable.dart';

/// Building blocks of the EarthSync team design (15 Nov): floating cream
/// cards, pill chips, status pills, an animated ring and bar, staggered
/// entrance motion and a satellite picture of the farm.

/// Floating rounded card with a soft shadow; tappable when [onTap] is set.
class FsCard extends StatelessWidget {
  const FsCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(FsSpace.lg),
    this.margin = const EdgeInsets.fromLTRB(
      FsSpace.gutter,
      FsSpace.md,
      FsSpace.gutter,
      0,
    ),
    this.color,
    this.radius = FsRadius.xl,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? color;
  final double radius;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? p.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: FsShadow.card(p),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
    return Padding(
      padding: margin,
      child: onTap == null
          ? card
          : FsPressable(
              onTap: onTap,
              scale: 0.985,
              semanticLabel: semanticLabel,
              child: card,
            ),
    );
  }
}

/// Section heading in the design ("Your fields", "5-Day Forecast").
class FsSectionTitle extends StatelessWidget {
  const FsSectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      FsSpace.gutter + FsSpace.xxs,
      FsSpace.xxl,
      FsSpace.gutter,
      FsSpace.xs,
    ),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              text,
              style: context.type.title2.copyWith(fontSize: 21),
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// White pill with a pin, the place name and a chevron.
class FsLocationChip extends StatelessWidget {
  const FsLocationChip({super.key, required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    return FsPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          FsSpace.md,
          FsSpace.sm + 2,
          FsSpace.md,
          FsSpace.sm + 2,
        ),
        decoration: BoxDecoration(
          color: p.surfaceRaised,
          borderRadius: BorderRadius.circular(FsRadius.capsule),
          boxShadow: FsShadow.soft(p),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.location_solid, size: 20, color: p.label),
            const SizedBox(width: FsSpace.sm),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.type.headline,
              ),
            ),
            const SizedBox(width: FsSpace.sm),
            Icon(CupertinoIcons.chevron_down, size: 16, color: p.label),
          ],
        ),
      ),
    );
  }
}

enum FsPillTone { good, look, info }

/// "✓ Good" / "⚠ Needs a look" pill.
class FsStatusPill extends StatelessWidget {
  const FsStatusPill(this.label, {super.key, this.tone = FsPillTone.good});
  final String label;
  final FsPillTone tone;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final (fg, bg, icon) = switch (tone) {
      FsPillTone.good => (
        p.positiveText,
        p.positiveBg,
        CupertinoIcons.checkmark_circle_fill,
      ),
      FsPillTone.look => (
        p.cautionText,
        p.cautionBg,
        CupertinoIcons.exclamationmark_triangle_fill,
      ),
      FsPillTone.info => (
        p.infoText,
        p.infoBg,
        CupertinoIcons.info_circle_fill,
      ),
    };
    return AnimatedContainer(
      duration: FsMotion.of(context, FsMotion.normal),
      padding: const EdgeInsets.symmetric(
        horizontal: FsSpace.sm + 2,
        vertical: FsSpace.xs + 1,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(FsRadius.capsule),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: FsSpace.xs + 1),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.type.subhead.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "✓ Saved on this phone" (two short lines, like the design).
class FsSavedBadge extends StatelessWidget {
  const FsSavedBadge(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          CupertinoIcons.checkmark_circle_fill,
          size: 22,
          color: p.positiveText,
        ),
        const SizedBox(width: FsSpace.xs + 2),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 96),
          child: Text(
            text,
            maxLines: 2,
            style: context.type.footnote.copyWith(
              color: p.secondaryLabel,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

/// Fades and slides a block in on first show; [index] staggers a list.
/// No timers (one controller per block), and none at all with reduced motion.
class FsEntrance extends StatefulWidget {
  const FsEntrance({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;

  @override
  State<FsEntrance> createState() => _FsEntranceState();
}

class _FsEntranceState extends State<FsEntrance>
    with SingleTickerProviderStateMixin {
  static const _step = 70, _run = 420;
  late final int _delay = math.min(widget.index, 6) * _step;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _delay + _run),
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Interval(_delay / (_delay + _run), 1, curve: FsMotion.curve),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _c.value = 1;
    } else if (!_c.isAnimating && _c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    child: widget.child,
    builder: (_, child) => Opacity(
      opacity: _t.value,
      child: Transform.translate(
        offset: Offset(0, (1 - _t.value) * 18),
        child: child,
      ),
    ),
  );
}

/// Ring that fills to [value] (0..1) when shown, with [child] in the middle.
class FsProgressRing extends StatelessWidget {
  const FsProgressRing({
    super.key,
    required this.value,
    required this.child,
    this.size = 76,
    this.stroke = 7,
    this.color,
  });
  final double value;
  final Widget child;
  final double size, stroke;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0, 1)),
      duration: FsMotion.of(context, const Duration(milliseconds: 900)),
      curve: FsMotion.curve,
      builder: (_, v, _) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(
            v,
            color ?? p.positiveText,
            p.surfaceRaised,
            stroke,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.color, this.track, this.stroke);
  final double v, stroke;
  final Color color, track;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.shortestSide - stroke) / 2;
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, r + stroke / 2, Paint()..color = track);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, paint..color = color.withValues(alpha: 0.18));
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * v,
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.color != color;
}

/// Rounded bar that grows to [value] (0..1) when shown.
class FsProgressBar extends StatelessWidget {
  const FsProgressBar({super.key, required this.value, this.color});
  final double value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    return ClipRRect(
      borderRadius: BorderRadius.circular(FsRadius.capsule),
      child: Container(
        height: 12,
        color: p.surfaceRaised.withValues(alpha: 0.85),
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.clamp(0, 1)),
          duration: FsMotion.of(context, const Duration(milliseconds: 900)),
          curve: FsMotion.curve,
          builder: (_, v, _) => FractionallySizedBox(
            widthFactor: v,
            child: Container(
              decoration: BoxDecoration(
                color: color ?? p.positiveText,
                borderRadius: BorderRadius.circular(FsRadius.capsule),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Satellite picture of the farm (not interactive), with its border when
/// the farmer marked the corners.
class FarmPicture extends StatefulWidget {
  const FarmPicture({
    super.key,
    required this.center,
    this.corners,
    this.zoom = 16,
    this.borderColor,
  });
  final LatLng center;
  final List<LatLng>? corners;
  final double zoom;
  final Color? borderColor;

  @override
  State<FarmPicture> createState() => _FarmPictureState();
}

class _FarmPictureState extends State<FarmPicture> {
  final _map = MapController();

  List<LatLng>? get _shape =>
      widget.corners != null && widget.corners!.length >= 3
      ? widget.corners
      : null;

  CameraFit? get _fit => _shape == null
      ? null
      : CameraFit.coordinates(
          coordinates: _shape!,
          padding: const EdgeInsets.all(14),
          maxZoom: 17,
        );

  /// Fit, then nudge so the first tiles are drawn (see [nudgeMap]).
  void _ready() {
    try {
      final fit = _fit;
      if (fit != null) _map.fitCamera(fit);
    } catch (_) {
      // Not laid out yet; the initial camera still applies.
    }
    nudgeMap(_map);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final shape = _shape;
    final line = widget.borderColor ?? const Color(0xFF8BE07E);
    return IgnorePointer(
      child: ColoredBox(
        color: const Color(0xFF4F6B3A),
        child: FlutterMap(
          mapController: _map,
          options: MapOptions(
            onMapReady: _ready,
            initialCenter: widget.center,
            initialZoom: widget.zoom,
            initialCameraFit: _fit,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
            backgroundColor: p.fill,
          ),
          children: [
            satelliteTileLayer(),
            if (shape != null)
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: shape,
                    color: line.withValues(alpha: 0.22),
                    borderColor: line,
                    borderStrokeWidth: 2.5,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
