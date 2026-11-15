import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earthsync/evidence/features/field/decision_comparison.dart';

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
          'chosen_decision_id': 'alternative-a',
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
        expect(find.text('Baseline · existing plan'), findsOneWidget);
        expect(find.text('Alternative A'), findsNWidgets(2));
        expect(find.text('Alternative B'), findsOneWidget);
        expect(
          find.text(
            'rice · 2024-07-03 to 2024-07-07\n5 declared calendar days; not a reviewed crop duration · rainfed',
          ),
          findsNWidgets(3),
        );
        expect(find.textContaining('No preferred crop'), findsOneWidget);
        final a = tester.getTopLeft(find.text('Baseline · existing plan'));
        final b = tester.getTopLeft(find.text('Alternative A').last);
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
        expect(saved!['chosen_decision_id'], 'alternative-a');
        expect(saved!['priorities'], ['less_water', 'nitrogen_potential']);
        expect(saved!.containsKey('score'), false);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'soil depth requirements are not presented as root characteristics',
    (tester) async {
      final assessment = fixture();
      assessment['catalog_projection'][0]['profile']['parameters']['ecological_soil_depth'] =
          {
            'state': 'available',
            'value': 100,
            'unit': 'cm',
            'statistic': 'synthetic reference fixture',
            'spatial_support': 'not field evidence',
            'claim_ids': [],
          };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DecisionComparison(
                decisions: [
                  for (final id in ['a', 'b', 'c'])
                    {'id': id, 'assessment': assessment},
                ],
                initialComparison: const {
                  'baseline_decision_id': 'a',
                  'alternative_decision_ids': ['b', 'c'],
                  'baseline_declared_existing_plan': true,
                },
              ),
            ),
          ),
        ),
      );
      final details = find
          .text('Crop characteristics & possible benefits')
          .first;
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Root characteristics: Insufficient applicable trait evidence.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('ecological soil depth: 100 cm'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
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
