import 'package:flutter_test/flutter_test.dart';
import 'package:logistics_app/models/delivery.dart';
import 'package:logistics_app/models/trip.dart';

void main() {
  group('DeliveryStatus', () {
    test('round-trips through its stored name', () {
      for (final status in DeliveryStatus.values) {
        expect(DeliveryStatus.fromName(status.name), status);
      }
    });

    test('falls back to pending for a value written by a newer build', () {
      expect(DeliveryStatus.fromName('teleported'), DeliveryStatus.pending);
    });

    test('only pending and in-transit count as open', () {
      expect(DeliveryStatus.pending.isOpen, isTrue);
      expect(DeliveryStatus.inTransit.isOpen, isTrue);
      expect(DeliveryStatus.delivered.isOpen, isFalse);
      expect(DeliveryStatus.failed.isOpen, isFalse);
    });
  });

  group('Delivery serialisation', () {
    final delivery = Delivery(
      id: 'abc',
      reference: 'LG-1040',
      customerName: 'Castellan Coffee',
      address: 'Arch 7, Vindale Yard',
      latitude: 51.5074,
      longitude: -0.1278,
      status: DeliveryStatus.delivered,
      scheduledFor: DateTime(2026, 8, 11, 11),
      notes: 'Heavy sacks',
      parcelCount: 6,
      completedAt: DateTime(2026, 8, 11, 11, 42),
      recipientName: 'Sam',
      proofPhotoPath: '/proofs/abc.jpg',
    );

    test('survives a trip through the map form', () {
      final restored = Delivery.fromMap(delivery.toMap());

      expect(restored.id, delivery.id);
      expect(restored.reference, delivery.reference);
      expect(restored.customerName, delivery.customerName);
      expect(restored.latitude, delivery.latitude);
      expect(restored.longitude, delivery.longitude);
      expect(restored.status, delivery.status);
      expect(restored.scheduledFor, delivery.scheduledFor);
      expect(restored.notes, delivery.notes);
      expect(restored.parcelCount, delivery.parcelCount);
      expect(restored.completedAt, delivery.completedAt);
      expect(restored.recipientName, delivery.recipientName);
      expect(restored.proofPhotoPath, delivery.proofPhotoPath);
    });

    test('stores times as UTC and hands them back local', () {
      final map = delivery.toMap();

      expect(
        map['scheduled_for'],
        DateTime(2026, 8, 11, 11).toUtc().millisecondsSinceEpoch,
      );
      expect(
        Delivery.fromMap(map).scheduledFor.isUtc,
        isFalse,
        reason: 'the UI formats local time',
      );
    });

    test('an untouched stop has no completion fields', () {
      final pending = Delivery(
        id: 'x',
        reference: 'LG-1',
        customerName: 'A',
        address: 'B',
        latitude: 0,
        longitude: 0,
        status: DeliveryStatus.pending,
        scheduledFor: DateTime(2026, 8, 11, 9),
      );

      final restored = Delivery.fromMap(pending.toMap());

      expect(restored.completedAt, isNull);
      expect(restored.recipientName, isNull);
      expect(restored.proofPhotoPath, isNull);
      expect(restored.failureReason, isNull);
      expect(restored.parcelCount, 1);
    });
  });

  group('Trip', () {
    test('is active until it is ended', () {
      final trip = Trip(
        id: 't',
        deliveryId: 'd',
        startedAt: DateTime(2026, 8, 11, 9),
      );

      expect(trip.isActive, isTrue);
      expect(
        trip.copyWith(endedAt: DateTime(2026, 8, 11, 9, 30)).isActive,
        isFalse,
      );
    });

    test('duration is measured against the end once there is one', () {
      final trip = Trip(
        id: 't',
        deliveryId: 'd',
        startedAt: DateTime(2026, 8, 11, 9),
        endedAt: DateTime(2026, 8, 11, 9, 25),
      );

      expect(trip.duration, const Duration(minutes: 25));
    });

    test('round-trips through its map form', () {
      final trip = Trip(
        id: 't',
        deliveryId: 'd',
        startedAt: DateTime(2026, 8, 11, 9),
        endedAt: DateTime(2026, 8, 11, 9, 25),
        distanceMeters: 4211.5,
      );

      final restored = Trip.fromMap(trip.toMap());

      expect(restored.id, trip.id);
      expect(restored.deliveryId, trip.deliveryId);
      expect(restored.startedAt, trip.startedAt);
      expect(restored.endedAt, trip.endedAt);
      expect(restored.distanceMeters, trip.distanceMeters);
    });
  });
}
