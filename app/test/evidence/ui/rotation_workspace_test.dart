import 'dart:async';
import 'package:earthsync/evidence/data/farm_journal.dart';
import 'package:earthsync/evidence/data/platform_farms.dart';
import 'package:earthsync/evidence/data/platform_transport.dart';
import 'package:earthsync/evidence/features/companion/rotation_workspace.dart';
import 'package:earthsync/evidence/state/journal_provider.dart';
import 'package:earthsync/evidence/state/platform_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets(
    'saved-source refresh preserves the actual rotation workspace editor',
    (tester) async {
      final farm = PlatformFarm.fromJson({
        'id': 'owned-farm',
        'confirmed_point': {'latitude': 42.03, 'longitude': -93.62},
        'production_system': 'rainfed',
      });
      final client = PlatformFarmClient(
        PlatformTransport(
          MockClient((_) async => http.Response('{}', 500)),
          baseUri: Uri.parse('http://127.0.0.1:8021'),
        ),
      );
      const snapshot = FarmJournalSnapshot({
        'farm_id': 'owned-farm',
        'retrieved_at': '2026-11-14',
      });
      Completer<FarmJournalSnapshot?>? pending;
      final container = ProviderContainer(
        overrides: [
          platformFarmProvider.overrideWith((ref) async => farm),
          platformFarmClientProvider.overrideWithValue(client),
          journalProvider.overrideWith(
            (ref) async => pending == null ? snapshot : pending.future,
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: RotationWorkspace()),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.widgetWithText(
        TextField,
        'Water / first crop start (YYYY-MM-DD)',
      );
      await tester.scrollUntilVisible(
        field,
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(field, '2024-07-03');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.fling(
        find.byType(ListView).first,
        const Offset(0, 6000),
        4000,
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        field,
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('2024-07-03'), findsOneWidget);
      pending = Completer();
      container.invalidate(journalProvider);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('2024-07-03'), findsOneWidget);
      pending.complete(snapshot);
      await tester.pumpAndSettle();
      expect(find.text('2024-07-03'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
