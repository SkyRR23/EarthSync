import 'package:flutter/widgets.dart';
import '../features/home/weather_tab.dart';

/// Optional adapter for restoring the original live-data screen later.
/// Not imported by the primary Android simulation flow. The host must provide
/// the normal Riverpod scope, saved farm preferences and navigation context.
Widget buildRealtimeWeatherPreview() => const WeatherTab();
