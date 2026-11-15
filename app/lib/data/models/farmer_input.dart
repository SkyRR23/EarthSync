/// Mirrors contract v1 `FarmerInput` (master plan §07).
/// Every answer may be unknown; Rust decides what unknown means.
library;

enum Irrigation { none, partial, full, unknown }

enum Drainage { poor, moderate, good, unknown }

enum Priority { income, lessWater, soilHealth, lowerRisk, foodForFamily }

/// Crop IDs offered in the questionnaire. Must match P2's crop_id values.
abstract final class Crops {
  static const options = <String, String>{
    'rice': 'Rice',
    'mung_bean': 'Mung bean',
    'black_gram': 'Black gram',
    'chickpea': 'Chickpea',
    'groundnut': 'Groundnut',
    'sesame': 'Sesame',
    'maize': 'Maize',
    'vegetables': 'Vegetables',
    'fruits': 'Fruits',
    'fallow': 'Nothing (rest)',
  };

  static String label(String? id) =>
      id == null || id.trim().isEmpty ? 'Unknown crop' : options[id] ?? id;
}

class FarmerInput {
  const FarmerInput({
    required this.latitude,
    required this.longitude,
    this.currentCrop,
    this.recentRotation = const [],
    this.plantingMonth,
    this.irrigation = Irrigation.unknown,
    this.drainage = Drainage.unknown,
    this.priorities = const [],
    this.boundary = const [],
    this.soilTexture,
    this.soilClass,
  });

  /// Field location used for every calculation: the farm centre once the
  /// farm is marked, otherwise the setup pin.
  final double latitude;
  final double longitude;

  /// Farm corners as [lat, lon] pairs (empty = only a pin). Kept for P2's
  /// server request; the on-device engine uses [latitude]/[longitude].
  final List<List<double>> boundary;

  /// Soil for today's engine: one of its 6 names (`clay_loam`…); null = not known.
  final String? soilTexture;

  /// The full 12-type soil name (`silty_clay_loam`…), for the backend/v0.3.
  final String? soilClass;

  /// null = farmer does not know / did not say.
  final String? currentCrop;
  final List<String> recentRotation;

  /// 1–12, null = unknown.
  final int? plantingMonth;
  final Irrigation irrigation;
  final Drainage drainage;
  final List<Priority> priorities;

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'current_crop': currentCrop,
    'recent_rotation': recentRotation,
    'planting_month': plantingMonth,
    'irrigation': irrigation.name,
    'drainage': drainage.name,
    'priorities': priorities.map(_priorityToJson).toList(),
    'field_boundary': boundary,
    'soil_texture': soilTexture,
    'soil_class': soilClass,
  };

  static String _priorityToJson(Priority p) => switch (p) {
    Priority.income => 'income',
    Priority.lessWater => 'less_water',
    Priority.soilHealth => 'soil_health',
    Priority.lowerRisk => 'lower_risk',
    Priority.foodForFamily => 'food_for_family',
  };
}
