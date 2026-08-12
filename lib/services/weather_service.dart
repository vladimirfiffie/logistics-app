import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:http/http.dart' as http;

/// Driving conditions at a point in time.
@immutable
class Weather {
  const Weather({
    required this.temperatureC,
    required this.feelsLikeC,
    required this.windKph,
    required this.precipitationMm,
    required this.code,
    required this.isDay,
  });

  final double temperatureC;
  final double feelsLikeC;
  final double windKph;
  final double precipitationMm;

  /// WMO weather interpretation code.
  final int code;

  final bool isDay;

  /// Plain description from the WMO code table, trimmed to the ones that
  /// actually occur and phrased for someone driving rather than a forecaster.
  String get description => switch (code) {
    0 => 'Clear',
    1 => 'Mostly clear',
    2 => 'Partly cloudy',
    3 => 'Overcast',
    45 || 48 => 'Fog',
    51 || 53 || 55 => 'Drizzle',
    56 || 57 => 'Freezing drizzle',
    61 => 'Light rain',
    63 => 'Rain',
    65 => 'Heavy rain',
    66 || 67 => 'Freezing rain',
    71 => 'Light snow',
    73 => 'Snow',
    75 => 'Heavy snow',
    77 => 'Snow grains',
    80 || 81 => 'Rain showers',
    82 => 'Violent showers',
    85 || 86 => 'Snow showers',
    95 => 'Thunderstorm',
    96 || 99 => 'Thunderstorm with hail',
    _ => 'Unknown',
  };

  IconData get icon => switch (code) {
    0 || 1 => isDay ? Icons.wb_sunny_outlined : Icons.nightlight_outlined,
    2 => Icons.wb_cloudy_outlined,
    3 => Icons.cloud_outlined,
    45 || 48 => Icons.foggy,
    >= 51 && <= 57 => Icons.grain,
    >= 61 && <= 67 => Icons.water_drop_outlined,
    >= 71 && <= 77 => Icons.ac_unit,
    >= 80 && <= 82 => Icons.umbrella_outlined,
    85 || 86 => Icons.ac_unit,
    >= 95 => Icons.thunderstorm_outlined,
    _ => Icons.help_outline,
  };

  /// Conditions a driver should actually be warned about — ice, heavy rain,
  /// fog, storms, strong wind on a high-sided van.
  String? get drivingWarning {
    if (code == 56 || code == 57 || code == 66 || code == 67) {
      return 'Freezing rain — expect ice underfoot and on the road.';
    }
    if (code >= 71 && code <= 77 || code == 85 || code == 86) {
      return 'Snow — allow extra time between stops.';
    }
    if (code == 45 || code == 48) return 'Fog — visibility is poor.';
    if (code >= 95) return 'Thunderstorms in the area.';
    if (code == 65 || code == 82) return 'Heavy rain — standing water likely.';
    if (windKph >= 60) return 'Strong wind — take care with a high-sided van.';
    return null;
  }
}

/// Current conditions from Open-Meteo.
///
/// Chosen because it needs no API key and no account, which keeps the app
/// runnable straight from a clone. The trade-off is a network call carrying
/// the driver's approximate position — the one thing in this app that leaves
/// the device, which is why it is a setting the driver can switch off.
class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 8);

  /// Returns null on any failure. Weather is a nicety on a delivery screen —
  /// a flat network must never turn into an error the driver has to dismiss.
  Future<Weather?> current({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toStringAsFixed(3),
      'longitude': longitude.toStringAsFixed(3),
      'current':
          'temperature_2m,apparent_temperature,precipitation,'
          'weather_code,wind_speed_10m,is_day',
      'wind_speed_unit': 'kmh',
      'timezone': 'auto',
    });

    try {
      final response = await _client.get(uri).timeout(_timeout);
      if (response.statusCode != 200) {
        debugPrint('weather: HTTP ${response.statusCode}');
        return null;
      }
      return parse(response.body);
    } catch (error) {
      debugPrint('weather unavailable: $error');
      return null;
    }
  }

  /// Exposed for tests: the JSON shape is the part worth pinning down.
  @visibleForTesting
  static Weather? parse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      final current = decoded['current'];
      if (current is! Map<String, dynamic>) return null;

      double number(String key) => (current[key] as num?)?.toDouble() ?? 0;

      return Weather(
        temperatureC: number('temperature_2m'),
        feelsLikeC: number('apparent_temperature'),
        windKph: number('wind_speed_10m'),
        precipitationMm: number('precipitation'),
        code: (current['weather_code'] as num?)?.toInt() ?? -1,
        isDay: ((current['is_day'] as num?)?.toInt() ?? 1) == 1,
      );
    } catch (error) {
      debugPrint('weather: could not parse response — $error');
      return null;
    }
  }

  void dispose() => _client.close();
}
