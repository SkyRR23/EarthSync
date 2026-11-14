import 'dart:io';

import 'package:earthsync/app/strings.dart';
import 'package:earthsync/data/engine/engine_envelope.dart';
import 'package:earthsync/data/models/field_analysis.dart';
import 'package:earthsync/design/components/scenario.dart';
import 'package:earthsync/design/theme.dart';
import 'package:earthsync/features/home/home_shell.dart';
import 'package:earthsync/state/providers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

FieldAnalysis _loadAnalysis() {
  final raw = File('test/fixtures/engine_success_envelope.json').readAsStringSync();
  return fieldAnalysisFromEnvelope(raw);
}

class _Ready extends AnalysisNotifier {
  _Ready(this.a);
  final FieldAnalysis a;

  @override
  AnalysisState build() => AnalysisReady(a);
}

Widget _buildShell({
  required FieldAnalysis analysis,
  required SharedPreferences prefs,
  required ThemeData theme,
  double textScale = 1.0,
}) {
  return ProviderScope(
    overrides: [
      analysisProvider.overrideWith(() => _Ready(analysis)),
      prefsProvider.overrideWithValue(prefs),
    ],
    child: MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: const HomeShell(),
    ),
  );
}

Future<void> _visitTabs(WidgetTester tester) async {
  for (final tab in [S.tabCrops, S.tabWeather, S.tabNotes, S.tabHome]) {
    await tester.tap(find.text(tab).last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'visiting tab $tab');
  }
}

void main() {
  late FieldAnalysis analysis;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    analysis = _loadAnalysis();
  });

  testWidgets('4 tabs show and tapping each tab shows its page title', (tester) async {
    await tester.pumpWidget(
      _buildShell(analysis: analysis, prefs: prefs, theme: fsLightTheme()),
    );
    await tester.pumpAndSettle();

    // All 4 tabs show in the bar
    expect(find.text(S.tabHome), findsWidgets);
    expect(find.text(S.tabCrops), findsWidgets);
    expect(find.text(S.tabWeather), findsWidgets);
    expect(find.text(S.tabNotes), findsWidgets);

    // Initial page title is "My field"
    expect(find.text(S.myField), findsOneWidget);

    // Tap Crops
    await tester.tap(find.text(S.tabCrops).last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(CupertinoSliverNavigationBar),
        matching: find.text(S.tabCrops),
      ),
      findsOneWidget,
    );

    // Tap Weather
    await tester.tap(find.text(S.tabWeather).last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(CupertinoSliverNavigationBar),
        matching: find.text(S.tabWeather),
      ),
      findsOneWidget,
    );

    // Tap Notes
    await tester.tap(find.text(S.tabNotes).last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(CupertinoSliverNavigationBar),
        matching: find.text(S.tabNotes),
      ),
      findsOneWidget,
    );
  });

  testWidgets('tapping crop plan on Home switches to Crops tab with plan selected', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _buildShell(analysis: analysis, prefs: prefs, theme: fsLightTheme()),
    );
    await tester.pumpAndSettle();

    // Verify plans exist on Home tab
    expect(find.byType(FsPlanRow), findsNWidgets(3));

    // Tap Plan 1 ("Other plan 1")
    await tester.scrollUntilVisible(find.byType(FsPlanRow).at(1), 100);
    await tester.tap(find.byType(FsPlanRow).at(1));
    await tester.pumpAndSettle();

    // Should be on Crops tab with Plan 1 selected
    expect(find.text(S.plan(1)), findsOneWidget);
    expect(find.text(S.planLong(1)), findsWidgets);

    // Return to Home tab
    await tester.tap(find.text(S.tabHome).last);
    await tester.pumpAndSettle();

    // Tap Plan 2 ("Other plan 2")
    await tester.scrollUntilVisible(find.byType(FsPlanRow).at(2), 100);
    await tester.tap(find.byType(FsPlanRow).at(2));
    await tester.pumpAndSettle();

    // Should be on Crops tab with Plan 2 selected
    expect(find.text(S.plan(2)), findsOneWidget);
    expect(find.text(S.planLong(2)), findsWidgets);
  });

  testWidgets('notes: empty state -> add note -> type -> save -> appears -> swipe to delete -> undo', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildShell(analysis: analysis, prefs: prefs, theme: fsLightTheme()),
    );
    await tester.pumpAndSettle();

    // Switch to Notes tab
    await tester.tap(find.text(S.tabNotes).last);
    await tester.pumpAndSettle();

    // Empty state
    expect(find.text(S.notesEmptyTitle), findsOneWidget);
    expect(find.text(S.notesEmptyBody), findsOneWidget);

    // Tap Add note
    await tester.tap(find.text(S.addNote));
    await tester.pumpAndSettle();

    // Type note text
    const sampleText = 'Spotted armyworms on leaves';
    await tester.enterText(find.byType(CupertinoTextField), sampleText);
    await tester.pumpAndSettle();

    // Save
    await tester.tap(find.text(S.save));
    await tester.pumpAndSettle();

    // Note appears
    expect(find.text(sampleText), findsOneWidget);

    // Swipe to delete
    await tester.drag(find.text(sampleText), const Offset(-500, 0));
    await tester.pumpAndSettle();

    // Note deleted notification and note gone
    expect(find.text(S.deleted), findsOneWidget);
    expect(find.text(sampleText), findsNothing);

    // Undo brings it back
    await tester.tap(find.text(S.undo));
    await tester.pumpAndSettle();

    expect(find.text(sampleText), findsOneWidget);
  });

  testWidgets('shell in light mode renders without layout errors', (tester) async {
    await tester.pumpWidget(
      _buildShell(analysis: analysis, prefs: prefs, theme: fsLightTheme()),
    );
    await tester.pumpAndSettle();
    await _visitTabs(tester);
  });

  testWidgets('shell in dark mode renders without layout errors', (tester) async {
    await tester.pumpWidget(
      _buildShell(analysis: analysis, prefs: prefs, theme: fsDarkTheme()),
    );
    await tester.pumpAndSettle();
    await _visitTabs(tester);
  });

  testWidgets('shell survives 130% text size', (tester) async {
    await tester.pumpWidget(
      _buildShell(
        analysis: analysis,
        prefs: prefs,
        theme: fsLightTheme(),
        textScale: 1.3,
      ),
    );
    await tester.pumpAndSettle();
    await _visitTabs(tester);
  });

  testWidgets('tablet width (1024x768) shows sidebar with no overflow', (tester) async {
    tester.view.physicalSize = const Size(1024 * 3, 768 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _buildShell(analysis: analysis, prefs: prefs, theme: fsLightTheme()),
    );
    await tester.pumpAndSettle();

    expect(find.text(S.appName), findsOneWidget);
    await _visitTabs(tester);
  });
}
