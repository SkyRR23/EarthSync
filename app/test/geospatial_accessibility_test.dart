import 'dart:convert';
import 'dart:io';
import 'package:earthsync/data/models/home_profile.dart';
import 'package:earthsync/data/platform_farms.dart';
import 'package:earthsync/data/platform_transport.dart';
import 'package:earthsync/features/field/geospatial_intelligence_panel.dart';
import 'package:earthsync/state/platform_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets(
    'cached real forecast exposes issuance gap and provenance to accessibility',
    (tester) async {
      // Cached actual NOAA source data, mocked local API only; no provider calls.
      final job =
          jsonDecode(
                File(
                  '../docs/integration/7g/evidence/browser/forecast-job.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final farm = PlatformFarm.fromJson({
        'id': 'synthetic-ui-farm-id',
        'confirmed_point': GeoPoint(42.0308, -93.6319).toJson(),
        'production_system': 'rainfed',
      });
      final client = PlatformFarmClient(
        PlatformTransport(
          MockClient(
            (_) async => http.Response(
              jsonEncode([job]),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
          baseUri: Uri.parse('http://127.0.0.1:8031'),
        ),
      );
      final semantics = tester.ensureSemantics();
      try {
        tester.view.physicalSize = const Size(1280, 6000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [platformFarmClientProvider.overrideWithValue(client)],
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: GeospatialIntelligencePanel(farm: farm),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final issuance = find.textContaining(
          'Publication/issuance time: unavailable.',
        );
        expect(issuance, findsOneWidget);
        expect(
          tester.getSemantics(issuance).label,
          contains('Publication/issuance time: unavailable.'),
        );
        expect(
          tester
              .getSemantics(
                find.textContaining(
                  'This saved temperature snapshot does not contain official warnings',
                ),
              )
              .label,
          contains(
            'Open Real-time EarthSync for separately dated station, forecast and alert sources.',
          ),
        );
        expect(
          find.textContaining('NASA satellite vegetation'),
          findsOneWidget,
        );
      } finally {
        semantics.dispose();
      }
    },
  );
}
