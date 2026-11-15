import 'dart:convert';
import 'dart:io';
import 'package:earthsync/evidence/data/farm_journal.dart';
import 'package:earthsync/evidence/features/companion/risk_center.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('forecast disclosure remains an actionable semantic node', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final job =
        jsonDecode(
              File(
                '../docs/integration/7g/evidence/browser-final-build/forecast-job.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RiskCenter(
                snapshot: FarmJournalSnapshot({
                  'farm_id': 'software-test-farm',
                  'intelligence': [job],
                }),
              ),
            ),
          ),
        ),
      ),
    );
    final title = find.textContaining('NOAA NCEP GFS ·');
    await tester.ensureVisible(title);
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Publication / issuance timestamp: unavailable'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Acknowledge snapshot'));
    await tester.pumpAndSettle();
    final node = tester.getSemantics(
      find.widgetWithText(OutlinedButton, 'Acknowledge snapshot'),
    );
    expect(
      node,
      matchesSemantics(
        isButton: true,
        hasTapAction: true,
        isEnabled: true,
        hasEnabledState: true,
        hasFocusAction: true,
        isFocusable: true,
        label: 'Acknowledge snapshot',
      ),
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
