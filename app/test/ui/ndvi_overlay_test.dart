// Synthetic transport/image fixtures verify rendering, not live NASA access.
import 'dart:convert';
import 'package:earthsync/data/platform_farms.dart';
import 'package:earthsync/data/platform_transport.dart';
import 'package:earthsync/features/map/ndvi_panel.dart';
import 'package:earthsync/state/home_provider.dart';
import 'package:earthsync/state/platform_provider.dart';
import 'package:earthsync/design/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../home_test_support.dart';

const png =
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFUlEQVR4nGMUSTb/z8DAwMAEIkAYABjlAbHdHxFpAAAAAElFTkSuQmCC';

void main() {
  for (final width in [320.0, 1200.0]) {
    for (final cached in [false, true]) {
      testWidgets(
        'NDVI ${cached ? 'cached' : 'unavailable'} controls at $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1500);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          var inspections = 0;
          String? requestedBounds;
          final transport = PlatformTransport(
            MockClient((request) async {
              if (request.method == 'POST') {
                expect(
                  request.url.path.endsWith('/ndvi-overlay/refresh'),
                  isTrue,
                );
                requestedBounds = request.url.queryParameters['bbox'];
                return http.Response('{}', 202);
              }
              if (request.url.queryParameters.containsKey('lat')) {
                expect(request.url.queryParameters['bbox'], requestedBounds);
                inspections++;
                return http.Response(
                  jsonEncode({
                    'pixel': {
                      'value': .539,
                      'raw_value': 5390,
                      'qa_value': 64,
                      'row': 3,
                      'column': 4,
                      'acquired_at': '2026-10-22T17:12:07Z',
                    },
                  }),
                  200,
                );
              }
              return http.Response(
                jsonEncode({
                  'status': cached ? 'cached' : 'unavailable',
                  'error': 'AUTHENTICATION_REQUIRED',
                  'stale': true,
                  'data_age_days': 24,
                  'data': cached
                      ? {
                          'png_base64': png,
                          'bounds': [-93.6321, 42.0305, -93.6317, 42.031],
                          'provider': 'SYNTHETIC TEST FIXTURE',
                          'product': 'HLSS30_VI',
                          'version': '2.0',
                          'acquired_at': '2026-10-22T17:12:07Z',
                          'retrieved_at': '2026-11-15T00:00:00Z',
                          'resolution_m': 30,
                          'quality': 'partial',
                          'coverage_pct': 50,
                          'valid_pixels': 2,
                          'polygon_pixels': 4,
                          'granule_id': 'SYNTHETIC TEST',
                          'qa_policy': 'Synthetic unit-test policy',
                          'coverage_definition':
                              'Accepted native centres / polygon centres',
                          'display_resampling': 'nearest',
                        }
                      : null,
                }),
                200,
              );
            }),
            baseUri: Uri.parse('http://127.0.0.1:8021'),
          );
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                platformFarmClientProvider.overrideWithValue(
                  PlatformFarmClient(transport),
                ),
                profileStoreProvider.overrideWithValue(MemoryProfileStore()),
              ],
              child: MaterialApp(
                theme: fsTheme(),
                home: const Scaffold(
                  body: SingleChildScrollView(child: NdviPanel()),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(requestedBounds?.split(',').length, 4);
          expect(
            find.text('NDVI · dimensionless numerical scale'),
            cached ? findsOneWidget : findsNothing,
          );
          if (cached) {
            expect(
              find.textContaining('valid coverage 50% (2/4 cell centres)'),
              findsOneWidget,
            );
            expect(
              find.textContaining('STALE · Cached real acquisition'),
              findsOneWidget,
            );
            await tester.ensureVisible(find.text('Inspect map centre'));
            await tester.tap(find.text('Inspect map centre'));
            await tester.pumpAndSettle();
            expect(inspections, 1);
            expect(
              find.textContaining('NDVI 0.5390 · raw 5390 × 0.0001'),
              findsOneWidget,
            );
          } else {
            expect(find.text('Satellite layer unavailable'), findsOneWidget);
            expect(
              find.textContaining('Earthdata authorization is not configured'),
              findsOneWidget,
            );
            expect(find.text('Inspect map centre'), findsNothing);
          }
          await tester.ensureVisible(find.byType(SwitchListTile));
          if (cached) {
            await tester.tap(find.byType(SwitchListTile));
          } else {
            expect(
              tester
                  .widget<SwitchListTile>(find.byType(SwitchListTile))
                  .onChanged,
              isNull,
            );
            expect(
              tester.widget<Slider>(find.byType(Slider)).onChanged,
              isNull,
            );
          }
          await tester.pumpAndSettle();
          expect(
            tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
            false,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        },
      );
    }
  }
}
