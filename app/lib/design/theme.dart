import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

const _font = 'Inter';

TextTheme _textTheme(FsPalette p) {
  TextStyle s(
    double size,
    FontWeight w,
    double height, {
    double tracking = 0,
  }) => TextStyle(
    fontFamily: _font,
    fontSize: size,
    fontWeight: w,
    height: height,
    letterSpacing: tracking,
    color: p.label,
  );
  return TextTheme(
    displaySmall: s(34, FontWeight.w700, 1.2, tracking: -0.8), // large title
    headlineMedium: s(28, FontWeight.w700, 1.22, tracking: -0.6), // title 1
    headlineSmall: s(22, FontWeight.w700, 1.27, tracking: -0.4), // title 2
    titleLarge: s(20, FontWeight.w600, 1.3, tracking: -0.3), // title 3
    titleMedium: s(17, FontWeight.w600, 1.35, tracking: -0.2), // headline
    bodyLarge: s(17, FontWeight.w400, 1.4, tracking: -0.2), // body
    bodyMedium: s(16, FontWeight.w400, 1.4, tracking: -0.15), // callout
    labelLarge: s(17, FontWeight.w600, 1.2, tracking: -0.2), // buttons
    labelMedium: s(15, FontWeight.w400, 1.35, tracking: -0.1), // subhead
    bodySmall: s(
      13,
      FontWeight.w400,
      1.38,
    ).copyWith(color: p.secondaryLabel), // footnote
    labelSmall: s(
      12,
      FontWeight.w400,
      1.33,
    ).copyWith(color: p.secondaryLabel), // caption
  );
}

ThemeData _build(FsPalette p, Brightness b) {
  final text = _textTheme(p);
  final scheme = ColorScheme(
    brightness: b,
    primary: p.tint,
    onPrimary: p.onTint,
    primaryContainer: p.tintSoft,
    onPrimaryContainer: p.positiveText,
    secondary: p.secondaryLabel,
    onSecondary: p.surface,
    surface: p.surface,
    onSurface: p.label,
    onSurfaceVariant: p.secondaryLabel,
    surfaceContainerHighest: p.fill,
    outline: p.fillStrong,
    outlineVariant: p.separator,
    error: p.negativeText,
    onError: p.surface,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    fontFamily: _font,
    textTheme: text,
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    extensions: [p],
    // Apple-style feedback: no ripples; rows highlight, buttons scale.
    splashFactory: NoSplash.splashFactory,
    highlightColor: p.fill,
    hoverColor: p.fill.withValues(alpha: 0.5),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        TargetPlatform.fuchsia: CupertinoPageTransitionsBuilder(),
      },
    ),
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: b,
      primaryColor: p.tint,
      barBackgroundColor: p.barBackground,
      scaffoldBackgroundColor: p.background,
      textTheme: CupertinoTextThemeData(
        primaryColor: p.tint,
        textStyle: text.body,
        navTitleTextStyle: text.headline,
        navLargeTitleTextStyle: text.largeTitle,
        navActionTextStyle: text.body.copyWith(color: p.tint),
        actionTextStyle: text.body.copyWith(color: p.tint),
        tabLabelTextStyle: text.caption.copyWith(
          fontSize: 11,
          letterSpacing: 0.1,
        ),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: p.separator,
      thickness: 0.5,
      space: 0.5,
    ),
    iconTheme: IconThemeData(color: p.tint, size: 22),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.tint,
      linearTrackColor: p.fill,
      circularTrackColor: p.fill,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surfaceRaised,
      modalBackgroundColor: p.surfaceRaised,
      showDragHandle: true,
      dragHandleColor: p.fillStrong,
      dragHandleSize: const Size(36, 5),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FsRadius.sheet),
        ),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: p.label.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(FsRadius.sm),
      ),
      textStyle: text.footnote.copyWith(color: p.surface),
    ),
  );
}

ThemeData fsLightTheme() => _build(FsPalette.light, Brightness.light);
ThemeData fsDarkTheme() => _build(FsPalette.dark, Brightness.dark);

/// Back-compat for tests and older call sites.
ThemeData fsTheme() => fsLightTheme();
