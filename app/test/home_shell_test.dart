import 'dart:convert';
import 'dart:io';

import 'package:earthsync/app/strings.dart';
import 'package:earthsync/data/engine/engine_envelope.dart';
import 'package:earthsync/data/models/farm_boundary.dart';
import 'package:earthsync/data/models/field_analysis.dart';
import 'package:earthsync/design/components/scenario.dart';
import 'package:earthsync/design/theme.dart';
import 'package:earthsync/features/home/home_shell.dart';
import 'package:earthsync/state/providers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

FieldAnalysis _loadAnalysis() {
  final raw = File(
    'test/fixtures/engine_success_envelope.json',
  ).readAsStringSync();
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
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const HomeShell(),
    ),
  );
}

Finder _navTitle(String text) => find.descendant(
  of: find.byType(CupertinoSliverNavigationBar),
  matching: find.text(text),
);

Future<void> _visitTabs(WidgetTester tester) async {
  for (final tab in [
    S.tabCrops,
    S.tabWeather,
    S.tabField,
    S.tabNotes,
    S.tabToday,
  ]) {
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

  testWidgets(
    '5 tabs: Today, Crops, Weather, Field, Notes — each shows its page',
    (tester) async {
      await tester.pumpWidget(
        _buildShell(analysis: analysis, prefs: prefs, theme: fsLightTheme()),
      );
      await tester.pumpAndSettle();

      for (final tab in [
        S.tabToday,
        S.tabCrops,
        S.tabWeather,
        S.tabField,
        S.tabNotes,
      ]) {
        expect(find.text(tab), findsWidgets);
      }

      await tester.tap(find.text(S.tabCrops).last);
      await tester.pumpAndSettle();
      expect(_navTitle(S.nextSeason), findsOneWidget);

      await tester.tap(find.text(S.tabWeather).last);
      await tester.pumpAndSettle();
      expect(_navTitle(S.tabWeather), findsOneWidget);

      await tester.tap(find.text(S.tabField).last);
      await tester.pumpAndSettle();
      expect(_navTitle(S.myFarm), findsOneWidget);

      await tester.tap(find.text(S.tabNotes).last);
      await tester.pumpAndSettle();
      expect(_navTitle(S.notesTitle), findsOneWidget);
    },
  );

  testWidgets(
    'Crops: one card per plan, best fit first, tap opens "why" sheet',
    (tester) async {
      tester.view.physicalSize = const Size(412 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _buildShell(analysis: analysis, prefs: prefs, theme: fsLightTheme()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.tabCrops).last);
      await tester.pumpAndSettle();

      final cards = find.byType(FsCropCard);
      expect(cards, findsNWidgets(analysis.scenarios.length));
      final first = tester.widget<FsCropCard>(cards.first).scenario;
      expect(first.id, sortedByFit(analysis.scenarios).first.$1.id);

      await tester.tap(cards.first);
      await tester.pumpAndSettle();
      expect(find.text(S.whyGood.toUpperCase()), findsOneWidget);
      expect(find.text(S.moreDetails), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    },
  );

  testWidgets('Notes: tap a picture, type, save, swipe to delete, undo', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildShell(analysis: analysis, prefs: prefs, theme: fsLightTheme()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.tabNotes).last);
    await tester.pumpAndSettle();

    expect(find.text(S.notesEmptyBody), findsOneWidget);

    await tester.tap(find.text(S.kindPests));
    await tester.pumpAndSettle();
    const sample = 'Spotted armyworms on leaves';
    await tester.enterText(find.byType(CupertinoTextField), sample);
    await tester.tap(find.text(S.save));
    await tester.pumpAndSettle();
    expect(find.text(sample), findsOneWidget);

    await tester.drag(find.text(sample), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text(S.deleted), findsOneWidget);
    expect(find.text(sample), findsNothing);

    await tester.tap(find.text(S.undo));
    await tester.pumpAndSettle();
    expect(find.text(sample), findsOneWidget);

    // The photo-cleanup timer runs out; an undone note must survive it.
    await tester.pump(const Duration(seconds: 11));
    expect(find.text(sample), findsOneWidget);
  });

  testWidgets('Notes: saving without words keeps the picture as the note', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildShell(analysis: analysis, prefs: prefs, theme: fsLightTheme()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.tabNotes).last);
    await tester.pumpAndSettle();

    await tester.tap(find.text(S.kindWater));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.save));
    await tester.pumpAndSettle();
    expect(find.text(S.yourNotes.toUpperCase()), findsOneWidget);
    expect(find.text(S.kindWater), findsNWidgets(2)); // tile + saved note
  });

  testWidgets('Field: asks to mark the farm until the 4 corners are saved', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildShell(analysis: analysis, prefs: prefs, theme: fsLightTheme()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.tabField).last);
    await tester.pumpAndSettle();
    expect(find.text(S.markFarmBody), findsOneWidget);
    expect(find.text(S.editFarm), findsNothing);
  });

  testWidgets('Field: a saved farm shows its size and the edit row', (
    tester,
  ) async {
    final farm = FarmBoundary(const [
      LatLng(16.8650, 96.1940),
      LatLng(16.8650, 96.1960),
      LatLng(16.8670, 96.1960),
      LatLng(16.8670, 96.1940),
    ]);
    SharedPreferences.setMockInitialValues({
      'farmer_draft_v1': jsonEncode(
        FarmerDraft(
          latitude: 16.866,
          longitude: 96.195,
          currentCrop: 'rice',
          farm: farm,
        ).toJson(),
      ),
    });
    prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      _buildShell(analysis: analysis, prefs: prefs, theme: fsLightTheme()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.tabField).last);
    await tester.pumpAndSettle();
    expect(find.text(S.editFarm), findsOneWidget);
    expect(find.text(farmSizeLabel(farm)), findsWidgets);
    expect(find.text(S.markFarmBody), findsNothing);
  });

  testWidgets('light mode renders every tab without layout errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildShell(analysis: analysis, prefs: prefs, theme: fsLightTheme()),
    );
    await tester.pumpAndSettle();
    await _visitTabs(tester);
  });

  testWidgets('dark mode renders every tab without layout errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildShell(analysis: analysis, prefs: prefs, theme: fsDarkTheme()),
    );
    await tester.pumpAndSettle();
    await _visitTabs(tester);
  });

  testWidgets('every tab survives 130% text size', (tester) async {
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

  testWidgets('tablet width (1024x768) shows the sidebar with no overflow', (
    tester,
  ) async {
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
