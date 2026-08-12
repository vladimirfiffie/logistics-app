/// A break taken during a shift.
///
/// Recorded separately from the shift rather than subtracted from it, because
/// the two answer different questions: a shift is how long the driver was at
/// work, and breaks are why the paid total is lower. A driver querying a
/// timesheet needs both numbers, not one derived figure.
class ShiftBreak {
  const ShiftBreak({
    required this.id,
    required this.shiftId,
    required this.startedAt,
    this.endedAt,
    this.kind = BreakKind.rest,
  });

  final String id;
  final String shiftId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final BreakKind kind;

  bool get isActive => endedAt == null;

  Duration get duration => (endedAt ?? DateTime.now()).difference(startedAt);

  ShiftBreak copyWith({DateTime? endedAt}) => ShiftBreak(
    id: id,
    shiftId: shiftId,
    startedAt: startedAt,
    endedAt: endedAt ?? this.endedAt,
    kind: kind,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'shift_id': shiftId,
    'started_at': startedAt.toUtc().millisecondsSinceEpoch,
    'ended_at': endedAt?.toUtc().millisecondsSinceEpoch,
    'kind': kind.name,
  };

  factory ShiftBreak.fromMap(Map<String, Object?> map) => ShiftBreak(
    id: map['id']! as String,
    shiftId: map['shift_id']! as String,
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
    kind: BreakKind.fromName(map['kind'] as String?),
  );
}

/// Why the driver stopped. Kept coarse — this is a timesheet, not a diary.
enum BreakKind {
  rest('Break', 'Rest break'),
  meal('Lunch', 'Meal break'),
  other('Other', 'Other');

  const BreakKind(this.label, this.detail);

  final String label;
  final String detail;

  static BreakKind fromName(String? value) => BreakKind.values.firstWhere(
    (kind) => kind.name == value,
    orElse: () => BreakKind.rest,
  );
}
