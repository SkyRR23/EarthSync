import 'dart:convert';
import 'package:earthsync/data/platform_farms.dart';
import 'package:earthsync/data/platform_transport.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earthsync/data/models/farm_boundary.dart';
import 'package:earthsync/data/models/home_profile.dart';
import 'package:earthsync/data/local/profile_store.dart';
import 'package:earthsync/state/home_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final square = [
    GeoPoint(0, 0),
    GeoPoint(0, .001),
    GeoPoint(.001, .001),
    GeoPoint(.001, 0),
  ];
  test('spherical area, reversed ring and point association', () {
    final b = FarmBoundary(square);
    expect(b.areaSquareMetres, closeTo(12364.3459, .01));
    expect(
      FarmBoundary(square.reversed.toList()).areaSquareMetres,
      closeTo(b.areaSquareMetres, .01),
    );
    expect(b.covers(GeoPoint(.0005, .0005)), true);
    expect(b.covers(GeoPoint(0, 0)), true);
    expect(b.covers(GeoPoint(1, 1)), false);
    expect(FarmBoundary.fromJson(b.toJson()).vertices, square);
  });
  test('suggested pin remains inside a concave field in either ring order', () {
    final ring = [
      GeoPoint(0, 0),
      GeoPoint(0, .004),
      GeoPoint(.001, .004),
      GeoPoint(.001, .001),
      GeoPoint(.004, .001),
      GeoPoint(.004, 0),
    ];
    for (final points in [ring, ring.reversed.toList()]) {
      final boundary = FarmBoundary(points);
      expect(boundary.covers(GeoPoint(.002, .002)), isFalse);
      expect(boundary.covers(boundary.interiorPoint), isTrue);
    }
  });
  test(
    'reject self-intersection, degenerate, adjacent duplicates, antimeridian',
    () {
      for (final ring in [
        [square[0], square[2], square[1], square[3]],
        [GeoPoint(0, 0), GeoPoint(1, 1), GeoPoint(2, 2)],
        [square[0], square[0], square[1], square[2]],
        [GeoPoint(0, 179), GeoPoint(1, -179), GeoPoint(2, 179)],
      ]) {
        expect(() => FarmBoundary(ring), throwsFormatException);
      }
    },
  );
  test(
    'old point-only profile and new boundary survive device store reload',
    () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(homeProfileProvider.future);
      await c
          .read(homeProfileProvider.notifier)
          .confirmFarm(GeoPoint(.0005, .0005), 'Test field');
      expect((await LocalProfileStore().load()).farm!.boundary, null);
      await c
          .read(homeProfileProvider.notifier)
          .confirmFarm(
            GeoPoint(.0005, .0005),
            'Test field',
            boundary: FarmBoundary(square),
          );
      final saved = (await LocalProfileStore().load()).farm!;
      expect(saved.boundary!.vertices, square);
      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);
      expect(
        (await restarted.read(
          homeProfileProvider.future,
        )).farm!.boundary!.vertices,
        square,
      );
      await expectLater(
        c
            .read(homeProfileProvider.notifier)
            .confirmFarm(
              GeoPoint(2, 2),
              'Outside',
              boundary: FarmBoundary(square),
            ),
        throwsFormatException,
      );
      expect(
        (await LocalProfileStore().load()).farm!.confirmedAt,
        saved.confirmedAt,
      );
    },
  );
  test(
    'remote boundary comparison ignores JSON object key order and rejects changed vertices',
    () async {
      final local = ConfirmedFarm(
        id: 'synthetic-local',
        point: GeoPoint(.0005, .0005),
        confirmedAt: DateTime.utc(2026, 11, 14),
        boundary: FarmBoundary(square),
      );
      PlatformFarmClient client(List<dynamic> coordinates) =>
          PlatformFarmClient(
            PlatformTransport(
              MockClient(
                (_) async => http.Response(
                  jsonEncode({
                    'local_profile_id': local.id,
                    'revision': farmRevision(local),
                    'farm': {
                      'id': 'synthetic-remote',
                      'confirmed_point': local.point.toJson(),
                      'production_system': 'rainfed',
                      'confirmed_polygon': {
                        'coordinates': coordinates,
                        'type': 'Polygon',
                      },
                    },
                  }),
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'},
                ),
              ),
              baseUri: Uri.parse('http://127.0.0.1:8031'),
            ),
          );
      expect(
        (await client(
          local.boundary!.toJson()['coordinates'] as List,
        ).link(local))!.point,
        local.point,
      );
      final changed = FarmBoundary([
        GeoPoint(0, 0),
        GeoPoint(0, .002),
        GeoPoint(.002, .002),
        GeoPoint(.002, 0),
      ]);
      await expectLater(
        client(changed.toJson()['coordinates'] as List).link(local),
        throwsFormatException,
      );
    },
  );
}
