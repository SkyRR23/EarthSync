import 'package:earthsync/app/router.dart';
import 'package:earthsync/data/environment/nasa_power_client.dart';
import 'package:earthsync/data/location/device_location.dart';
import 'package:earthsync/data/models/home_profile.dart';
import 'package:earthsync/design/theme.dart';
import 'package:earthsync/state/dashboard_provider.dart';
import 'package:earthsync/state/home_provider.dart';
import 'package:earthsync/state/local_farm_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'home_test_support.dart';

Future<void> launch(
  WidgetTester t,
  MemoryProfileStore store,
  FakeDeviceLocation location, {
  String start = '/',
}) async {
  t.view.physicalSize = const Size(412, 880);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final router = buildRouter()..go(start);
  final localStore = await memoryFarmStore(t);
  addTearDown(router.dispose);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        localFarmStoreProvider.overrideWith((ref) async => localStore),
        profileStoreProvider.overrideWithValue(store),
        deviceLocationProvider.overrideWithValue(location),
        dashboardClimateClientProvider.overrideWithValue(
          NasaPowerClient(
            client: MockClient((_) async => http.Response('', 503)),
          ),
        ),
      ],
      child: MaterialApp.router(theme: fsTheme(), routerConfig: router),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tapText(WidgetTester t, String text) async {
  final finder = find.text(text);
  if (finder.evaluate().isEmpty) {
    t.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  } else {
    await t.ensureVisible(finder);
  }
  await t.pumpAndSettle();
  await t.tap(finder.hitTestable());
  await t.pumpAndSettle();
}

void main() {
  testWidgets('first launch offers three choices without requesting GPS', (
    t,
  ) async {
    final location = FakeDeviceLocation();
    await launch(t, MemoryProfileStore(), location);
    expect(find.text('Welcome to EarthSync'), findsOneWidget);
    expect(find.text('Use My Location'), findsOneWidget);
    expect(find.text('Choose an Area'), findsOneWidget);
    expect(find.text('Skip for Now'), findsOneWidget);
    expect(location.calls, 0);
  });
  testWidgets('allowed location opens Your Area without confirming a farm', (
    t,
  ) async {
    final store = MemoryProfileStore();
    final location = FakeDeviceLocation();
    await launch(t, store, location);
    await tapText(t, 'Use My Location');
    expect(find.text('Your Area'), findsOneWidget);
    expect(find.text('Add My Farm'), findsOneWidget);
    expect(find.text('Open Farm Questionnaire'), findsNothing);
    expect(store.profile.farm, null);
    expect(store.profile.userLocation, isA<ApproximateArea>());
    expect(location.calls, 1);
  });
  for (final reason in [
    LocationUnavailableReason.denied,
    LocationUnavailableReason.unavailable,
  ]) {
    testWidgets('$reason location never blocks the dashboard', (t) async {
      final store = MemoryProfileStore();
      await launch(
        t,
        store,
        FakeDeviceLocation(failure: LocationFailure('Choose manually', reason)),
      );
      await tapText(t, 'Use My Location');
      expect(find.text('Explore the world'), findsOneWidget);
      expect(find.text('Add My Farm'), findsOneWidget);
      expect(store.profile.farm, null);
      expect((store.profile.userLocation as UnknownLocation).reason, reason);
    });
  }
  testWidgets(
    'skip opens global exploration and restores for a returning user',
    (t) async {
      final store = MemoryProfileStore();
      final location = FakeDeviceLocation();
      await launch(t, store, location);
      await tapText(t, 'Skip for Now');
      expect(find.text('Explore the world'), findsOneWidget);
      expect(location.calls, 0);
      await t.pumpWidget(const SizedBox.shrink());
      await launch(t, store, location);
      expect(find.text('Welcome to EarthSync'), findsNothing);
      expect(find.text('Explore the world'), findsOneWidget);
    },
  );
  testWidgets('manual global area is saved without GPS or farm confirmation', (
    t,
  ) async {
    final store = MemoryProfileStore();
    final location = FakeDeviceLocation();
    await launch(t, store, location);
    await tapText(t, 'Choose an Area');
    await t.enterText(find.byKey(const Key('latitude')), '-23.55');
    await t.enterText(find.byKey(const Key('longitude')), '-46.63');
    await tapText(t, 'Save Area');
    expect(find.text('Your Area'), findsOneWidget);
    expect(find.text('Add My Farm'), findsOneWidget);
    expect(
      (store.profile.userLocation as ApproximateArea).point,
      GeoPoint(-23.55, -46.63),
    );
    expect(store.profile.farm, null);
    expect(location.calls, 0);
  });
  testWidgets('farm needs explicit confirmation, persists, and can be edited', (
    t,
  ) async {
    final store = MemoryProfileStore(const HomeProfile(onboarded: true));
    await launch(t, store, FakeDeviceLocation());
    await tapText(t, 'Add My Farm');
    await t.enterText(find.byKey(const Key('latitude')), '1.2');
    await t.enterText(find.byKey(const Key('longitude')), '2.3');
    await t.enterText(find.byType(TextFormField).first, 'East field');
    final save = find.widgetWithText(FilledButton, 'Save Confirmed Farm');
    if (save.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        save,
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    expect(t.widget<FilledButton>(save).onPressed, null);
    await tapText(t, 'I confirm this point marks my field.');
    await tapText(t, 'Save Confirmed Farm');
    expect(find.text('East field'), findsWidgets);
    await t.scrollUntilVisible(
      find.text('Open Farm Questionnaire'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Open Farm Questionnaire'), findsOneWidget);
    final farmId = store.profile.farm!.id;
    await tapText(t, 'Edit My Farm');
    await t.enterText(find.byKey(const Key('latitude')), '1.4');
    if (save.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        save,
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    expect(t.widget<FilledButton>(save).onPressed, null);
    await tapText(t, 'I confirm this point marks my field.');
    await tapText(t, 'Save Confirmed Farm');
    expect(store.profile.farm!.id, farmId);
    expect(store.profile.farm!.point, GeoPoint(1.4, 2.3));
    await tapText(t, 'Open Farm Questionnaire');
    expect(find.text('Question 1 of 6'), findsOneWidget);
  });
  testWidgets('unconfirmed direct questionnaire link offers area exploration', (
    t,
  ) async {
    await launch(
      t,
      MemoryProfileStore(),
      FakeDeviceLocation(),
      start: '/question/1',
    );
    expect(find.text('Farm confirmation needed'), findsOneWidget);
    await tapText(t, 'Go to Dashboard');
    expect(find.text('Explore the world'), findsOneWidget);
  });
}
