import 'dart:convert';
import 'dart:typed_data';
import 'package:earthsync/evidence/data/platform_farms.dart';
import 'package:earthsync/evidence/data/platform_transport.dart';
import 'package:earthsync/evidence/features/companion/crop_intelligence.dart';
import 'package:earthsync/evidence/features/companion/soil_workflows.dart';
import 'package:earthsync/evidence/features/photo_evidence/photo_picker.dart';
import 'package:earthsync/evidence/features/photo_evidence/photo_evidence_models.dart';
import 'package:earthsync/evidence/state/platform_provider.dart';
import 'package:earthsync/evidence/state/journal_provider.dart';
import 'package:earthsync/evidence/data/farm_journal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'image preview, explicit consent and validated findings at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Map<String, dynamic>? submitted;
        var mutations = 0;
        final client = PlatformFarmClient(
          PlatformTransport(
            MockClient((request) async {
              if (request.url.path.endsWith('/image-capabilities')) {
                return http.Response(
                  jsonEncode({
                    'enabled': true,
                    'provider': 'mock',
                    'model': 'synthetic-test',
                  }),
                  200,
                );
              }
              mutations++;
              if (request.url.path.endsWith('/photos')) {
                return http.Response(
                  '{"id":"test-photo"}',
                  201,
                  headers: {'content-type': 'application/json'},
                );
              }
              submitted = jsonDecode(request.body) as Map<String, dynamic>;
              return http.Response(
                jsonEncode({
                  'status': 'unverified_model_observation',
                  'provider_status': 'succeeded',
                  'observations': [
                    {'feature': 'yellowing', 'visibility': 'uncertain'},
                  ],
                  'possible_explanations': [],
                  'sources': [],
                  'citations': [],
                  'limitations': ['No confirmed diagnosis.'],
                  'missing_information': [],
                  'follow_up': [],
                }),
                200,
              );
            }),
            baseUri: Uri.parse('http://127.0.0.1:8021'),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SoilWorkflows(
                  client: client,
                  farmId: 'synthetic-farm',
                  picker: _SyntheticPicker(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Choose image'));
        await tester.pumpAndSettle();
        expect(mutations, 0);
        expect(find.byType(Image), findsOneWidget);
        final analyze = find.widgetWithText(FilledButton, 'Analyze image');
        expect(tester.widget<FilledButton>(analyze).onPressed, isNull);
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
        await tester.ensureVisible(analyze);
        await tester.tap(analyze);
        await tester.pumpAndSettle();
        expect(submitted?['external_image_consent'], true);
        expect(submitted?['image_kind'], 'crop');
        expect(
          mutations,
          2,
        ); // upload + analyze only; no automatic observation write.
        expect(find.text('yellowing · uncertain'), findsOneWidget);
        expect(find.text('Possible causes to investigate'), findsOneWidget);
        expect(
          tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
          false,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('unavailable output retains limitations and no inferred cause', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ImageEvidenceResult(
              packet: {
                'status': 'vision_unavailable',
                'provider_status': 'vision_unavailable',
                'limitations': ['A photo cannot measure soil pH.'],
                'missing_information': ['Laboratory sample required.'],
              },
            ),
          ),
        ),
      ),
    );
    expect(
      find.text('No supported cause is inferred from this image.'),
      findsOneWidget,
    );
    expect(find.text('• A photo cannot measure soil pH.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('PNG upload decodes the server JSON metadata response', () async {
    final transport = PlatformTransport(
      MockClient((request) async {
        expect(request.headers['content-type'], 'image/png');
        return http.Response(
          '{"id":"photo-test"}',
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
      baseUri: Uri.parse('http://127.0.0.1:8021'),
    );
    final result = await transport.request(
      'POST',
      '/photos',
      expectedStatus: 201,
      bytes: [1, 2, 3],
      contentType: 'image/png',
    );
    expect((result as Map)['id'], 'photo-test');
  });
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'retrieves scoped claims and retains missing eligibility at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Map<String, dynamic>? sent;
        final client = PlatformFarmClient(
          PlatformTransport(
            MockClient((request) async {
              sent = jsonDecode(request.body) as Map<String, dynamic>;
              return http.Response(
                jsonEncode({
                  'answer': 'No field recommendation is approved.',
                  'claims': [
                    {
                      'parameter': 'soil_sampling_context',
                      'value': 6,
                      'unit': 'inches',
                      'statistic': 'Sampling reference',
                      'source_id': 'test-source',
                      'evidence_status': 'reference_only',
                      'region': 'US-IA',
                      'locator': 'Sampling paragraph',
                      'limitations': ['Cultivar unknown.'],
                    },
                  ],
                  'blocked_candidates': [],
                  'sources': [],
                  'local_review_questions': ['Which cultivar is used?'],
                  'contradictions': [],
                  'recommendation_eligible': false,
                }),
                200,
              );
            }),
            baseUri: Uri.parse('http://127.0.0.1:8021'),
          ),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              platformFarmClientProvider.overrideWithValue(client),
              journalProvider.overrideWith(
                (ref) async => FarmJournalSnapshot({
                  'farm_id': 'test-farm',
                  'entries': [],
                  'photos': [],
                }),
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: CropIntelligencePanel(cropId: 'maize'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Crop intelligence'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(0), 'soil sampling');
        await tester.enterText(find.byType(TextField).at(1), 'US-IA');
        await tester.ensureVisible(find.text('Retrieve evidence'));
        await tester.tap(find.text('Retrieve evidence'));
        await tester.pumpAndSettle();
        expect(sent?['region'], 'US-IA');
        expect(sent?['crop'], 'maize');
        expect(
          find.text('No field recommendation is approved.'),
          findsOneWidget,
        );
        expect(find.text('soil sampling context'), findsOneWidget);
        expect(find.text('• Which cultivar is used?'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'laboratory confirmation is explicit and preserves corrected units and depth',
    (tester) async {
      final report = {
        'original': {
          'sample_id': 'SYNTHETIC-1',
          'laboratory': 'Software test laboratory',
          'values': [
            {
              'parameter': 'ph',
              'value': 6.4,
              'unit': 'pH',
              'method': 'water',
              'depth': '0-15 cm',
              'source_locator': 'image 1, row 1',
            },
          ],
        },
        'confirmed': null,
      };
      Map<String, dynamic>? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  submitted = await showDialog<Map<String, dynamic>>(
                    context: context,
                    builder: (_) => LabReportEditor(report: report),
                  );
                },
                child: const Text('Open report'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open report'));
      await tester.pumpAndSettle();
      final button = find.widgetWithText(
        FilledButton,
        'Confirm checked values',
      );
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Reported value'),
        '6.6',
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(submitted?['confirmed'], true);
      expect((submitted?['values'] as List).first['value'], 6.6);
      expect((submitted?['values'] as List).first['unit'], 'pH');
      expect((submitted?['values'] as List).first['depth'], '0-15 cm');
      expect((report['original'] as Map)['values'][0]['value'], 6.4);
      expect(tester.takeException(), isNull);
    },
  );
}

class _SyntheticPicker implements FieldPhotoPicker {
  @override
  bool get supportsCamera => false;
  @override
  Future<PreparedPhoto?> pick(
    PhotoOrigin origin, {
    required bool readGps,
  }) async {
    if (readGps) throw StateError('GPS must not be requested');
    return PreparedPhoto(
      png: Uint8List.fromList(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgmMbwHwACxgGWtyLbjwAAAABJRU5ErkJggg==',
        ),
      ),
      origin: origin,
      width: 1,
      height: 1,
    );
  }
}
