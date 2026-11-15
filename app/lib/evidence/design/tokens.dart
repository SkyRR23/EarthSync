import 'package:flutter/material.dart';

/// Field Shift design tokens. See docs/flutter-design-system.md §2.
/// Widgets must use these instead of hardcoded colours or sizes.
abstract final class FsColors {
  // Brand
  static const primary = Color(0xFF21583D);
  static const forest = Color(0xFF173D30);
  static const leaf = Color(0xFFC8DFBF);
  static const harvest = Color(0xFFF4C96A);
  static const darkBackground = Color(0xFF101E18);
  static const darkSurface = Color(0xFF192A23);
  static const darkPrimary = Color(0xFFA4D5B8);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFFE2EDE3);
  static const earth = Color(0xFF7D664A);
  static const sky = Color(0xFF4385A4);

  // Neutral
  static const bg = Color(0xFFF7F5EF);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFDFE5DC);
  static const textPrimary = Color(0xFF1B2924);
  static const textSecondary = Color(0xFF53665B);

  // Feasibility
  static const supported = Color(0xFF286B52);
  static const constrained = Color(0xFFB26A00);
  static const unknown = Color(0xFF5F6368);

  // Risk
  static const riskHigh = Color(0xFFB64040);
  static const riskMedium = Color(0xFFB26A00);
  static const riskLow = Color(0xFF286B52);
  static const riskUnknown = Color(0xFF5F6368);

  // Evidence types
  static const evidenceObservation = Color(0xFF4385A4);
  static const evidenceModel = Color(0xFF6A1B9A);
  static const evidenceImagery = Color(0xFF00838F);
  static const evidenceReference = Color(0xFF7D664A);
  static const evidenceUnverified = Color(0xFF5F6368);
}

abstract final class FsLayout {
  static const compact = 600.0;
  static const rail = 900.0;
  static const content = 1160.0;
}

abstract final class FsSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
  static const gutter = 16.0;
  static const minTouch = 56.0;
}

abstract final class FsRadius {
  static const sm = Radius.circular(8);
  static const md = Radius.circular(12);
  static const lg = Radius.circular(16);
}

abstract final class FsMotion {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const curve = Curves.easeOutCubic;
}
