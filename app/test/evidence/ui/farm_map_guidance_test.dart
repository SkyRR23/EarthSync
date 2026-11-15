import 'package:earthsync/evidence/data/models/farm_boundary.dart';
import 'package:earthsync/evidence/data/models/home_profile.dart';
import 'package:earthsync/evidence/features/map/farm_map_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 1100.0]) {
    testWidgets(
      'outside pin can be fixed before confirming outline at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var point = GeoPoint(.005, .005);
        final boundary = FarmBoundary([
          GeoPoint(0, 0),
          GeoPoint(0, .002),
          GeoPoint(.002, .002),
          GeoPoint(.002, 0),
        ]);
        var editing = false, confirmed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: StatefulBuilder(
                  builder: (context, update) => FarmMapEditor(
                    point: point,
                    boundary: boundary,
                    onPoint: (value) => update(() => point = value),
                    onEditing: (value) => editing = value,
                    onBoundary: (value) => confirmed = value != null,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Edit field outline'));
        await tester.tap(find.text('Edit field outline'));
        await tester.pumpAndSettle();
        expect(editing, isTrue);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Use this outline'),
              )
              .onPressed,
          isNull,
        );
        await tester.ensureVisible(find.text('Move farm pin inside outline'));
        await tester.tap(find.text('Move farm pin inside outline'));
        await tester.pumpAndSettle();
        expect(boundary.covers(point), isTrue);
        expect(confirmed, isFalse);
        await tester.ensureVisible(find.text('Use this outline'));
        await tester.tap(find.text('Use this outline'));
        await tester.pumpAndSettle();
        expect(editing, isFalse);
        expect(confirmed, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
