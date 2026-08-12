import 'package:intl/intl.dart';

/// Display helpers shared across screens. Kept in one place so a distance
/// reads the same on the map, the job card, and the history entry.
final _timeFormat = DateFormat.Hm();
final _dateFormat = DateFormat('EEE d MMM');
final _dateTimeFormat = DateFormat('EEE d MMM, HH:mm');

String formatDistance(double meters) {
  if (meters.isNaN || meters.isInfinite) return '—';
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

/// Metres per second in, km/h out — what a driver actually reads.
String formatSpeed(double metersPerSecond) {
  if (metersPerSecond.isNaN || metersPerSecond < 0) return '—';
  return '${(metersPerSecond * 3.6).toStringAsFixed(1)} km/h';
}

String formatAccuracy(double meters) => '±${meters.round()} m';

String formatTime(DateTime time) => _timeFormat.format(time);

String formatDate(DateTime time) => _dateFormat.format(time);

String formatDateTime(DateTime time) => _dateTimeFormat.format(time);

/// Signed decimal degrees, the format that pastes cleanly into any map app.
String formatCoordinates(double latitude, double longitude) =>
    '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
