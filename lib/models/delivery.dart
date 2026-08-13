/// A single delivery stop assigned to the driver.
enum DeliveryStatus {
  pending,
  inTransit,
  delivered,
  failed;

  static DeliveryStatus fromName(String value) =>
      DeliveryStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () => DeliveryStatus.pending,
      );

  String get label => switch (this) {
    DeliveryStatus.pending => 'Pending',
    DeliveryStatus.inTransit => 'In transit',
    DeliveryStatus.delivered => 'Delivered',
    DeliveryStatus.failed => 'Failed',
  };

  bool get isOpen => this == DeliveryStatus.pending || this == inTransit;
}

/// What happens to a stop that could not be delivered.
///
/// A failure used to be the end of the record: a reason was written and the
/// parcel was, as far as the app was concerned, gone. In the job it always
/// goes somewhere — back to the door tomorrow, later the same day once the
/// customer is home, or back to the depot — and that decision is made at the
/// door, by the person holding the parcel.
enum FailureAction {
  cardedRetryTomorrow(
    'Carded — retry tomorrow',
    'Leaves a card and puts the stop back on tomorrow morning.',
  ),
  retryToday('Try again later today', 'Puts it back on the run in two hours.'),
  returnToDepot(
    'Return to depot',
    'No further attempt. It goes back on the van.',
  );

  const FailureAction(this.label, this.detail);

  final String label;
  final String detail;

  /// Whether a follow-up stop should be raised.
  bool get retries => this != FailureAction.returnToDepot;

  /// When the follow-up is due, measured from the failure.
  DateTime nextAttemptAfter(DateTime failedAt) => switch (this) {
    FailureAction.retryToday => failedAt.add(const Duration(hours: 2)),
    // Tomorrow at nine, not "in 24 hours": a stop failed at half four in the
    // afternoon should not come back at half four the next.
    FailureAction.cardedRetryTomorrow => DateTime(
      failedAt.year,
      failedAt.month,
      failedAt.day + 1,
      9,
    ),
    FailureAction.returnToDepot => failedAt,
  };

  static FailureAction? fromName(String? value) {
    if (value == null) return null;
    for (final action in FailureAction.values) {
      if (action.name == value) return action;
    }
    return null;
  }
}

class Delivery {
  const Delivery({
    required this.id,
    required this.reference,
    required this.customerName,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.scheduledFor,
    this.notes,
    this.parcelCount = 1,
    this.completedAt,
    this.recipientName,
    this.proofPhotoPath,
    this.signaturePath,
    this.failureReason,
    this.barcode,
    this.customerPhone,
    this.parcelsScanned = 0,
    this.failureAction,
    this.attempt = 1,
    this.previousAttemptId,
  });

  final String id;

  /// Human-facing job number, e.g. `LG-1042`.
  final String reference;
  final String customerName;
  final String address;
  final double latitude;
  final double longitude;
  final DeliveryStatus status;
  final DateTime scheduledFor;
  final String? notes;
  final int parcelCount;

  /// Set when the stop reaches [DeliveryStatus.delivered] or
  /// [DeliveryStatus.failed].
  final DateTime? completedAt;
  final String? recipientName;
  final String? proofPhotoPath;

  /// PNG of the recipient's signature, written next to the proof photo.
  final String? signaturePath;

  final String? failureReason;

  /// What is printed on the parcel label. Scanning one finds its stop without
  /// the driver reading a reference off a screen with a parcel in each hand.
  final String? barcode;

  /// Dialled and texted from the stop. Optional — plenty of rounds have no
  /// number for the customer at all.
  final String? customerPhone;

  /// How many of [parcelCount] have been scanned off at the door. Never more
  /// than the count; zero means nothing was scanned, which is allowed.
  final int parcelsScanned;

  /// What the driver decided to do with a stop that failed.
  final FailureAction? failureAction;

  /// 1 for the original stop, 2 for the first retry, and so on. Shown next to
  /// the reference so a second attempt is obvious on the manifest.
  final int attempt;

  /// The stop this one was raised from, if it is a retry. Keeps the failed
  /// attempt in history rather than overwriting it.
  final String? previousAttemptId;

  bool get isRetry => attempt > 1;

  /// Every parcel accounted for. Only meaningful when scanning was used.
  bool get allParcelsScanned => parcelsScanned >= parcelCount;

