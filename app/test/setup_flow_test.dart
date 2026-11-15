import 'package:earthsync/app/router.dart';
import 'package:earthsync/app/strings.dart';
import 'package:earthsync/data/models/farmer_input.dart';
import 'package:earthsync/design/theme.dart';
import 'package:earthsync/features/onboarding/setup_flow.dart';
import 'package:earthsync/state/providers.dart';
import 'package:earthsync/state/today.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pump(WidgetTester t, String start) async {
  t.view.physicalSize = const Size(412 * 3, 915 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [prefsProvider.overrideWithValue(prefs)],
  );
  addTearDown(c.dispose);
  final router = buildRouter()..go(start);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(
        theme: fsLightTheme(),
        routerConfig: router,
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(disableAnimations: true),
          child: child!,
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return c;
}

Future<void> _tap(WidgetTester t, String text) async {
  await t.ensureVisible(find.text(text).last);
  await t.tap(find.text(text).last);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('welcome -> step 1 asks for location (1 / 7)', (t) async {
    await _pump(t, '/');
    expect(find.text(S.setupTitle), findsOneWidget);
    await _tap(t, S.getStartedSetup);
    expect(find.text(S.allowLocationTitle), findsWidgets);
    expect(find.text(S.stepSlash(1, kSetupSteps)), findsOneWidget);
    expect(find.text(S.locationPrivacy), findsOneWidget);
    expect(find.text(S.pinOnMap), findsOneWidget);
  });

  testWidgets('steps 2-7 save every answer and end on home', (t) async {
    final c = await _pump(t, '/setup/2');
    c.read(farmerDraftProvider.notifier).setLocation(16.85, 96.15);

    // 2 · farm
    expect(find.text(S.stepSlash(2, kSetupSteps)), findsOneWidget);
    await t.enterText(find.byType(TextField), '  River field ');
    await _tap(t, S.livestockFarm);
    expect(find.text(S.livestockNote), findsOneWidget);
    await _tap(t, S.cropFarm);
    await _tap(t, S.next);

    // 3 · crops (multi-select; "Other" shows Myanmar pulses and oilseeds)
    await _tap(t, 'Rice');
    await _tap(t, S.cropOther);
    await _tap(t, 'Mung bean');
    expect(find.text(S.cropsFirstNote), findsOneWidget);
    await _tap(t, S.next);

    // 4 · water
    await _tap(t, '💧 ${S.waterSome}');
    await _tap(t, '🌊 ${S.drainLong}');
    await _tap(t, S.next);

    // 5 · season
    await t.tap(find.text(S.selectMonth).first); // planting
    await t.pumpAndSettle();
    await _tap(t, 'June');
    expect(find.text('June'), findsOneWidget);
    await _tap(t, S.next);

    // 6 · alerts: turn water reminders off
    expect(find.byType(CupertinoSwitch), findsNWidgets(3));
    await t.tap(find.byType(CupertinoSwitch).at(1));
    await t.pumpAndSettle();
    await _tap(t, S.finishSetup);

    // 7 · account (no Firebase in tests: just continue)
    expect(find.text(S.accountTitle), findsOneWidget);
    await _tap(t, S.next);

    final d = c.read(farmerDraftProvider);
    expect(d.farmName, 'River field');
    expect(d.farmType, 'crop');
    expect(d.crops, ['rice', 'mung_bean']);
    expect(d.currentCrop, 'rice');
    expect((d.irrigation, d.drainage), (Irrigation.partial, Drainage.poor));
    expect(d.plantingMonth, 6);
    expect(d.isComplete, true);
    expect(c.read(alertPrefsProvider).water, false);
    expect(c.read(alertPrefsProvider).pests, true);
    expect(find.text(S.tabCrops), findsOneWidget); // home tabs
    expect(t.takeException(), isNull);
  });
}
