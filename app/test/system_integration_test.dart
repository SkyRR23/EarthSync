import 'dart:convert';
import 'dart:io';
import 'package:earthsync/data/engine/v03_engine.dart';
import 'package:earthsync/data/service_client.dart';
import 'package:earthsync/data/models/home_profile.dart';
import 'package:earthsync/features/field/assessment_screen.dart';
import 'package:earthsync/features/assistant/integrated_assistant.dart';
import 'package:earthsync/main.dart';
import 'package:earthsync/state/home_provider.dart';
import 'package:earthsync/state/integration_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'home_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final synthetic =
      jsonDecode(
            File(
              '../engine/tests/fixtures/v03/synthetic_request.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  late V03Result actual;
  setUpAll(() async {
    // Actual generated FRB loader + native Rust, not initMock or Dart arithmetic.
    actual = await V03Engine(
      ServiceClient(MockClient((_) async => http.Response('{}', 500))),
    ).analyze(V03Request.fromJson(synthetic));
  });
  test(
    'v03 native bridge preserves evidence, sources and all result states',
    () {
      expect(actual.synthetic, true);
      expect(actual.context, synthetic);
      expect(actual.findings, isNotEmpty);
      expect(
        actual.findings.any((f) => f['status'] == V03Status.supported.wire),
        true,
      );
      for (final status in V03Status.values) {
        final wire =
            jsonDecode(jsonEncode(actual.envelope)) as Map<String, dynamic>;
        wire['data']['findings'][0]['status'] = status.wire;
        expect(
          V03Status.decode(V03Result.decode(wire).findings.first['status']),
          status,
        );
      }
      expect(() => actual.envelope['data'] = {}, throwsUnsupportedError);
      expect(() => actual.context!['sources'].clear(), throwsUnsupportedError);
      expect(
        V03Result.decode({
          'status': 'error',
          'schema_version': v03Version,
          'error': {
            'status': V03Status.invalid.wire,
            'path': 'farm.point',
            'message': 'Invalid point',
          },
        }).validation!['path'],
        'farm.point',
      );
    },
  );
  testWidgets(
    'phone v03 results label synthetic arithmetic and retain details',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: V03ResultPanel(result: actual)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('SYNTHETIC SOFTWARE TEST'), findsOneWidget);
      expect(find.textContaining('whole-crop suitability'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'device area, manual area and confirmed farm remain separate after restore',
    () async {
      final store = MemoryProfileStore();
      final container = ProviderContainer(
        overrides: [profileStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      await container.read(homeProfileProvider.future);
      final notifier = container.read(homeProfileProvider.notifier);
      final device = GeoPoint(12, 13),
          manual = GeoPoint(42, -93),
          farm = GeoPoint(16.85, 96.15);
      await notifier.setArea(
        ApproximateArea(
          point: device,
          label: 'Device area',
          source: AreaSource.device,
        ),
      );
      await notifier.confirmFarm(farm, 'My field');
      await notifier.setArea(
        ApproximateArea(
          point: manual,
          label: 'Manual area',
          source: AreaSource.manual,
        ),
      );
      final restored = await store.load();
      expect(restored.approximateDeviceLocation, device);
      expect((restored.userLocation as ApproximateArea).point, manual);
      expect(restored.farm!.point, farm);
    },
  );
  test(
    'farm edits invalidate v03 results and discard old in-flight work',
    () async {
      final store = MemoryProfileStore(confirmedProfile());
      final client = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response(jsonEncode(synthetic), 200);
      });
      final container = ProviderContainer(
        overrides: [
          profileStoreProvider.overrideWithValue(store),
          integrationHttpProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);
      await container.read(homeProfileProvider.future);
      final running = container
          .read(assessmentProvider.notifier)
          .run(synthetic: true);
      await container
          .read(homeProfileProvider.notifier)
          .confirmFarm(GeoPoint(4, 5), 'Edited field');
      expect(container.read(assessmentProvider).result, null);
      await running;
      expect(container.read(assessmentProvider).result, null);
    },
  );
  testWidgets('main navigation opens assistant with no farm and no location', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileStoreProvider.overrideWithValue(
            MemoryProfileStore(const HomeProfile(onboarded: true)),
          ),
        ],
        child: const FieldShiftApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Explore the world'), findsOneWidget);
    await tester.tap(find.text('Assistant'));
    await tester.pumpAndSettle();
    expect(find.text('EarthSync assistant'), findsOneWidget);
    expect(find.textContaining('No confirmed farm'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test(
    'manual or skipped exploration does not send a previously saved device point',
    () async {
      final profile = HomeProfile(
        onboarded: true,
        approximateDeviceLocation: GeoPoint(12, 13),
        userLocation: ApproximateArea(
          point: GeoPoint(42, -93),
          label: 'Manual area',
          source: AreaSource.manual,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          profileStoreProvider.overrideWithValue(MemoryProfileStore(profile)),
          integrationHttpProvider.overrideWithValue(
            MockClient((_) async => http.Response('{}', 503)),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(homeProfileProvider.future);
      expect(
        container
            .read(integratedAssistantContextProvider(true))
            .approximateLocation,
        null,
      );
      await container.read(homeProfileProvider.notifier).skip();
      expect(
        container
            .read(integratedAssistantContextProvider(true))
            .approximateLocation,
        null,
      );
    },
  );
  test(
    'location-free assistant never fabricates context or decisions',
    () async {
      final container = ProviderContainer(
        overrides: [
          profileStoreProvider.overrideWithValue(
            MemoryProfileStore(const HomeProfile(onboarded: true)),
          ),
          integrationHttpProvider.overrideWithValue(
            MockClient((_) async => http.Response('{}', 503)),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(homeProfileProvider.future);
      final context = container.read(integratedAssistantContextProvider(false));
      expect(context.confirmedFarm, null);
      expect(context.selectedArea, null);
      expect(context.evidence, isEmpty);
      expect(context.decisions, isEmpty);
    },
  );
}
