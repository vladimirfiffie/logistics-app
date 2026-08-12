/// A working shift: clock on, drive the round, clock off.
///
/// Separate from [Trip], which is one leg to one stop. A shift spans the whole
/// day and is what a driver actually gets paid for, so it survives the app
/// being closed and is never ended implicitly.
class Shift {
  const Shift({
    required this.id,
    required this.startedAt,
    this.endedAt,
    this.vehicleLabel,
    this.startedByTag = false,
  });

  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// The van this shift was started in, when a tag said so.
  final String? vehicleLabel;

  /// Whether it was started by tapping a tag rather than tapping the screen.
  /// Worth recording: a tag tap is evidence the driver was physically at the
  /// vehicle, which a button press is not.
  final bool startedByTag;

  bool get isActive => endedAt == null;

  Duration get duration => (endedAt ?? DateTime.now()).difference(startedAt);

  Shift copyWith({DateTime? endedAt}) => Shift(
    id: id,
    startedAt: startedAt,
    endedAt: endedAt ?? this.endedAt,
    vehicleLabel: vehicleLabel,
    startedByTag: startedByTag,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'started_at': startedAt.toUtc().millisecondsSinceEpoch,
    'ended_at': endedAt?.toUtc().millisecondsSinceEpoch,
    'vehicle_label': vehicleLabel,
    'started_by_tag': startedByTag ? 1 : 0,
  };

  factory Shift.fromMap(Map<String, Object?> map) => Shift(
    id: map['id']! as String,
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
    vehicleLabel: map['vehicle_label'] as String?,
    startedByTag: ((map['started_by_tag'] as int?) ?? 0) == 1,
  );
}
