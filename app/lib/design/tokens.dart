import 'package:flutter/material.dart';

/// EarthSync design tokens — warm, farm-friendly (team design, 15 Nov),
/// tuned for outdoor use.
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
  static const xl = 22.0; // hero and content cards
  static const sheet = 24.0;
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

/// Soft card shadows (the team design's floating white cards).
abstract final class FsShadow {
  static List<BoxShadow> card(FsPalette p) => [
    BoxShadow(color: p.shadow, blurRadius: 18, offset: const Offset(0, 6)),
  ];
  static List<BoxShadow> soft(FsPalette p) => [
    BoxShadow(color: p.shadow, blurRadius: 10, offset: const Offset(0, 3)),
  ];
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
    required this.heading,
    required this.sky,
    required this.skySoft,
    required this.shadow,
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
  final Color heading; // big titles (deep green)
  final Color sky, skySoft; // weather card gradient
  final Color shadow; // soft card shadow

  List<Color> get cropColors => [crop1, crop2, crop3, crop4];

  (Color text, Color bg) tone(FsTone t) => switch (t) {
    FsTone.positive => (positiveText, positiveBg),
    FsTone.caution => (cautionText, cautionBg),
    FsTone.negative => (negativeText, negativeBg),
    FsTone.neutral => (neutralText, neutralBg),
    FsTone.info => (infoText, infoBg),
  };

  static const light = FsPalette(
    background: Color(0xFFF7F4EA),
    surface: Color(0xFFFFFDF8),
    surfaceRaised: Color(0xFFFFFFFF),
    fill: Color(0xFFEDE9DC),
    fillStrong: Color(0xFFD5CFBD),
    separator: Color(0xFFE6E1D2),
    label: Color(0xFF1B2A1D),
    secondaryLabel: Color(0xFF56624F),
    tertiaryLabel: Color(0xFF858E7E),
    tint: Color(0xFF2E6B34),
    onTint: Color(0xFFFFFFFF),
    tintSoft: Color(0xFFE4F0DA),
    rain: Color(0xFF2F7FD0),
    heat: Color(0xFFC2410C),
    positiveText: Color(0xFF2F7D32),
    positiveBg: Color(0xFFE3F1DB),
    cautionText: Color(0xFFA35F00),
    cautionBg: Color(0xFFFFF0D2),
    negativeText: Color(0xFFA32222),
    negativeBg: Color(0xFFFCE6E2),
    neutralText: Color(0xFF3D463A),
    neutralBg: Color(0xFFEDEAE0),
    infoText: Color(0xFF1F5E99),
    infoBg: Color(0xFFE4EFFA),
    crop1: Color(0xFF2E6B34),
    crop2: Color(0xFF9A6B3F),
    crop3: Color(0xFF2F6FB3),
    crop4: Color(0xFF7A4FA8),
    barBackground: Color(0xF2F7F4EA),
    heading: Color(0xFF1E4D24),
    sky: Color(0xFFCFE5F8),
    skySoft: Color(0xFFEFF6FC),
    shadow: Color(0x1A3B3A1F),
  );

  static const dark = FsPalette(
    background: Color(0xFF0E1410),
    surface: Color(0xFF18211A),
    surfaceRaised: Color(0xFF1F2A21),
    fill: Color(0xFF263128),
    fillStrong: Color(0xFF3B483D),
    separator: Color(0xFF2B362D),
    label: Color(0xFFEEF3EA),
    secondaryLabel: Color(0xFFADB8A8),
    tertiaryLabel: Color(0xFF7F8B7C),
    tint: Color(0xFF6CC477),
    onTint: Color(0xFF0B2010),
    tintSoft: Color(0xFF1C3720),
    rain: Color(0xFF7DB8F2),
    heat: Color(0xFFFF9F5A),
    positiveText: Color(0xFF9BDDA2),
    positiveBg: Color(0xFF1C3720),
    cautionText: Color(0xFFFFC66E),
    cautionBg: Color(0xFF3A2B0E),
    negativeText: Color(0xFFFF9A9A),
    negativeBg: Color(0xFF3D1616),
    neutralText: Color(0xFFD3DAD0),
    neutralBg: Color(0xFF263128),
    infoText: Color(0xFF9CC8FF),
    infoBg: Color(0xFF12293F),
    crop1: Color(0xFF6CC477),
    crop2: Color(0xFFD1A06E),
    crop3: Color(0xFF6FA8EE),
    crop4: Color(0xFFB792E0),
    barBackground: Color(0xF20E1410),
    heading: Color(0xFFCFEBC9),
    sky: Color(0xFF1C3347),
    skySoft: Color(0xFF15232F),
    shadow: Color(0x66000000),
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
