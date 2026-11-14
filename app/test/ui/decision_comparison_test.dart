import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earthsync/features/field/decision_comparison.dart';

void main() {
  testWidgets(
    'compares saved dates and findings without ranking or recalculation',
    (tester) async {
      final assessment =
          jsonDecode(
                File(
                  '../docs/integration/7w/evidence/browser-final-acceptance/saved-rust-v2-assessment.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DecisionComparison(
                decisions: [
                  {'id': 'software-test-A', 'assessment': assessment},
                  {'id': 'software-test-B', 'assessment': assessment},
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('software-test-A').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('software-test-B').last);
      await tester.pumpAndSettle();
      expect(find.text('Alternative A · software-test-A'), findsOneWidget);
      expect(find.text('Alternative B · software-test-B'), findsOneWidget);
      expect(find.textContaining('2024-07-03 → 2024-07-07'), findsNWidgets(2));
      expect(find.textContaining('No preferred crop'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
