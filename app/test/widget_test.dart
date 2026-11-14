import 'dart:convert';
import 'dart:io';

import 'package:earthsync/data/engine/mock_engine.dart';
import 'package:earthsync/data/models/farmer_input.dart';
import 'package:earthsync/data/models/field_analysis.dart';
import 'package:earthsync/design/components/scenario.dart';
import 'package:earthsync/design/theme.dart';
import 'package:earthsync/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

FieldAnalysis _fixture() => FieldAnalysis.fromJson(
  jsonDecode(
        File('assets/fixtures/field_analysis_demo.json').readAsStringSync(),
      )
      as Map<String, dynamic>,
);

void main() {
  test(
    'fixture parses: baseline + 2 alternatives, missing month stays null',
    () {
      final a = _fixture();
      expect(a.scenarios.length, greaterThanOrEqualTo(3));
      expect(a.baseline?.isBaseline, isTrue);
      expect(a.climateSummary.months.length, 12);
      expect(
        a.climateSummary.months[6].rainMm,
        isNull,
      ); // July missing, not zero
      expect(a.dataQuality.isDemo, isTrue);
    },
  );

  test('mock engine returns the fixture', () async {
    final a = await MockEngine(
      delay: Duration.zero,
    ).analyzeField(const FarmerInput(latitude: 16.8, longitude: 96.1));
    expect(a.scenarios, isNotEmpty);
  });

  testWidgets('welcome screen offers optional location', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: FieldShiftApp()));
    await tester.pumpAndSettle();
    expect(find.text('Use My Location'), findsOneWidget);
    expect(find.text('Skip for Now'), findsOneWidget);
  });

  testWidgets('scenario card shows title, status and no percentages', (
    tester,
  ) async {
    final s = _fixture().scenarios[1];
    await tester.pumpWidget(
      MaterialApp(
        theme: fsTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: FsScenarioCard(scenario: s, optionNumber: 1),
          ),
        ),
      ),
    );
    expect(find.text(s.title), findsOneWidget);
    expect(find.text('Partly limited'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });
}
