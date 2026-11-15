import 'dart:convert';

import 'package:earthsync/app/strings.dart';
import 'package:earthsync/data/environment/greenness.dart';
import 'package:earthsync/data/models/farm_boundary.dart';
import 'package:earthsync/design/theme.dart';
import 'package:earthsync/features/home/field_overview.dart';
import 'package:earthsync/state/providers.dart';
import 'package:earthsync/state/today.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

final farm = FarmBoundary(const [
  LatLng(16.8506, 96.1494),
  LatLng(16.8506, 96.1509),
  LatLng(16.8493, 96.1509),
  LatLng(16.8493, 96.1494),
]);

const sq = [
  [16.85, 96.15],
  [16.85, 96.1503],
  [16.8497, 96.1503],
  [16.8497, 96.15],
];

final answer = {
  'status': 'success',
  'latest': {
    'date': '2026-11-02',
    'sensor': 'Sentinel-2',
    'pixels_inside': 3,
    'pixels_clear': 2,
    'ndvi_mean': 0.62,
    'cells': [
      {'ndvi': 0.6, 'corners': sq},
      {'ndvi': 0.64, 'corners': sq},
      {'ndvi': null, 'corners': sq},
    ],
  },
  'previous': {
    'date': '2026-10-28',
    'sensor': 'Landsat',
    'pixels_inside': 3,
    'pixels_clear': 3,
    'ndvi_mean': 0.515,
  },
};

void main() {
  test('reads the backend answer and words it plainly', () async {
    late Uri asked;
    final g = await GreennessClient(
      baseUrl: 'https://example.test',
      client: MockClient((r) async {
        asked = r.url;
        return http.Response(jsonEncode(answer), 200);
      }),
    ).fetch(farm.corners);
    expect(asked.path, '/api/v1/environment/greenness');
    expect(asked.queryParameters['farm']!.split(','), hasLength(8));
    expect(g.latest!.cells, hasLength(3));
    expect(g.latest!.cells.last.ndvi, isNull);
    expect(
      greenCaption(g),
      'Green cover 0.62 on 2 Nov · 0.52 on 28 Oct. '
      '2 of 3 pixels clear · Sentinel-2, NASA HLS 30 m. ${S.greenScale}.',
    );
    expect(ndviColor(null), isNot(ndviColor(0.7)));
  });

  testWidgets('plant health on: NASA HLS pixels drawn inside the farm', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'farmer_draft_v1': jsonEncode(
        FarmerDraft(
          latitude: 16.85,
          longitude: 96.15,
          currentCrop: 'rice',
          farm: farm,
        ).toJson(),
      ),
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          greennessClientProvider.overrideWithValue(
            GreennessClient(
              baseUrl: 'https://example.test',
              client: MockClient(
                (_) async => http.Response(jsonEncode(answer), 200),
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: fsLightTheme(),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const FieldTab(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pumpAndSettle();
    final cells = tester
        .widgetList<PolygonLayer>(find.byType(PolygonLayer))
        .expand((l) => l.polygons)
        .where((p) => p.points.first == const LatLng(16.85, 96.15));
    expect(cells, hasLength(3));
    expect(find.textContaining('Green cover 0.62 on 2 Nov'), findsOneWidget);
    expect(find.text(S.greenDense), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
