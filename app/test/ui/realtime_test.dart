// Synthetic transport fixtures; never evidence of operational live providers.
import 'dart:convert';
import 'dart:async';
import 'package:earthsync/data/platform_farms.dart';
import 'package:earthsync/data/platform_transport.dart';
import 'package:earthsync/features/realtime/realtime_panel.dart';
import 'package:earthsync/state/platform_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('cache timeout ends loading and leaves a usable retry gap', (
    tester,
  ) async {
    final first = Completer<http.Response>();
    var gets = 0;
    final client = PlatformFarmClient(
      PlatformTransport(
        MockClient((request) async {
          if (request.method == 'POST') return http.Response('{}', 202);
          gets++;
          return gets == 1 ? first.future : http.Response('{}', 503);
        }),
        baseUri: Uri.parse('http://127.0.0.1:8021'),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          platformFarmClientProvider.overrideWithValue(client),
          platformFarmProvider.overrideWith((ref) async => null),
        ],
        child: const MaterialApp(home: RealtimeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 31));
    await tester.pump();
    expect(
      find.textContaining('Local monitoring service could not be reached.'),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Refresh'),
          )
          .onPressed,
      isNotNull,
    );
    expect(gets, 1);
    await tester.pump(const Duration(seconds: 13));
    expect(gets, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(gets, 2);
    first.complete(http.Response('{}', 503));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  for (final width in [390.0, 1280.0]) {
    for (final language in ['en', 'my']) {
      testWidgets('monitoring preserves failed alert state at $width $language', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        try {
          tester.view.physicalSize = Size(width, 950);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final transport = PlatformTransport(
            MockClient((request) async {
              if (request.method == 'POST') return http.Response('{}', 202);
              return http.Response(
                jsonEncode({
                  'location': {
                    'name': 'Ames public reference',
                    'lat': 42.0308,
                    'lon': -93.6319,
                    'timezone': 'America/Chicago',
                  },
                  'worker_running': true,
                  'sources': {
                    'iowa_station': {
                      'source': 'iowa_station',
                      'data_type': 'LIVE_STATION_OBSERVATION',
                      'status': 'FRESH',
                      'data': {
                        'stations': [],
                        'measurements': [
                          {
                            'station_id': 'AMFI4',
                            'variable': 'air_temperature',
                            'value': 10,
                            'unit': '°C',
                            'observed_at': '2026-11-15T00:00:00Z',
                            'observed_local': '2026-11-14T18:00:00-06:00',
                            'depth_cm': null,
                            'status': 'FRESH',
                            'quality_flag': '',
                          },
                        ],
                      },
                    },
                    'nws_alerts': {
                      'source': 'nws_alerts',
                      'data_type': 'OFFICIAL_CURRENT_ALERT',
                      'status': 'CACHED_REAL_STALE',
                      'error': 'PROVIDER_OUTAGE',
                      'last_success_at': '2026-11-15T00:00:00Z',
                      'message':
                          'No active official alerts found at the last successful check.',
                      'data': {'alerts': []},
                    },
                  },
                  'scientific_status':
                      '60 blocked rule candidates; zero approved executable crop-suitability recommendations.',
                  'satellite_status': {'hls_ndvi': 'UNAVAILABLE'},
                }),
                200,
                headers: {'content-type': 'application/json'},
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
                platformFarmProvider.overrideWith((ref) async => null),
              ],
              child: MaterialApp(
                locale: Locale(language),
                supportedLocales: const [Locale('en'), Locale('my')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                home: const RealtimeScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .getSemantics(find.textContaining('AMFI4 · air_temperature'))
                .label,
            contains('2026-11-15T00:00:00Z'),
          );
          expect(
            find.text('Official alert status could not be verified.'),
            findsOneWidget,
          );
          expect(
            find.text(
              'No active official alerts found at the last successful check.',
            ),
            findsNothing,
          );
          expect(
            find.textContaining('60 blocked rule candidates'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        } finally {
          semantics.dispose();
        }
      });
    }
  }
  testWidgets('changing location discards an in-flight prior location', (
    tester,
  ) async {
    // The panel must never display Iowa data under a Myanmar selection.
    final delayed = Completer<http.Response>();
    final client = PlatformFarmClient(
      PlatformTransport(
        MockClient((r) async {
          if (r.method == 'GET' && r.url.path.endsWith('/ames')) {
            return delayed.future;
          }
          return http.Response('{}', r.method == 'POST' ? 202 : 503);
        }),
        baseUri: Uri.parse('http://127.0.0.1:8021'),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          platformFarmClientProvider.overrideWithValue(client),
          platformFarmProvider.overrideWith((ref) async => null),
        ],
        child: const MaterialApp(home: RealtimeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Yangon, Myanmar').last);
    await tester.pumpAndSettle();
    delayed.complete(
      http.Response(
        jsonEncode({
          'sources': {},
          'satellite_status': {},
          'scientific_status': 'AMFI4 old observation',
          'worker_running': true,
        }),
        200,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Local monitoring service could not be reached.'),
      findsOneWidget,
    );
    expect(find.textContaining('AMFI4'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
