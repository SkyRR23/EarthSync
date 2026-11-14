import 'package:flutter/material.dart';

/// Field Shift design tokens — Apple-style, tuned for outdoor use.
/// Colours come from [FsPalette] (light/dark aware); read them with
/// `context.fs`. Never hardcode colours or sizes in widgets.

/// Spacing on a 4-pt grid.
abstract final class FsSpace {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
  static const huge = 44.0;

  /// Side margin for full-width content and inset grouped lists.
  static const gutter = 16.0;

  /// Minimum tap target. Apple's minimum is 44; larger for field use.
  static const minTouch = 50.0;

  /// Max readable content width on tablets / desktop.
  static const maxContent = 680.0;

  /// Width from which results use a sidebar instead of a tab bar.
  static const wideBreakpoint = 720.0;
}

abstract final class FsRadius {
  static const xs = 6.0;
  static const sm = 8.0;
  static const md = 12.0; // grouped sections, tiles
  static const lg = 16.0;
  static const sheet = 20.0;
  static const capsule = 999.0;
}

abstract final class FsMotion {
  static const fast = Duration(milliseconds: 140);
  static const normal = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 420);
  static const curve = Curves.easeOutCubic;
  static const spring = Curves.easeOutBack;

  /// Zero when the user asked the OS to reduce motion.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.of(context).disableAnimations ? Duration.zero : d;
}

/// Soft status tones used for capsule labels and banners.
enum FsTone { positive, caution, negative, neutral, info }

/// Colour roles. Light values follow Apple's grouped-list palette with
/// darker secondary text for sunlight readability.
@immutable
class FsPalette extends ThemeExtension<FsPalette> {
  const FsPalette({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.fill,
    required this.fillStrong,
    required this.separator,
    required this.label,
    required this.secondaryLabel,
    required this.tertiaryLabel,
    required this.tint,
    required this.onTint,
    required this.tintSoft,
    required this.rain,
    required this.heat,
    required this.positiveText,
    required this.positiveBg,
    required this.cautionText,
    required this.cautionBg,
    required this.negativeText,
    required this.negativeBg,
    required this.neutralText,
    required this.neutralBg,
    required this.infoText,
    required this.infoBg,
    required this.crop1,
    required this.crop2,
    required this.crop3,
    required this.crop4,
    required this.barBackground,
  });

  final Color background; // grouped page background
  final Color surface; // grouped section / card
  final Color surfaceRaised; // sheets, floating controls
  final Color fill; // segmented track, pressed rows
  final Color fillStrong; // borders of controls
  final Color separator; // hairlines
  final Color label;
  final Color secondaryLabel;
  final Color tertiaryLabel;
  final Color tint; // the one accent: everything tappable
  final Color onTint;
  final Color tintSoft;
  final Color rain;
  final Color heat;
  final Color positiveText, positiveBg;
  final Color cautionText, cautionBg;
  final Color negativeText, negativeBg;
  final Color neutralText, neutralBg;
  final Color infoText, infoBg;
  final Color crop1, crop2, crop3, crop4; // timeline categories
  final Color barBackground; // translucent nav / tab bars

  List<Color> get cropColors => [crop1, crop2, crop3, crop4];

  (Color text, Color bg) tone(FsTone t) => switch (t) {
    FsTone.positive => (positiveText, positiveBg),
    FsTone.caution => (cautionText, cautionBg),
    FsTone.negative => (negativeText, negativeBg),
    FsTone.neutral => (neutralText, neutralBg),
    FsTone.info => (infoText, infoBg),
  };

  static const light = FsPalette(
    background: Color(0xFFF2F2F7),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    fill: Color(0xFFE9E9EE),
    fillStrong: Color(0xFFD1D1D6),
    separator: Color(0xFFD8D8DC),
    label: Color(0xFF1C1C1E),
    secondaryLabel: Color(0xFF5C5C61),
    tertiaryLabel: Color(0xFF8A8A8E),
    tint: Color(0xFF1E7B4F),
    onTint: Color(0xFFFFFFFF),
    tintSoft: Color(0xFFE3F4EA),
    rain: Color(0xFF0A60C2),
    heat: Color(0xFFC2410C),
    positiveText: Color(0xFF14532D),
    positiveBg: Color(0xFFE3F4EA),
    cautionText: Color(0xFF7A4A00),
    cautionBg: Color(0xFFFFF1D6),
    negativeText: Color(0xFF9F1D1D),
    negativeBg: Color(0xFFFDE8E8),
    neutralText: Color(0xFF3A3A3C),
    neutralBg: Color(0xFFEDEDF0),
    infoText: Color(0xFF0B4A8F),
    infoBg: Color(0xFFE5F0FC),
    crop1: Color(0xFF1E7B4F),
    crop2: Color(0xFF9A6B3F),
    crop3: Color(0xFF2F6FB3),
    crop4: Color(0xFF7A4FA8),
    barBackground: Color(0xEFF9F9FB),
  );

  static const dark = FsPalette(
    background: Color(0xFF000000),
    surface: Color(0xFF1C1C1E),
    surfaceRaised: Color(0xFF2C2C2E),
    fill: Color(0xFF2C2C2E),
    fillStrong: Color(0xFF48484A),
    separator: Color(0xFF38383A),
    label: Color(0xFFFFFFFF),
    secondaryLabel: Color(0xFFAEAEB2),
    tertiaryLabel: Color(0xFF8E8E93),
    tint: Color(0xFF3CCB82),
    onTint: Color(0xFF00210F),
    tintSoft: Color(0xFF12351F),
    rain: Color(0xFF64A8FF),
    heat: Color(0xFFFF9F5A),
    positiveText: Color(0xFF8FE3B3),
    positiveBg: Color(0xFF12351F),
    cautionText: Color(0xFFFFC56B),
    cautionBg: Color(0xFF3A2A0C),
    negativeText: Color(0xFFFF9A9A),
    negativeBg: Color(0xFF3D1414),
    neutralText: Color(0xFFD1D1D6),
    neutralBg: Color(0xFF2C2C2E),
    infoText: Color(0xFF9CC8FF),
    infoBg: Color(0xFF0E2A4A),
    crop1: Color(0xFF3CCB82),
    crop2: Color(0xFFD1A06E),
    crop3: Color(0xFF6FA8EE),
    crop4: Color(0xFFB792E0),
    barBackground: Color(0xE61C1C1E),
  );

  @override
  FsPalette copyWith() => this;

  @override
  FsPalette lerp(ThemeExtension<FsPalette>? other, double t) =>
      other is FsPalette && t >= 0.5 ? other : this;
}

extension FsContext on BuildContext {
  FsPalette get fs => Theme.of(this).extension<FsPalette>() ?? FsPalette.light;
  TextTheme get type => Theme.of(this).textTheme;
  bool get reduceMotion => MediaQuery.of(this).disableAnimations;
}

/// Apple text-style names over Material's TextTheme slots.
extension FsTextStyles on TextTheme {
  TextStyle get largeTitle => displaySmall!; // 34 bold
  TextStyle get title1 => headlineMedium!; // 28 bold
  TextStyle get title2 => headlineSmall!; // 22 bold
  TextStyle get title3 => titleLarge!; // 20 semibold
  TextStyle get headline => titleMedium!; // 17 semibold
  TextStyle get body => bodyLarge!; // 17
  TextStyle get callout => bodyMedium!; // 16
  TextStyle get subhead => labelMedium!; // 15
  TextStyle get footnote => bodySmall!; // 13
  TextStyle get caption => labelSmall!; // 12
}
