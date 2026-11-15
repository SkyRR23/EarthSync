import 'dart:convert';
import 'dart:io';

import 'package:earthsync/app/strings.dart';
import 'package:earthsync/data/engine/live_integration.dart';
import 'package:earthsync/data/environment/nasa_power_client.dart';
import 'package:earthsync/data/models/farmer_input.dart';
import 'package:earthsync/data/models/field_note.dart';
import 'package:earthsync/data/models/soil_texture.dart';
import 'package:earthsync/data/soil/soil_ai_client.dart';
import 'package:earthsync/design/theme.dart';
import 'package:earthsync/features/home/home_shell.dart';
import 'package:earthsync/features/soil/soil_test_screen.dart';
import 'package:earthsync/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('hand-texture key (same table as the backend)', () {
    final cases = <(Ribbon?, Feel?, SoilClass?)>[
      (Ribbon.fallsApart, null, SoilClass.sand),
      (Ribbon.none, Feel.gritty, SoilClass.loamySand),
      (Ribbon.none, Feel.sticky, SoilClass.sandyLoam),
      (Ribbon.short, Feel.gritty, SoilClass.sandyLoam),
      (Ribbon.short, Feel.smooth, SoilClass.siltLoam),
      (Ribbon.short, Feel.sticky, SoilClass.loam),
      (Ribbon.medium, Feel.gritty, SoilClass.sandyClayLoam),
      (Ribbon.medium, Feel.smooth, SoilClass.siltyClayLoam),
      (Ribbon.medium, null, SoilClass.clayLoam),
      (Ribbon.long, Feel.gritty, SoilClass.sandyClay),
      (Ribbon.long, Feel.smooth, SoilClass.siltyClay),
      (Ribbon.long, Feel.sticky, SoilClass.clay),
      (null, Feel.gritty, null),
    ];
    for (final (r, f, want) in cases) {
      test('$r + $f -> $want', () => expect(handKey(r, f), want));
    }
  });

  test('12 soil types map onto the 6 the current engine knows', () {
    expect(
      {for (final c in SoilClass.values) c.engine6},
      {'sand', 'sandy_loam', 'loam', 'silt', 'clay_loam', 'clay'},
    );
    expect(SoilClass.siltyClayLoam.engine6, 'clay_loam');
    expect(SoilClass.loamySand.engine6, 'sandy_loam');
    // Names saved by yesterday's 6-type test still load.
    for (final old in [
      'sand',
      'sandy_loam',
      'loam',
      'silt',
      'clay_loam',
      'clay',
    ]) {
      expect(soilClassFromName(old), isNotNull, reason: old);
    }
  });

  test('saved soil goes to the engine as 6 types and to the backend as 12', () {
    const base = FarmerDraft(latitude: 16.85, longitude: 96.15);
    final d = base.copyWith(
      soilTexture: 'silty_clay_loam',
      soilSource: 'ai_estimate',
      soilConfidence: 'medium',
      soilSigns: ['grey_spots'],
    );
    expect(d.toInput().soilTexture, 'clay_loam');
    expect(d.toInput().soilClass, 'silty_clay_loam');
    final back = FarmerDraft.fromJson(d.toJson());
    expect(back.soilSource, 'ai_estimate');
    expect(back.soilConfidence, 'medium');
    expect(back.soilSigns, ['grey_spots']);
    expect(base.copyWith(soilTexture: kUnknown).toInput().soilTexture, isNull);
  });

  test('live engine request carries the engine soil name', () {
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
    expect(
      (buildLiveIntegrationRequest(input, evidence)['soil'] as Map)['texture'],
      'loam',
    );
  });

  group('soil AI client', () {
    late File photo;
    setUp(() async {
      photo = File('${Directory.systemTemp.path}/soil-test.jpg')
        ..writeAsBytesSync([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
    });

    test('sends photos + answers, reads the estimate', () async {
      late Map<String, dynamic> sent;
      final client = SoilAiClient(
        baseUrl: 'https://example.test',
        client: MockClient((req) async {
          expect(req.url.path, '/api/v1/soil/estimate');
          sent = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'status': 'success',
              'source': 'ai_estimate',
              'soil_class': 'clay_loam',
              'confidence': 'medium',
              'photo_usable': true,
              'signs_seen': ['cracks', 'grey_spots'],
              'reason': 'Medium ribbon and cracks.',
              'hand_test': 'clay_loam',
            }),
            200,
          );
        }),
      );
      final est = await client.estimate(
        photos: [photo],
        ribbon: Ribbon.medium,
        feel: Feel.sticky,
        signs: {SoilSign.cracks},
      );
      expect(
        (sent['photos'] as List).single,
        base64Encode(photo.readAsBytesSync()),
      );
      expect(sent['answers'], {
        'ribbon': 'medium',
        'feel': 'sticky',
        'signs': ['cracks'],
      });
      expect(est.soilClass, SoilClass.clayLoam);
      expect(est.signs, [SoilSign.cracks, SoilSign.greySpots]);
    });

    test('server errors become a SoilAiException', () async {
      final client = SoilAiClient(
        baseUrl: 'https://example.test',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'status': 'error',
              'error': {
                'code': 'not_configured',
                'message': 'x',
                'retryable': false,
              },
            }),
            503,
          ),
        ),
      );
      expect(
        () => client.estimate(
          photos: [photo],
          ribbon: null,
          feel: null,
          signs: {},
        ),
        throwsA(
          isA<SoilAiException>().having(
            (e) => e.code,
            'code',
            'not_configured',
          ),
        ),
      );
    });
  });

  testWidgets('soil check without photos: hand test decides, signs are saved', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [prefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: fsLightTheme(), home: const SoilTestScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // No photo folder in tests, so the photo steps are skipped.
    await tester.tap(find.text(S.start));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.ribbonMedium));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.feelSmooth));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.signGreySpots));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.next));
    await tester.pumpAndSettle();

    expect(find.text('Silty clay loam'), findsOneWidget);
    expect(find.text(S.soilFromHands), findsOneWidget);
    await tester.tap(find.text(S.saveSoil));
    await tester.pumpAndSettle();

    final d = c.read(farmerDraftProvider);
    expect(d.soilTexture, 'silty_clay_loam');
    expect(d.soilSource, 'hand_test');
    expect(d.soilSigns, ['grey_spots']);
    expect(c.read(notesProvider).single.kind, NoteKind.soil);
  });

  testWidgets('soil check: not sure at every step saves unknown, not a guess', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [prefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: fsLightTheme(), home: const SoilTestScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.start));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.dontKnow));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.dontKnow));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.next));
    await tester.pumpAndSettle();
    expect(find.text(S.soilUnsure), findsOneWidget);
    await tester.tap(find.text(S.saveSoil));
    await tester.pumpAndSettle();
    expect(c.read(farmerDraftProvider).soilTexture, kUnknown);
  });

  testWidgets('Crops with no farm pinned says so instead of spinning forever', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [prefsProvider.overrideWithValue(prefs)],
        child: MaterialApp(theme: fsLightTheme(), home: const HomeShell()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(S.noFarmTitle), findsWidgets);
    expect(find.text(S.preparing), findsNothing);
  });
}
