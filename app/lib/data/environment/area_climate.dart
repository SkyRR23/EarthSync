import '../models/home_profile.dart';
import 'nasa_power_client.dart';

class ClimateQuery {
  const ClimateQuery(this.point, this.window);
  final GeoPoint point;
  final HistoricalWindow window;
  @override
  bool operator ==(Object other) =>
      other is ClimateQuery &&
      point == other.point &&
      window.startYear == other.window.startYear &&
      window.startMonth == other.window.startMonth &&
      window.endYear == other.window.endYear &&
      window.endMonth == other.window.endMonth;
  @override
  int get hashCode => Object.hash(
    point,
    window.startYear,
    window.startMonth,
    window.endYear,
    window.endMonth,
  );
}

class ClimateReading {
  const ClimateReading(this.month, this.rainMm, this.temperatureC);
  final DateTime month;
  final double? rainMm, temperatureC;
}

/// Presentation of backend monthly values only. No crop analysis, gap filling,
/// spatial averaging, or alternative climate source.
class AreaClimate {
  AreaClimate(this.evidence, HistoricalWindow window) {
    final observations =
        evidence.environment['seasonal']['observations'] as List;
    for (
      var month = DateTime.utc(window.startYear, window.startMonth);
      !month.isAfter(DateTime.utc(window.endYear, window.endMonth));
      month = DateTime.utc(month.year, month.month + 1)
    ) {
      final matching = observations
          .where(
            (o) =>
                o['period']['year'] == month.year &&
                o['period']['month'] == month.month,
          )
          .toList();
      final row = matching.length == 1 ? matching.single : null;
      double? value(String key, String complete, {bool nonnegative = false}) {
        if (row == null || row[complete] != true) return null;
        final v = row[key];
        return v is num && v.isFinite && (!nonnegative || v >= 0)
            ? v.toDouble()
            : null;
      }

      readings.add(
        ClimateReading(
          month,
          value('rainfall_mm', 'rainfall_complete', nonnegative: true),
          value('mean_temperature_c', 'temperature_complete'),
        ),
      );
    }
  }
  final NasaPowerEvidence evidence;
  final List<ClimateReading> readings = [];
}
