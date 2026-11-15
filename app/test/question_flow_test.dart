import 'package:earthsync/app/router.dart';
import 'package:earthsync/app/strings.dart';
import 'package:earthsync/data/models/farmer_input.dart';
import 'package:earthsync/design/theme.dart';
import 'package:earthsync/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(String start, {FarmerDraft? initialDraft}) {
  final router = buildRouter()..go(start);
  return ProviderScope(
    overrides: [
      if (initialDraft != null)
        farmerDraftProvider.overrideWith(() => _PresetDraft(initialDraft)),
    ],
    child: MaterialApp.router(theme: fsTheme(), routerConfig: router),
  );
}

class _PresetDraft extends FarmerDraftNotifier {
  _PresetDraft(this._initial);
  final FarmerDraft _initial;
  @override
  FarmerDraft build() => _initial;
}

void main() {
  testWidgets('single-choice answer auto-advances to next question', (t) async {
    await t.pumpWidget(_app('/question/1'));
    await t.pumpAndSettle();
    expect(find.text('1 of 3'), findsOneWidget);
    await t.tap(find.text('Rice'));
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(find.text('2 of 3'), findsOneWidget);
  });

  testWidgets('after question 3 the flow goes to /home', (t) async {
    await t.pumpWidget(
      _app(
        '/question/3',
        initialDraft: const FarmerDraft(
          latitude: kSampleLat,
          longitude: kSampleLon,
          currentCrop: 'rice',
          irrigation: Irrigation.full,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('3 of 3'), findsOneWidget);
    await t.tap(find.text(S.drainFast));
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(find.text(S.tabField), findsOneWidget);
  });

  testWidgets('"Not sure" is visible without scrolling on crop question', (
    t,
  ) async {
    t.view.physicalSize = const Size(412 * 3, 880 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app('/question/1'));
    await t.pumpAndSettle();
    expect(find.text(S.dontKnow).hitTestable(), findsOneWidget);
  });
}
