import 'dart:convert';
import 'dart:io';

import 'package:earthsync/app/strings.dart';
import 'package:earthsync/data/engine/engine_envelope.dart';
import 'package:earthsync/data/models/farm_boundary.dart';
import 'package:earthsync/data/models/field_analysis.dart';
import 'package:earthsync/design/theme.dart';
import 'package:earthsync/features/home/home_shell.dart';
import 'package:earthsync/features/map/gibs_layer.dart';
import 'package:earthsync/state/providers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Ready extends AnalysisNotifier {
  _Ready(this.a);
  final FieldAnalysis a;
  @override
  AnalysisState build() => AnalysisReady(a);
}

final _farm = FarmBoundary(const [
  LatLng(16.8650, 96.1940),
  LatLng(16.8650, 96.1960),
  LatLng(16.8670, 96.1960),
  LatLng(16.8670, 96.1940),
]);

Future<Widget> _shell({required bool withFarm}) async {
  SharedPreferences.setMockInitialValues({
    'farmer_draft_v1': jsonEncode(
      FarmerDraft(
        latitude: 16.866,
        longitude: 96.195,
        currentCrop: 'rice',
        farm: withFarm ? _farm : null,
      ).toJson(),
    ),
  });
  final prefs = await SharedPreferences.getInstance();
  final a = fieldAnalysisFromEnvelope(
    File('test/fixtures/engine_success_envelope.json').readAsStringSync(),
  );
  return ProviderScope(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      analysisProvider.overrideWith(() => _Ready(a)),
    ],
    child: MaterialApp(
      theme: fsLightTheme(),
      home: const HomeShell(initialTab: 3),
    ),
  );
}

void main() {
  test('newest-image tile URL asks GIBS for its default (latest) time', () {
    final url = GibsLayerConfig.plantHealth.tileUrlAt(
      const LatLng(16.866, 96.195),
    );
    expect(url, contains('/MODIS_Terra_NDVI_8Day/default/default/'));
    expect(url, endsWith('/9/231/392.png'));
  });

  test('date label says it is the newest 8-day image, with its date', () {
    expect(plantHealthDateLabel(null), S.plantHealthNewest);
    expect(
      plantHealthDateLabel(DateTime.utc(2026, 11, 13)),
      '${S.plantHealthNewest}: 13 Nov 2026',
    );
  });

  testWidgets('with a farm, plant health is clipped to the farm border', (
    tester,
  ) async {
    await tester.pumpWidget(await _shell(withFarm: true));
    await tester.pumpAndSettle();
    expect(find.byType(ClipToPolygon), findsNothing);

    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pumpAndSettle();
    expect(find.byType(ClipToPolygon), findsOneWidget);
    expect(find.textContaining(S.insideFarmOnly), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a farm the switch is off and asks to mark the farm', (
    tester,
  ) async {
    await tester.pumpWidget(await _shell(withFarm: false));
    await tester.pumpAndSettle();
    final sw = tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch));
    expect(sw.onChanged, isNull);
    expect(find.text(S.markFarmForHealth), findsOneWidget);
    expect(find.byType(ClipToPolygon), findsNothing);
  });
}
