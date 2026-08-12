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
    this.failureReason,
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
  final String? failureReason;

  Delivery copyWith({
    DeliveryStatus? status,
    DateTime? completedAt,
    String? recipientName,
    String? proofPhotoPath,
    String? failureReason,
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
      failureReason: failureReason ?? this.failureReason,
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
    'failure_reason': failureReason,
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
    failureReason: map['failure_reason'] as String?,
  );
}
