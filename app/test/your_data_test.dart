import 'dart:convert';

import 'package:earthsync/app/strings.dart';
import 'package:earthsync/data/models/field_note.dart';
import 'package:earthsync/design/theme.dart';
import 'package:earthsync/features/privacy/your_data_screen.dart';
import 'package:earthsync/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _draft = FarmerDraft(
  latitude: 16.85,
  longitude: 96.15,
  currentCrop: 'rice',
  soilTexture: 'loam',
);

Future<(ProviderContainer, SharedPreferences)> _setUp() async {
  SharedPreferences.setMockInitialValues({
    'farmer_draft_v1': jsonEncode(_draft.toJson()),
    'field_notes_v1': jsonEncode([
      FieldNote(
        id: '1',
        createdAt: DateTime.utc(2026, 11, 14),
        kind: NoteKind.pests,
        text: 'Brown spots',
      ).toJson(),
    ]),
    'last_result_v1': '{"saved":"x"}',
  });
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [prefsProvider.overrideWithValue(prefs)],
  );
  return (c, prefs);
}

Widget _app(ProviderContainer c) => UncontrolledProviderScope(
  container: c,
  child: MaterialApp.router(
    theme: fsLightTheme(),
    routerConfig: GoRouter(
      initialLocation: '/your-data',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('welcome')),
        ),
        GoRoute(path: '/your-data', builder: (_, _) => const YourDataScreen()),
      ],
    ),
  ),
);

void main() {
  testWidgets('shows what is kept where, in plain words', (tester) async {
    final (c, _) = await _setUp();
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();
    for (final title in [
      S.dataPhoneTitle,
      S.dataOnlineTitle,
      S.dataCountsTitle,
      S.dataWeatherTitle,
      S.dataNeverTitle,
      S.deleteAll,
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
  });

  testWidgets(
    'Delete all my data wipes the phone copy and returns to Welcome',
    (tester) async {
      final (c, prefs) = await _setUp();
      addTearDown(c.dispose);
      expect(c.read(notesProvider), hasLength(1));
      expect(c.read(farmerDraftProvider).soilTexture, 'loam');

      await tester.pumpWidget(_app(c));
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.deleteAll));
      await tester.pumpAndSettle();
      expect(find.text(S.deleteConfirmTitle), findsOneWidget);
      await tester.tap(find.text(S.deleteWord));
      await tester.pumpAndSettle();

      expect(c.read(notesProvider), isEmpty);
      expect(c.read(farmerDraftProvider).hasLocation, isFalse);
      expect(c.read(farmerDraftProvider).soilTexture, isNull);
      expect(prefs.getString('farmer_draft_v1'), isNull);
      expect(prefs.getString('field_notes_v1'), isNull);
      expect(prefs.getString('last_result_v1'), isNull);
      expect(find.text('welcome'), findsOneWidget);
      expect(find.text(S.allDeleted), findsOneWidget);
    },
  );

  testWidgets('Cancel deletes nothing', (tester) async {
    final (c, prefs) = await _setUp();
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.deleteAll));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.cancel));
    await tester.pumpAndSettle();
    expect(c.read(notesProvider), hasLength(1));
    expect(prefs.getString('farmer_draft_v1'), isNotNull);
  });
}
