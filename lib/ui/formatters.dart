import 'package:intl/intl.dart';

import '../models/app_settings.dart';

/// Display helpers shared across screens. Kept in one place so a distance
/// reads the same on the map, the job card, and the history entry.
final _timeFormat = DateFormat.Hm();
final _dateFormat = DateFormat('EEE d MMM');
final _dateTimeFormat = DateFormat('EEE d MMM, HH:mm');

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

String formatTime(DateTime time) => _timeFormat.format(time);

String formatDate(DateTime time) => _dateFormat.format(time);

String formatDateTime(DateTime time) => _dateTimeFormat.format(time);

/// Signed decimal degrees, the format that pastes cleanly into any map app.
String formatCoordinates(double latitude, double longitude) =>
    '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
