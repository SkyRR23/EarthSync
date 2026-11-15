import 'dart:convert';
import 'package:earthsync/evidence/design/theme.dart';
import 'package:earthsync/evidence/features/planning/planning_panel.dart';
import 'package:earthsync/evidence/state/home_provider.dart';
import 'package:earthsync/evidence/state/preferences_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../home_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'appearance and language restore in a fresh provider container',
    () async {
      final first = ProviderContainer();
      await first.read(preferencesProvider.future);
      await first
          .read(preferencesProvider.notifier)
          .savePreferences(theme: ThemeMode.dark, language: 'my');
      first.dispose();
      final restored = ProviderContainer();
      addTearDown(restored.dispose);
      final prefs = await restored.read(preferencesProvider.future);
      expect(prefs.theme, ThemeMode.dark);
      expect(prefs.language, 'my');
    },
  );
  testWidgets(
    'crop history saves for the confirmed farm without engine promotion',
    (t) async {
      t.view.physicalSize = const Size(800, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            profileStoreProvider.overrideWithValue(
              MemoryProfileStore(confirmedProfile()),
            ),
          ],
          child: MaterialApp(
            theme: fsTheme(),
            home: const Scaffold(
              body: SingleChildScrollView(child: PlanningPanel()),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Record crop history & farm context'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField).at(0), 'Maize');
      await t.enterText(find.byType(TextFormField).at(1), '2024-02-01');
      await t.enterText(find.byType(TextFormField).at(2), '2024-01-31');
      await t.ensureVisible(find.text('Save crop notes'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save crop notes'));
      await t.pumpAndSettle();
      expect(find.text('Harvest must follow planting.'), findsOneWidget);
      final store = await SharedPreferences.getInstance();
      expect(store.getString('farm.notes.field-1'), null);
      await t.enterText(find.byType(TextFormField).at(2), '2024-05-31');
      await t.ensureVisible(find.text('Save crop notes'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save crop notes'));
      await t.pumpAndSettle();
      final notes = jsonDecode(store.getString('farm.notes.field-1')!);
      expect(notes['previous'], 'Maize');
      expect(notes['previousEnd'], '2024-05-31');
      expect(notes.containsKey('recommendation_eligible'), false);
      expect(store.getString('farm.notes.other-farm'), null);
    },
  );
}
