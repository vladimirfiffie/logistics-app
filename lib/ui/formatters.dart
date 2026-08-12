import 'package:intl/intl.dart';

import '../models/app_settings.dart';

/// Display helpers shared across screens. Kept in one place so a distance
/// reads the same on the map, the job card, and the history entry.

/// The driver's date and time choices, mirrored out of `SettingsController`.
///
/// Same trick as `AppHaptics.enabled`: dates are formatted from plain
/// functions called deep inside build methods and from code with no provider
/// in reach, and threading two enums through every one of those call sites
/// would cost more than it buys.
class DateFormatting {
  const DateFormatting._();

  static DateStyle date = DateStyle.dayMonth;
  static ClockStyle clock = ClockStyle.twentyFour;

  /// `DateFormat` parses its pattern on construction, so the handful in play
  /// are built once rather than on every list row.
  static final _cache = <String, DateFormat>{};

  static DateFormat _of(String pattern) =>
      _cache.putIfAbsent(pattern, () => DateFormat(pattern));
}

const _metresPerMile = 1609.344;
const _feetPerMetre = 3.28084;

/// Metres in, the driver's chosen unit out.
///
/// Short distances stay in metres/feet rather than showing "0.06 km", which
/// is unreadable at the point it matters most — walking up to the door.
String formatDistance(
  double meters, {
  DistanceUnit unit = DistanceUnit.metric,
}) {
  if (meters.isNaN || meters.isInfinite) return '—';

  if (unit == DistanceUnit.imperial) {
    final miles = meters / _metresPerMile;
    if (miles < 0.1) return '${(meters * _feetPerMetre).round()} ft';
    return '${miles.toStringAsFixed(miles < 10 ? 2 : 1)} mi';
  }

  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(meters < 10000 ? 2 : 1)} km';
}

String formatDuration(Duration duration) {
  final total = duration.inSeconds.abs();
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  if (hours > 0) return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  if (minutes > 0) return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  return '${seconds}s';
}

/// Metres per second in, km/h or mph out — what a driver actually reads.
String formatSpeed(
  double metersPerSecond, {
  DistanceUnit unit = DistanceUnit.metric,
}) {
  if (metersPerSecond.isNaN || metersPerSecond < 0) return '—';
  if (unit == DistanceUnit.imperial) {
    final mph = metersPerSecond * 3600 / _metresPerMile;
    return '${mph.toStringAsFixed(1)} mph';
  }
  return '${(metersPerSecond * 3.6).toStringAsFixed(1)} km/h';
}

String formatAccuracy(
  double meters, {
  DistanceUnit unit = DistanceUnit.metric,
}) {
  if (unit == DistanceUnit.imperial) {
    return '±${(meters * _feetPerMetre).round()} ft';
  }
  return '±${meters.round()} m';
}

/// Celsius in, whatever the driver reads out.
String formatTemperature(double celsius, {bool fahrenheit = false}) {
  if (celsius.isNaN || celsius.isInfinite) return '—';
  if (fahrenheit) return '${(celsius * 9 / 5 + 32).round()}°F';
  return '${celsius.round()}°C';
}

/// Wind arrives from the forecast in km/h and follows the distance unit —
/// nobody reads their distances in miles and their wind in kilometres.
String formatWindSpeed(double kph, {DistanceUnit unit = DistanceUnit.metric}) {
  if (kph.isNaN || kph.isInfinite) return '—';
  if (unit == DistanceUnit.imperial) {
    return '${(kph * 1000 / _metresPerMile).round()} mph';
  }
  return '${kph.round()} km/h';
}

String formatTime(DateTime time) =>
    DateFormatting._of(DateFormatting.clock.pattern).format(time);

String formatDate(DateTime time) =>
    DateFormatting._of(DateFormatting.date.pattern).format(time);

String formatDateTime(DateTime time) =>
    '${formatDate(time)}, '
    '${formatTime(time)}';

/// Signed decimal degrees, the format that pastes cleanly into any map app.
String formatCoordinates(double latitude, double longitude) =>
    '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
