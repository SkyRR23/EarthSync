import 'package:earthsync/app/router.dart';
import 'package:earthsync/design/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earthsync/state/home_provider.dart';
import 'home_test_support.dart';

Widget _app(String start) {
  final router = buildRouter()..go(start);
  return ProviderScope(
    overrides: [
      profileStoreProvider.overrideWithValue(
        MemoryProfileStore(confirmedProfile()),
      ),
    ],
    child: MaterialApp.router(theme: fsTheme(), routerConfig: router),
  );
}

void main() {
  testWidgets('single-choice answer auto-advances to next question', (t) async {
    await t.pumpWidget(_app('/question/1'));
    await t.pumpAndSettle();
    expect(find.text('Question 1 of 6'), findsOneWidget);
    await t.tap(find.text('Rice'));
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(find.text('Question 2 of 6'), findsOneWidget);
  });

  testWidgets('"I don\'t know" is visible without scrolling on crop question', (
    t,
  ) async {
    t.view.physicalSize = const Size(412 * 3, 880 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app('/question/1'));
    await t.pumpAndSettle();
    expect(find.text("I don't know").hitTestable(), findsOneWidget);
  });
}
