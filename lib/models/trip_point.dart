import 'package:latlong2/latlong.dart';

import 'fix.dart';

/// One GPS breadcrumb recorded during a [Trip].
class TripPoint {
  const TripPoint({
    required this.tripId,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.speed,
    required this.heading,
    required this.altitude,
    required this.recordedAt,
    this.id,
  });

  /// Assigned by SQLite on insert; null for points not yet persisted.
  final int? id;
  final String tripId;
  final double latitude;
  final double longitude;

  /// Radius of 68% confidence, in metres.
  final double accuracy;

  /// Metres per second.
  final double speed;

  /// Degrees clockwise from true north.
  final double heading;
  final double altitude;
  final DateTime recordedAt;

  LatLng get latLng => LatLng(latitude, longitude);

  factory TripPoint.fromFix(String tripId, Fix position) => TripPoint(
    tripId: tripId,
    latitude: position.latitude,
    longitude: position.longitude,
    accuracy: position.accuracy,
    speed: position.speed,
    heading: position.heading,
    altitude: position.altitude,
    recordedAt: position.timestamp,
  );

  /// The breadcrumb read back as a reading. Used to put a resumed trip on the
  /// map straight away, rather than leaving it blank until the stream
  /// produces its first fix.
  Fix toFix() => Fix(
    latitude: latitude,
    longitude: longitude,
    accuracy: accuracy,
    speed: speed,
    heading: heading,
    altitude: altitude,
    timestamp: recordedAt,
  );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'trip_id': tripId,
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'speed': speed,
    'heading': heading,
    'altitude': altitude,
    'recorded_at': recordedAt.toUtc().millisecondsSinceEpoch,
  };

  factory TripPoint.fromMap(Map<String, Object?> map) => TripPoint(
    id: map['id'] as int?,
    tripId: map['trip_id']! as String,
    latitude: (map['latitude']! as num).toDouble(),
    longitude: (map['longitude']! as num).toDouble(),
    accuracy: (map['accuracy']! as num).toDouble(),
    speed: (map['speed']! as num).toDouble(),
    heading: (map['heading']! as num).toDouble(),
    altitude: (map['altitude']! as num).toDouble(),
    recordedAt: DateTime.fromMillisecondsSinceEpoch(
      map['recorded_at']! as int,
      isUtc: true,
    ).toLocal(),
  );
}
