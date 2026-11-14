import 'dart:convert';
import 'dart:io';

import 'package:earthsync/app/strings.dart';
import 'package:earthsync/data/engine/live_integration.dart';
import 'package:earthsync/data/environment/nasa_power_client.dart';
import 'package:earthsync/data/models/farmer_input.dart';
import 'package:earthsync/data/models/field_note.dart';
import 'package:earthsync/data/models/soil_texture.dart';
import 'package:earthsync/design/theme.dart';
import 'package:earthsync/features/soil/soil_test_screen.dart';
import 'package:earthsync/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('hand texture key', () {
    test('every path ends in one of the engine soil types', () {
      expect(soilFromFeelTest(makesBall: false), SoilTexture.sand);
      expect(
        soilFromFeelTest(makesBall: true, ribbon: Ribbon.none),
        SoilTexture.sandyLoam,
      );
      expect(
        soilFromFeelTest(makesBall: true, ribbon: Ribbon.long),
        SoilTexture.clay,
      );
      expect(
        soilFromFeelTest(makesBall: true, ribbon: Ribbon.medium),
        SoilTexture.clayLoam,
      );
      expect(
        soilFromFeelTest(
          makesBall: true,
          ribbon: Ribbon.short,
          feel: Feel.gritty,
        ),
        SoilTexture.sandyLoam,
      );
      expect(
        soilFromFeelTest(
          makesBall: true,
          ribbon: Ribbon.short,
          feel: Feel.smooth,
        ),
        SoilTexture.silt,
      );
      expect(
        soilFromFeelTest(
          makesBall: true,
          ribbon: Ribbon.short,
          feel: Feel.neither,
        ),
        SoilTexture.loam,
      );
    });

    test('missing answers give no result yet', () {
      expect(soilFromFeelTest(), isNull);
      expect(soilFromFeelTest(makesBall: true), isNull);
      expect(soilFromFeelTest(makesBall: true, ribbon: Ribbon.short), isNull);
    });

    test('engine names match the Rust SoilTexture spelling', () {
      expect(
        [for (final t in SoilTexture.values) t.engineName],
        ['sand', 'sandy_loam', 'loam', 'silt', 'clay_loam', 'clay'],
      );
      expect(soilTextureFromName('clay_loam'), SoilTexture.clayLoam);
      expect(soilTextureFromName('mud'), isNull);
    });
  });

  group('soil reaches the engine request', () {
    test('farmer soil is saved and sent; "not sure" sends nothing', () {
      const base = FarmerDraft(latitude: 16.85, longitude: 96.15);
      final checked = base.copyWith(soilTexture: 'clay_loam');
      expect(checked.toInput().soilTexture, 'clay_loam');
      expect(FarmerDraft.fromJson(checked.toJson()).soilTexture, 'clay_loam');
      expect(
        base.copyWith(soilTexture: kUnknown).toInput().soilTexture,
        isNull,
      );
    });
  });

  group('photo notes', () {
    test('photo fields survive saving', () {
      final n = FieldNote(
        id: '1',
        createdAt: DateTime.utc(2026, 11, 14),
        kind: NoteKind.soil,
        text: 'Soil test: Clay',
        photo: '1.jpg',
      ).withCloudPhoto('users/u/photos/1.jpg');
      final back = FieldNote.fromJson(
        jsonDecode(jsonEncode(n.toJson())) as Map<String, dynamic>,
      );
      expect(back.kind, NoteKind.soil);
      expect(back.photo, '1.jpg');
      expect(back.cloudPhoto, 'users/u/photos/1.jpg');
    });

    test('old notes without photos still load', () {
      final back = FieldNote.fromJson({
        'id': 'x',
        'created_at': '2026-11-14T00:00:00Z',
        'kind': 'pests',
        'text': 'Brown spots',
      });
      expect(back.photo, isNull);
      expect(back.kind, NoteKind.pests);
    });
  });

  testWidgets(
    'soil test: ball, short ribbon, smooth = Silt; saved with a note',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: fsLightTheme(),
            home: const SoilTestScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(S.start));
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.ballYes));
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.ribbonShort));
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.feelSmooth));
      await tester.pumpAndSettle();

      expect(find.text('Silt'), findsOneWidget);
      expect(find.text(S.soilFromHands), findsOneWidget);

      await tester.tap(find.text(S.saveSoil));
      await tester.pumpAndSettle();
      expect(container.read(farmerDraftProvider).soilTexture, 'silt');
      final notes = container.read(notesProvider);
      expect(notes.single.kind, NoteKind.soil);
      expect(notes.single.text, S.soilNote('Silt'));
    },
  );

  testWidgets('soil test: "Not sure" saves unknown, not a guess', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [prefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: fsLightTheme(), home: const SoilTestScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.start));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.dontKnow));
    await tester.pumpAndSettle();
    expect(find.text(S.soilUnsure), findsOneWidget);
    await tester.tap(find.text(S.saveSoil));
    await tester.pumpAndSettle();
    expect(container.read(farmerDraftProvider).soilTexture, kUnknown);
    expect(container.read(notesProvider), isEmpty);
  });

  test('live engine request carries the farmer soil texture', () {
    const input = FarmerInput(
      latitude: 16.85,
      longitude: 96.15,
      soilTexture: 'loam',
    );
    final evidence = NasaPowerEvidence.parse(
      File('assets/fixtures/nasa_power_real.json').readAsStringSync(),
      input,
      const HistoricalWindow(),
    );
    final req = buildLiveIntegrationRequest(input, evidence);
    expect((req['soil'] as Map)['texture'], 'loam');
    const none = FarmerInput(latitude: 16.85, longitude: 96.15);
    expect(
      (buildLiveIntegrationRequest(none, evidence)['soil'] as Map)['texture'],
      isNull,
    );
  });
}
