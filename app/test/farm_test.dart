import 'package:earthsync/data/models/farm_boundary.dart';
import 'package:earthsync/data/models/field_analysis.dart';
import 'package:earthsync/design/components/scenario.dart';
import 'package:earthsync/features/home/climate_history.dart';
import 'package:earthsync/state/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  // About 213 m (east-west) x 222 m (north-south) near Yangon.
  const corners = [
    LatLng(16.8650, 96.1940),
    LatLng(16.8650, 96.1960),
    LatLng(16.8670, 96.1960),
    LatLng(16.8670, 96.1940),
  ];

  group('FarmBoundary', () {
    test('size of a small farm is about right', () {
      final f = FarmBoundary(corners);
      expect(f.isComplete, isTrue);
      expect(f.areaM2, closeTo(213 * 222, 1500));
      expect(f.areaAcres, closeTo(11.7, 0.5));
      expect(farmSizeLabel(f), 'About 12 acres');
    });

    test('centre is the middle of the farm', () {
      final c = FarmBoundary(corners).center;
      expect(c.latitude, closeTo(16.8660, 1e-6));
      expect(c.longitude, closeTo(96.1950, 1e-6));
    });

    test('corners tapped out of order never make a crossed shape', () {
      final crossed = FarmBoundary([
        corners[0],
        corners[2],
        corners[1],
        corners[3],
      ]);
      expect(crossed.areaM2, closeTo(FarmBoundary(corners).areaM2, 1));
    });

    test('survives saving and loading', () {
      final f = FarmBoundary(corners);
      final back = FarmBoundary.fromJson(f.toJson())!;
      expect(back.center.latitude, closeTo(f.center.latitude, 1e-9));
      expect(
        FarmBoundary.fromJson([
          [1, 2],
        ]),
        isNull,
      );
    });
  });

  group('FarmerDraft with a farm', () {
    test('analysis uses the farm centre, not the setup pin', () {
      final d = FarmerDraft(
        latitude: 17.5,
        longitude: 95.0,
        currentCrop: 'rice',
        farm: FarmBoundary(corners),
      );
      final input = d.toInput();
      expect(input.latitude, closeTo(16.8660, 1e-6));
      expect(input.longitude, closeTo(96.1950, 1e-6));
      expect(input.boundary.length, 4);
      expect(input.toJson()['field_boundary'], hasLength(4));
    });

    test('without a farm the setup pin is used', () {
      const d = FarmerDraft(latitude: 17.5, longitude: 95.0);
      expect(d.toInput().latitude, 17.5);
      expect(d.toInput().boundary, isEmpty);
    });

    test('farm survives JSON round trip', () {
      final d = FarmerDraft(
        latitude: 16.9,
        longitude: 96.2,
        farm: FarmBoundary(corners),
      );
      final back = FarmerDraft.fromJson(d.toJson());
      expect(back.hasFarm, isTrue);
      expect(back.fieldLatitude, closeTo(16.8660, 1e-6));
    });
  });

  group('Weather words', () {
    List<MonthlyClimate> months(List<double?> rain) => [
      for (final (i, r) in rain.indexed)
        MonthlyClimate(month: i + 1, rainMm: r),
    ];

    test('rain thirds come only from ranking the engine numbers', () {
      final m = months([5, 10, 20, 60, 200, 400, 500, 450, 380, 150, 40, null]);
      final r = rankRain(m);
      expect(r[11], MonthRain.unknown);
      expect(
        monthRuns(m, [for (final x in r) x == MonthRain.most]),
        'Jun – Aug',
      );
      expect(
        monthRuns(m, [for (final x in r) x == MonthRain.least]),
        'Jan – Mar',
      );
    });
  });

  group('Weather window', () {
    test('default is last full calendar year', () {
      final w = lastFullYear(DateTime.utc(2026, 11, 14));
      expect(
        [w.startYear, w.startMonth, w.endYear, w.endMonth],
        [2025, 1, 2025, 12],
      );
      w.validate(); // passes the team's own window rules
    });

    test('early in the year it steps back one more year', () {
      final w = lastFullYear(DateTime.utc(2027, 2, 3));
      expect([w.startYear, w.endYear], [2025, 2025]);
    });
  });

  group('Crop order', () {
    test('best fit first, engine order kept within a fit word', () {
      RotationScenario s(String id, Feasibility f, {bool base = false}) =>
          RotationScenario(
            id: id,
            title: id,
            isBaseline: base,
            steps: const [],
            eligibility: f,
            likelyBenefits: const [],
            risks: const [],
            limitations: const [],
            evidenceIds: const [],
          );
      final sorted = sortedByFit([
        s('now', Feasibility.constrained, base: true),
        s('a', Feasibility.conflicts),
        s('b', Feasibility.supported),
        s('c', Feasibility.unknown),
        s('d', Feasibility.supported),
      ]);
      expect([for (final e in sorted) e.$1.id], ['b', 'd', 'now', 'c', 'a']);
    });
  });
}
