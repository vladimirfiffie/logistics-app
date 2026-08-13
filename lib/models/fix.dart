import 'package:flutter/foundation.dart';

/// One reading from the phone's location hardware.
///
/// The app's own type rather than the plugin's. Everything above
/// `LocationService` — the odometer, the live view, the manifest's distance
/// column — used to be written against `geolocator`'s `Position`, which meant
/// the choice of location plugin reached into five files and the widget tree.
/// It is one interface now, so swapping the plugin underneath (for one that
/// works without Play Services, say) is a change to a single file rather than
/// a migration.
@immutable
class Fix {
  const Fix({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.speed,
    required this.heading,
    required this.altitude,
    required this.timestamp,
  });

  final double latitude;
  final double longitude;

  /// Radius of the horizontal uncertainty, in metres.
  final double accuracy;

  /// Metres per second over the ground.
  final double speed;

  /// Degrees clockwise from true north. Derived from movement, so it means
  /// nothing when [speed] is near zero — and some devices report -1 rather
  /// than admitting they do not know.
  final double heading;

  /// Metres above sea level.
  final double altitude;

  /// When the device took the reading, not when the app received it.
  final DateTime timestamp;

  @override
  bool operator ==(Object other) =>
      other is Fix &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.accuracy == accuracy &&
      other.speed == speed &&
      other.heading == heading &&
      other.altitude == altitude &&
      other.timestamp == timestamp;

  @override
  int get hashCode => Object.hash(
    latitude,
    longitude,
    accuracy,
    speed,
    heading,
    altitude,
    timestamp,
  );

  @override
  String toString() =>
      'Fix($latitude, $longitude ±${accuracy.toStringAsFixed(0)}m)';
}
