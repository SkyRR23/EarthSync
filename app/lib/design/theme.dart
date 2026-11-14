import 'package:flutter/material.dart';
import 'tokens.dart';

ThemeData fsTheme({Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: FsColors.primary,
    brightness: brightness,
    primary: dark ? const Color(0xFFA4D5B8) : FsColors.primary,
    surface: dark ? const Color(0xFF192A23) : FsColors.surface,
    error: dark ? const Color(0xFFFFB4AB) : FsColors.riskHigh,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'EarthSyncSans',
    fontFamilyFallback: const ['NotoSansMyanmar'],
  );
  final text = base.textTheme
      .copyWith(
        headlineLarge: const TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          height: 1.15,
          letterSpacing: -1.1,
        ),
        headlineMedium: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          height: 1.2,
          letterSpacing: -.6,
        ),
        titleLarge: const TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
        titleMedium: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          height: 1.4,
        ),
        bodyLarge: const TextStyle(fontSize: 16, height: 1.55),
        bodyMedium: const TextStyle(fontSize: 14, height: 1.5),
        bodySmall: TextStyle(
          fontSize: 12,
          height: 1.5,
          color: scheme.onSurfaceVariant,
        ),
        labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      )
      .apply(
        fontFamily: 'EarthSyncSans',
        fontFamilyFallback: const ['NotoSansMyanmar'],
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: dark ? const Color(0xFF101E18) : FsColors.bg,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF101E18) : FsColors.bg,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleMedium,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: shape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        side: BorderSide(color: scheme.outlineVariant),
        shape: shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .6)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.all(16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      padding: const EdgeInsets.all(8),
      side: BorderSide(color: scheme.outlineVariant),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      height: 76,
      labelTextStyle: WidgetStatePropertyAll(text.labelSmall),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 24),
    expansionTileTheme: const ExpansionTileThemeData(
      shape: Border(),
      collapsedShape: Border(),
    ),
  );
}
