import 'package:earthsync/data/environment/soil_property_layer.dart';
import 'package:earthsync/data/models/home_profile.dart';
import 'package:flutter_test/flutter_test.dart';

// Synthetic transport fixture; never bundled as operational soil evidence.
Map<String, dynamic> layer({Object? value = 6.4}) => {
  'schema_version': 'earthsync.soil-map.v1',
  'status': value == null ? 'no_valid_pixels' : 'available',
  'provider': 'ISRIC SoilGrids',
  'property': 'phh2o',
  'unit': 'pH',
  'resolution_m': 250,
  'depth_cm': [0, 5],
  'usable_for_assessment': false,
  'source_url': 'https://files.isric.org/soilgrids/latest/data/phh2o/test.tif',
  'source_sha256': List.filled(64, 'a').join(),
  'retrieved_at': '2026-01-01T00:00:00Z',
  'cells': [
    {
      'value': value,
      'geometry': {
        'type': 'Polygon',
        'coordinates': [
          [
            [1.999, .999],
            [2.001, .999],
            [2.001, 1.001],
            [1.999, 1.001],
            [1.999, .999],
          ],
        ],
      },
    },
  ],
};

void main() {
  test(
    'pH contract retains source and raw values without crop classification',
    () {
      final raw = layer();
      expect(validatedSoilLayer(raw, GeoPoint(1, 2)), same(raw));
      expect(raw.containsKey('suitability'), false);
    },
  );
  test('a different field cannot inherit cached soil polygons', () {
    expect(validatedSoilLayer(layer(), GeoPoint(2, 3)), isNull);
  });
  test('missing pixels remain unknown', () {
    expect(
      validatedSoilLayer(
        layer(value: null),
        GeoPoint(1, 2),
      )?['cells'][0]['value'],
      isNull,
    );
    expect(validatedSoilLayer(layer(value: null), GeoPoint(1, 2)), isNotNull);
  });
  test(
    'rejects wrong units, missing provenance, nonfinite and unsupported values',
    () {
      for (final raw in [
        {...layer(), 'unit': 'score'},
        {...layer(), 'source_sha256': null},
        {...layer(), 'source_url': 'https://example.org/soil'},
        layer(value: double.nan),
        layer(value: -1),
        layer(value: 15),
      ]) {
        expect(validatedSoilLayer(raw, GeoPoint(1, 2)), isNull);
      }
    },
  );
}
