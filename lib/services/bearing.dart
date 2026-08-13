import 'dart:math' as math;

/// Which way things are, relative to north and relative to the driver.
///
/// Not navigation: there is no road network here, and nothing in this file
/// knows that a river or a one-way street exists. It answers the question a
/// driver actually asks when they are stopped at a junction with the map in
/// front of them — "which way is it from here?" — and leaves turn-by-turn to
/// the nav app the stop sheet hands off to.

/// Mean Earth radius, in metres. The value the haversine formula is normally
/// quoted with, and the one geolocator used before this app measured its own
/// distances — so an odometer reading does not change under the driver when
/// the location plugin does.
const earthRadiusMeters = 6371008.8;

/// Great-circle distance between two points, in metres.
///
/// Haversine on a sphere. The error against a proper ellipsoid is about 0.3%
/// — three metres in a kilometre — which is far inside the GPS's own accuracy
/// and nowhere near enough to matter to a mileage claim.
double distanceBetweenMeters(
  double fromLatitude,
  double fromLongitude,
  double toLatitude,
  double toLongitude,
) {
  final fromLat = _radians(fromLatitude);
  final toLat = _radians(toLatitude);
  final deltaLat = _radians(toLatitude - fromLatitude);
  final deltaLng = _radians(toLongitude - fromLongitude);

  final a =
      math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
      math.cos(fromLat) *
          math.cos(toLat) *
          math.sin(deltaLng / 2) *
          math.sin(deltaLng / 2);

  return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Initial great-circle bearing from one point to another, in degrees
/// clockwise from true north.
///
/// "Initial" because the bearing of a long path changes as you fly it; over a
/// delivery round it is a straight line for all practical purposes.
double bearingDegrees(
  double fromLatitude,
  double fromLongitude,
  double toLatitude,
  double toLongitude,
) {
  final fromLat = _radians(fromLatitude);
  final toLat = _radians(toLatitude);
  final deltaLng = _radians(toLongitude - fromLongitude);

  final y = math.sin(deltaLng) * math.cos(toLat);
  final x =
      math.cos(fromLat) * math.sin(toLat) -
      math.sin(fromLat) * math.cos(toLat) * math.cos(deltaLng);

  final degrees = _degrees(math.atan2(y, x));
  return (degrees + 360) % 360;
}

/// The eight-point compass name for a bearing: N, NE, E and so on.
///
/// Eight points rather than sixteen because "north-north-east" is not how
/// anyone describes where a house is.
String compassPoint(double bearing) {
  const points = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  final normalised = (bearing % 360 + 360) % 360;
  // Each point covers 45°, centred on its own bearing, so the boundaries sit
  // at 22.5° either side.
  final index = ((normalised + 22.5) ~/ 45) % 8;
  return points[index];
}

/// [bearing] expressed relative to the way the driver is facing: 0 is dead
/// ahead, positive is to the right, negative to the left, ±180 is behind.
double relativeBearing(double bearing, double heading) {
  final difference = (bearing - heading + 540) % 360 - 180;
  return difference;
}

/// How a driver would say a relative bearing out loud.
///
/// Deliberately coarse. A straight-line bearing is not a road, so "half
/// right" is honest where "bear right in 200 metres" would be a claim about
/// a junction this app cannot see.
String describeRelative(double relative) {
  final magnitude = relative.abs();
  final side = relative < 0 ? 'left' : 'right';

  if (magnitude <= 20) return 'straight ahead';
  if (magnitude <= 65) return 'ahead and to your $side';
  if (magnitude <= 115) return 'to your $side';
  if (magnitude <= 155) return 'behind you, to the $side';
  return 'behind you';
}

double _radians(double degrees) => degrees * math.pi / 180;

double _degrees(double radians) => radians * 180 / math.pi;
