import 'package:earthsync/main.dart';
import 'package:earthsync/state/home_provider.dart';
import 'package:earthsync/data/models/home_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../home_test_support.dart';

void main() {
  testWidgets('desktop rail survives the nested route semantics barrier', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1050);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
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
    expect(find.bySemanticsLabel('Real-Time EarthSync'), findsOneWidget);
    expect(find.bySemanticsLabel('Satellite NDVI Map'), findsOneWidget);
    expect(find.bySemanticsLabel('Laboratory Reports'), findsOneWidget);
    await tester.tap(find.text('Satellite NDVI Map'));
    await tester.pumpAndSettle();
    expect(find.text('Satellite NDVI map'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });
}
