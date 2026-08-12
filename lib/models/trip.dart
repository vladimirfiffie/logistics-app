/// A tracking session: the drive from wherever the driver was when they hit
/// "start" to the moment the stop is closed out.
class Trip {
  const Trip({
    required this.id,
    required this.deliveryId,
    required this.startedAt,
    this.endedAt,
    this.distanceMeters = 0,
  });

  final String id;
  final String deliveryId;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// Ground distance accumulated from the recorded breadcrumbs, not the
  /// straight line from origin to destination.
  final double distanceMeters;

  bool get isActive => endedAt == null;

  Duration get duration => (endedAt ?? DateTime.now()).difference(startedAt);

  Trip copyWith({DateTime? endedAt, double? distanceMeters}) => Trip(
    id: id,
    deliveryId: deliveryId,
    startedAt: startedAt,
    endedAt: endedAt ?? this.endedAt,
    distanceMeters: distanceMeters ?? this.distanceMeters,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'delivery_id': deliveryId,
    'started_at': startedAt.toUtc().millisecondsSinceEpoch,
    'ended_at': endedAt?.toUtc().millisecondsSinceEpoch,
    'distance_meters': distanceMeters,
  };

  factory Trip.fromMap(Map<String, Object?> map) => Trip(
    id: map['id']! as String,
    deliveryId: map['delivery_id']! as String,
    startedAt: DateTime.fromMillisecondsSinceEpoch(
      map['started_at']! as int,
      isUtc: true,
    ).toLocal(),
    endedAt: switch (map['ended_at'] as int?) {
      final int ms => DateTime.fromMillisecondsSinceEpoch(
        ms,
        isUtc: true,
      ).toLocal(),
      null => null,
    },
    distanceMeters: (map['distance_meters'] as num?)?.toDouble() ?? 0,
  );
}
