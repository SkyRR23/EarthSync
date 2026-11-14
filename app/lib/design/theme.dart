import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData fsTheme() {
  const scheme = ColorScheme.light(
    primary: FsColors.primary,
    onPrimary: FsColors.onPrimary,
    primaryContainer: FsColors.primaryContainer,
    secondary: FsColors.earth,
    surface: FsColors.surface,
    onSurface: FsColors.textPrimary,
    onSurfaceVariant: FsColors.textSecondary,
    outline: FsColors.border,
    error: FsColors.riskHigh,
  );

  const text = TextTheme(
    headlineMedium: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      height: 1.4,
    ),
    titleLarge: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      height: 1.5,
    ),
    titleMedium: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      height: 1.5,
    ),
    bodyLarge: TextStyle(fontSize: 18, height: 1.6),
    bodyMedium: TextStyle(fontSize: 16, height: 1.6),
    labelLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1.5,
    ),
    bodySmall: TextStyle(
      fontSize: 14,
      height: 1.5,
      color: FsColors.textSecondary,
    ),
  );

  const buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(FsRadius.md),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: FsColors.bg,
    textTheme: text.apply(
      bodyColor: FsColors.textPrimary,
      displayColor: FsColors.textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: FsColors.bg,
      foregroundColor: FsColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(FsSpace.minTouch),
        shape: buttonShape,
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(FsSpace.minTouch),
        shape: buttonShape,
        side: const BorderSide(color: FsColors.primary),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(FsSpace.minTouch, FsSpace.minTouch),
        textStyle: text.labelLarge,
      ),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: FsColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(FsRadius.lg),
        side: BorderSide(color: FsColors.border),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: FsColors.primary,
      linearTrackColor: FsColors.border,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: FsColors.surface,
      indicatorColor: FsColors.primaryContainer,
      height: 72,
    ),
  );
}
