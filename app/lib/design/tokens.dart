import 'package:flutter/material.dart';

/// Field Shift design tokens. See docs/flutter-design-system.md §2.
/// Widgets must use these instead of hardcoded colours or sizes.
abstract final class FsColors {
  // Brand
  static const primary = Color(0xFF2E7D32);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFFC8E6C9);
  static const earth = Color(0xFF6D4C41);
  static const sky = Color(0xFF1565C0);

  // Neutral
  static const bg = Color(0xFFFAFAF7);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFD6D6CF);
  static const textPrimary = Color(0xFF1B1B18);
  static const textSecondary = Color(0xFF4A4A44);

  // Feasibility
  static const supported = Color(0xFF2E7D32);
  static const constrained = Color(0xFFB26A00);
  static const unknown = Color(0xFF5F6368);

  // Risk
  static const riskHigh = Color(0xFFC62828);
  static const riskMedium = Color(0xFFB26A00);
  static const riskLow = Color(0xFF2E7D32);
  static const riskUnknown = Color(0xFF5F6368);

  // Evidence types
  static const evidenceObservation = Color(0xFF1565C0);
  static const evidenceModel = Color(0xFF6A1B9A);
  static const evidenceImagery = Color(0xFF00838F);
  static const evidenceReference = Color(0xFF6D4C41);
  static const evidenceUnverified = Color(0xFF5F6368);
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
