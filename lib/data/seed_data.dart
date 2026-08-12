import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../models/delivery.dart';
import 'delivery_repository.dart';

/// Seeds a starter manifest the first time the app runs.
///
/// With no dispatch backend there is nothing to pull a day's work from, so we
/// fabricate one. Stops are scattered around [origin] — the driver's real
/// position when location is available — which keeps the map and the distance
/// readouts meaningful instead of stranding the driver an ocean away from
/// their jobs.
class SeedData {
  const SeedData._();

  /// Used when location permission is refused before the first seed.
  static const fallbackOrigin = LatLng(51.5074, -0.1278);

  static const _stops =
      <
        ({
          String customer,
          String address,
          String? notes,
          int parcels,
          double northKm,
          double eastKm,
          int hourOffset,
        })
      >[
        (
          customer: 'Harlow & Sons Hardware',
          address: '14 Bridgewater Road, Unit 3',
          notes: 'Loading bay round the back. Ring bell twice.',
          parcels: 4,
          northKm: 1.8,
          eastKm: -0.9,
          hourOffset: 1,
        ),
        (
          customer: 'Meridian Dental Practice',
          address: '221 Oakfield Avenue',
          notes: 'Reception closes 13:00–14:00 for lunch.',
          parcels: 1,
          northKm: -2.4,
          eastKm: 1.6,
          hourOffset: 2,
        ),
        (
          customer: 'Castellan Coffee Roasters',
          address: 'Arch 7, Vindale Yard',
          notes: 'Heavy — 25kg sacks. Trolley recommended.',
          parcels: 6,
          northKm: 0.7,
          eastKm: 3.1,
          hourOffset: 3,
        ),
        (
          customer: 'Nadia Okonkwo',
          address: 'Flat 12B, Perrin House, Selby Street',
          notes: 'Buzzer broken — call on arrival.',
          parcels: 1,
          northKm: -1.1,
          eastKm: -2.8,
          hourOffset: 4,
        ),
        (
          customer: 'Redmond Autoparts',
          address: '3 Kilnbrook Industrial Estate',
          notes: null,
          parcels: 9,
          northKm: 4.2,
          eastKm: 2.2,
          hourOffset: 5,
        ),
        (
          customer: 'St Aldate Primary School',
          address: 'School Lane, main office',
          notes: 'Deliveries accepted 09:00–15:00 only.',
          parcels: 2,
          northKm: -3.6,
          eastKm: -1.4,
          hourOffset: 6,
        ),
      ];

  /// Inserts the starter manifest if the repository is empty. Safe to call on
  /// every launch.
  static Future<void> ensureSeeded(
    DeliveryRepository repository, {
    LatLng? origin,
    DateTime? now,
    Uuid uuid = const Uuid(),
  }) async {
    final existing = await repository.fetchDeliveries();
    if (existing.isNotEmpty) return;

    final start = origin ?? fallbackOrigin;
    final today = now ?? DateTime.now();
    final dayStart = DateTime(today.year, today.month, today.day, 8);

    for (var i = 0; i < _stops.length; i++) {
      final stop = _stops[i];
      final point = _offset(start, northKm: stop.northKm, eastKm: stop.eastKm);
      await repository.saveDelivery(
        Delivery(
          id: uuid.v4(),
          reference: 'LG-${1040 + i}',
          customerName: stop.customer,
          address: stop.address,
          latitude: point.latitude,
          longitude: point.longitude,
          status: DeliveryStatus.pending,
          scheduledFor: dayStart.add(Duration(hours: stop.hourOffset)),
          notes: stop.notes,
          parcelCount: stop.parcels,
        ),
      );
    }
  }

  /// Shifts [from] by a ground distance in kilometres. Accurate enough over the
  /// few-kilometre range used here.
  static LatLng _offset(
    LatLng from, {
    required double northKm,
    required double eastKm,
  }) {
    const kmPerDegreeLat = 110.574;
    final kmPerDegreeLng = 111.320 * math.cos(from.latitude * math.pi / 180);
    return LatLng(
      from.latitude + northKm / kmPerDegreeLat,
      from.longitude +
          eastKm / (kmPerDegreeLng.abs() < 1e-6 ? 1e-6 : kmPerDegreeLng),
    );
  }
}