  /// Files this stop owns on disk. Deleting the row has to delete these too,
  /// or they outlive every trace of the delivery they belong to.
  Iterable<String> get attachmentPaths => [
    if (proofPhotoPath case final String path) path,
    if (signaturePath case final String path) path,
  ];

  Delivery copyWith({
    DeliveryStatus? status,
    DateTime? completedAt,
    String? recipientName,
    String? proofPhotoPath,
    String? signaturePath,
    String? failureReason,
    String? barcode,
    String? customerPhone,
    int? parcelsScanned,
    FailureAction? failureAction,
  }) {
    return Delivery(
      id: id,
      reference: reference,
      customerName: customerName,
      address: address,
      latitude: latitude,
      longitude: longitude,
      status: status ?? this.status,
      scheduledFor: scheduledFor,
      notes: notes,
      parcelCount: parcelCount,
      completedAt: completedAt ?? this.completedAt,
      recipientName: recipientName ?? this.recipientName,
      proofPhotoPath: proofPhotoPath ?? this.proofPhotoPath,
      signaturePath: signaturePath ?? this.signaturePath,
      failureReason: failureReason ?? this.failureReason,
      barcode: barcode ?? this.barcode,
      customerPhone: customerPhone ?? this.customerPhone,
      parcelsScanned: parcelsScanned ?? this.parcelsScanned,
      failureAction: failureAction ?? this.failureAction,
      attempt: attempt,
      previousAttemptId: previousAttemptId,
    );
  }

  /// The follow-up stop for a failed attempt: same customer, same parcels, a
  /// new id and a new slot, with the outcome fields cleared. The failed row it
  /// came from is left exactly as it was — that attempt happened.
  Delivery nextAttempt({required String id, required DateTime scheduledFor}) {
    return Delivery(
      id: id,
      reference: reference,
      customerName: customerName,
      address: address,
      latitude: latitude,
      longitude: longitude,
      status: DeliveryStatus.pending,
      scheduledFor: scheduledFor,
      notes: notes,
      parcelCount: parcelCount,
      barcode: barcode,
      customerPhone: customerPhone,
      attempt: attempt + 1,
      previousAttemptId: this.id,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'reference': reference,
    'customer_name': customerName,
    'address': address,
    'latitude': latitude,
    'longitude': longitude,
    'status': status.name,
    'scheduled_for': scheduledFor.toUtc().millisecondsSinceEpoch,
    'notes': notes,
    'parcel_count': parcelCount,
    'completed_at': completedAt?.toUtc().millisecondsSinceEpoch,
    'recipient_name': recipientName,
    'proof_photo_path': proofPhotoPath,
    'signature_path': signaturePath,
    'failure_reason': failureReason,
    'barcode': barcode,
    'customer_phone': customerPhone,
    'parcels_scanned': parcelsScanned,
    'failure_action': failureAction?.name,
    'attempt': attempt,
    'previous_attempt_id': previousAttemptId,
  };

  factory Delivery.fromMap(Map<String, Object?> map) => Delivery(
    id: map['id']! as String,
    reference: map['reference']! as String,
    customerName: map['customer_name']! as String,
    address: map['address']! as String,
    latitude: (map['latitude']! as num).toDouble(),
    longitude: (map['longitude']! as num).toDouble(),
    status: DeliveryStatus.fromName(map['status']! as String),
    scheduledFor: DateTime.fromMillisecondsSinceEpoch(
      map['scheduled_for']! as int,
      isUtc: true,
    ).toLocal(),
    notes: map['notes'] as String?,
    parcelCount: (map['parcel_count'] as int?) ?? 1,
    completedAt: switch (map['completed_at'] as int?) {
      final int ms => DateTime.fromMillisecondsSinceEpoch(
        ms,
        isUtc: true,
      ).toLocal(),
      null => null,
    },
    recipientName: map['recipient_name'] as String?,
    proofPhotoPath: map['proof_photo_path'] as String?,
    signaturePath: map['signature_path'] as String?,
    failureReason: map['failure_reason'] as String?,
    barcode: map['barcode'] as String?,
    customerPhone: map['customer_phone'] as String?,
    parcelsScanned: (map['parcels_scanned'] as int?) ?? 0,
    failureAction: FailureAction.fromName(map['failure_action'] as String?),
    attempt: (map['attempt'] as int?) ?? 1,
    previousAttemptId: map['previous_attempt_id'] as String?,
  );
}
