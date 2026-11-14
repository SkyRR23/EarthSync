import 'models/home_profile.dart';
import 'platform_transport.dart';

String farmRevision(ConfirmedFarm farm) =>
    farm.confirmedAt.toUtc().toIso8601String();

class PlatformFarm {
  PlatformFarm.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      point = GeoPoint.fromJson(
        Map<String, dynamic>.from(json['confirmed_point'] as Map),
      ),
      productionSystem = json['production_system'] as String;
  final String id, productionSystem;
  final GeoPoint point;
}

class PlatformFarmClient {
  const PlatformFarmClient(this.transport);
  final PlatformTransport transport;
  Future<Map<String, dynamic>> references(
    String query,
  ) async => Map<String, dynamic>.from(
    await transport.request(
          'GET',
          '$prefix/crop-references?${Uri(queryParameters: {'q': query}).query}',
          expectedStatus: 200,
        )
        as Map,
  );

  Future<Map<String, dynamic>> water(
    String id,
    GeoPoint point,
    String start,
    String end,
  ) async => Map<String, dynamic>.from(
    await transport.request(
          'POST',
          '$prefix/water/jobs',
          expectedStatus: 202,
          body: {
            'farm_id': id,
            'query': {'point': point.toJson(), 'start': start, 'end': end},
          },
        )
        as Map,
  );

  Future<Map<String, dynamic>> job(String id) async =>
      Map<String, dynamic>.from(
        await transport.request('GET', '$prefix/jobs/$id', expectedStatus: 200)
            as Map,
      );
  static const prefix = '/api/platform/v1';
  Future<PlatformFarm?> link(ConfirmedFarm local) async {
    try {
      final json =
          await transport.request(
                'GET',
                '$prefix/farm-links/${Uri.encodeComponent(local.id)}?${Uri(queryParameters: {'revision': farmRevision(local)}).query}',
                expectedStatus: 200,
              )
              as Map;
      if (json['local_profile_id'] != local.id ||
          DateTime.parse(json['revision'] as String) != local.confirmedAt) {
        throw const FormatException('Farm identity mismatch');
      }
      final farm = PlatformFarm.fromJson(
        Map<String, dynamic>.from(json['farm'] as Map),
      );
      if (farm.point != local.point) {
        throw const FormatException('Farm point mismatch');
      }
      return farm;
    } on PlatformFailure catch (error) {
      if (error.code == 'NOT_FOUND') return null;
      rethrow;
    }
  }

  Future<void> confirm(ConfirmedFarm local, String system) async {
    await transport.request(
      'POST',
      '$prefix/farm-links',
      expectedStatus: 201,
      body: {
        'local_profile_id': local.id,
        'revision': farmRevision(local),
        'farm': {
          'name': local.name ?? 'My Farm',
          'confirmed_point': local.point.toJson(),
          'confirmed_on': farmRevision(local).substring(0, 10),
          'production_system': system,
        },
      },
    );
  }

  Future<Map<String, dynamic>> context(String id) async =>
      Map<String, dynamic>.from(
        await transport.request(
              'GET',
              '$prefix/farms/$id/context',
              expectedStatus: 200,
            )
            as Map,
      );
  Future<List<Map<String, dynamic>>> decisions(String id) async =>
      List<Map<String, dynamic>>.from(
        await transport.request(
              'GET',
              '$prefix/farms/$id/decisions',
              expectedStatus: 200,
            )
            as List,
      );
  Future<Map<String, dynamic>> assistant(String id) async =>
      Map<String, dynamic>.from(
        await transport.request(
              'GET',
              '$prefix/farms/$id/assistant-context',
              expectedStatus: 200,
            )
            as Map,
      );
  Future<Map<String, dynamic>> assess(Map<String, dynamic> body) async =>
      Map<String, dynamic>.from(
        await transport.request(
              'POST',
              '$prefix/assessments',
              expectedStatus: 200,
              body: body,
            )
            as Map,
      );
  Future<void> history(String id, Map<String, dynamic> body) async {
    await transport.request(
      'POST',
      '$prefix/farms/$id/history',
      expectedStatus: 201,
      body: body,
    );
  }
}
