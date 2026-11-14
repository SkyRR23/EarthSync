import 'dart:convert';
import 'dart:io';

import 'package:earthsync/data/models/field_analysis.dart';
import 'package:earthsync/design/theme.dart';
import 'package:earthsync/features/results/results_screen.dart';
import 'package:earthsync/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

FieldAnalysis _mock() => FieldAnalysis.fromJson(
  jsonDecode(
        File('assets/fixtures/field_analysis_demo.json').readAsStringSync(),
      )
      as Map<String, dynamic>,
);

class _Ready extends AnalysisNotifier {
  _Ready(this.a);
  final FieldAnalysis a;
  @override
  AnalysisState build() => AnalysisReady(a);
}

Future<void> _pump(
  WidgetTester t, {
  required ThemeData theme,
  Size size = const Size(412, 880),
  double textScale = 1,
}) async {
  t.view.physicalSize = size * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final a = _mock();
  await t.pumpWidget(
    ProviderScope(
      overrides: [analysisProvider.overrideWith(() => _Ready(a))],
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const ResultsScreen(),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _visitTabs(WidgetTester t) async {
  expect(find.text('Your options'), findsWidgets);
  for (final tab in ['Climate', 'Compare', 'Overview']) {
    await t.tap(find.text(tab).last);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull, reason: 'tab $tab');
  }
}

void main() {
  testWidgets('results render in light mode without layout errors', (t) async {
    await _pump(t, theme: fsLightTheme());
    await _visitTabs(t);
  });

  testWidgets('results render in dark mode', (t) async {
    await _pump(t, theme: fsDarkTheme());
    await _visitTabs(t);
  });

  testWidgets('results survive 130% text size', (t) async {
    await _pump(t, theme: fsLightTheme(), textScale: 1.3);
    await _visitTabs(t);
  });

  testWidgets('tablet width uses a sidebar instead of a tab bar', (t) async {
    await _pump(t, theme: fsLightTheme(), size: const Size(1024, 768));
    expect(find.text('Field Shift'), findsOneWidget);
    await _visitTabs(t);
  });

  testWidgets('compare tab switches options with the segmented control', (
    t,
  ) async {
    await _pump(t, theme: fsLightTheme());
    await t.tap(find.text('Compare').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Option 2'));
    await t.pumpAndSettle();
    expect(find.text('Monsoon rice, then sesame'), findsWidgets);
  });
}
