import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earthsync/features/field/decision_comparison.dart';

// UI fixtures reuse a saved capture; no new live/scientific claim is made.
Map<String, dynamic> fixture() => Map<String, dynamic>.from(
  jsonDecode(
        File(
          '../docs/integration/7w/evidence/browser-final-acceptance/saved-rust-v2-assessment.json',
        ).readAsStringSync(),
      )
      as Map,
);
void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'three saved strategies save and reopen at $width without ranking',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Map<String, dynamic>? saved;
        final decisions = [
          for (final id in ['baseline', 'alternative-a', 'alternative-b'])
            {'id': id, 'assessment': fixture()},
        ];
        final group = {
          'baseline_decision_id': 'baseline',
          'alternative_decision_ids': ['alternative-a', 'alternative-b'],
          'name': 'Reported plan exploration',
          'exploration_reason': 'Explore water conservation',
          'priorities': ['less_water', 'nitrogen_potential'],
          'baseline_declared_existing_plan': true,
        };
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DecisionComparison(
                  decisions: decisions,
                  initialComparison: group,
                  onSave: (value) async {
                    saved = value;
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Baseline · existing plan · baseline'),
          findsOneWidget,
        );
        expect(find.text('Alternative A · alternative-a'), findsOneWidget);
        expect(find.text('Alternative B · alternative-b'), findsOneWidget);
        expect(
          find.text(
            'rice.mm.calendar-5-sessions-0@1 · 2024-07-03 → 2024-07-07 · declared rainfed',
          ),
          findsNWidgets(3),
        );
        expect(find.textContaining('No preferred crop'), findsOneWidget);
        final a = tester.getTopLeft(
          find.text('Baseline · existing plan · baseline'),
        );
        final b = tester.getTopLeft(find.text('Alternative A · alternative-a'));
        if (width >= 1000) {
          expect(a.dy, b.dy);
          expect(b.dx, greaterThan(a.dx));
        } else {
          expect(b.dy, greaterThan(a.dy));
        }
        await tester.ensureVisible(find.text('Confirm & save comparison'));
        await tester.tap(find.text('Confirm & save comparison'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save comparison'));
        await tester.pumpAndSettle();
        expect(saved!['baseline_decision_id'], 'baseline');
        expect(saved!['alternative_decision_ids'], [
          'alternative-a',
          'alternative-b',
        ]);
        expect(saved!['baseline_declared_existing_plan'], true);
        expect(saved!['priorities'], ['less_water', 'nitrogen_potential']);
        expect(saved!.containsKey('score'), false);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('two decisions cannot satisfy three-strategy requirement', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DecisionComparison(
              decisions: [
                {'id': 'a', 'assessment': fixture()},
                {'id': 'b', 'assessment': fixture()},
              ],
              onSave: (_) async {},
            ),
          ),
        ),
      ),
    );
    expect(
      find.textContaining('Save at least three separate two-crop sequences'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Confirm & save comparison'),
          )
          .onPressed,
      null,
    );
  });
}
