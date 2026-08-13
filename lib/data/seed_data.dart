import 'dart:math' as math;
import 'dart:math' show Random;

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
      final reference = 'LG-${1040 + i}';
      await repository.saveDelivery(
        Delivery(
          id: uuid.v4(),
          reference: reference,
          customerName: stop.customer,
          address: stop.address,
          latitude: point.latitude,
          longitude: point.longitude,
          status: DeliveryStatus.pending,
          scheduledFor: dayStart.add(Duration(hours: stop.hourOffset)),
          notes: stop.notes,
          parcelCount: stop.parcels,
          barcode: _barcodeFor(reference, i),
          // Not every stop has a number, which is worth seeding too: the call
          // and text buttons have to cope with its absence.
          customerPhone: i.isEven ? _phoneFor(i) : null,
        ),
      );
    }
  }

  static const _customers = [
    'Harlow & Sons Hardware',
    'Meridian Dental Practice',
    'Castellan Coffee Roasters',
    'Redmond Autoparts',
    'St Aldate Primary School',
    'Beckworth Veterinary Clinic',
    'The Fold Bookshop',
    'Ravensmere Garden Centre',
    'Poulton Tyre & Exhaust',
    'Alderway Pharmacy',
    'Kestrel Print Works',
    'Marchetti Delicatessen',
    'Quillon Legal Services',
    'Ferrymead Community Hall',
    'Bramley Bakery',
    'Northgate Physiotherapy',
    'Ashcombe Electrical Supplies',
    'The Lantern Guest House',
  ];

  static const _residents = [
    'Nadia Okonkwo',
    'Tomasz Wiśniewski',
    'Priya Raghunathan',
    'Callum Sutherland',
    'Amara Nwosu',
    'Léa Bertrand',
    'Hyun-woo Park',
    'Sofia Marchetti',
  ];

  static const _streets = [
    'Bridgewater Road',
    'Oakfield Avenue',
    'Selby Street',
    'Kilnbrook Estate',
    'Vindale Yard',
    'Perrin House',
    'Marlow Crescent',
    'Tanners Lane',
    'Halstead Way',
    'Cobb Street',
    'Ferrymead Road',
    'Whitlock Rise',
  ];

  static const _notes = [
    'Loading bay round the back.',
    'Buzzer broken — call on arrival.',
    'Leave with the neighbour if out.',
    'Heavy — trolley recommended.',
    'Access via the side gate.',
    'Closed 13:00–14:00 for lunch.',
    'Deliveries before 15:00 only.',
    null,
    null,
  ];

  /// Appends [count] freshly generated stops to whatever is already there.
  ///
  /// Exists because there is no dispatch backend to pull a real day's work
  /// from — this is how you get more to test against. References continue
  /// from the highest existing one so they never collide, and the stops are
  /// scattered around [origin] like the initial seed.
  static Future<List<Delivery>> addStops(
    DeliveryRepository repository, {
    int count = 5,
    LatLng? origin,
    DateTime? now,
    Uuid uuid = const Uuid(),
    Random? random,
  }) async {
    final rng = random ?? Random();
    final existing = await repository.fetchDeliveries();
    final start = origin ?? fallbackOrigin;
    final today = now ?? DateTime.now();

    // Continue the numbering rather than restarting it.
    var nextNumber = 1040;
    for (final delivery in existing) {
      final digits = RegExp(r'(\d+)$').firstMatch(delivery.reference)?.group(1);
      final parsed = int.tryParse(digits ?? '');
      if (parsed != null && parsed >= nextNumber) nextNumber = parsed + 1;
    }

    // Queue new work after the latest slot already on the manifest, so added
    // stops sort to the end instead of interleaving with the day's history.
    var slot = DateTime(today.year, today.month, today.day, 9);
    for (final delivery in existing) {
      if (delivery.scheduledFor.isAfter(slot)) slot = delivery.scheduledFor;
    }

    final created = <Delivery>[];
    for (var i = 0; i < count; i++) {
      // A quarter residential, which is roughly a real round's mix and gives
      // the flat/buzzer notes somewhere to land.
      final residential = rng.nextInt(4) == 0;
      final customer = residential
          ? _residents[rng.nextInt(_residents.length)]
          : _customers[rng.nextInt(_customers.length)];
      final street = _streets[rng.nextInt(_streets.length)];
      final address = residential
          ? 'Flat ${rng.nextInt(40) + 1}, $street'
          : '${rng.nextInt(200) + 1} $street';

      final point = _offset(
        start,
        // Signed offsets out to ~5km, so stops land all around the driver
        // rather than in one quadrant.
        northKm: (rng.nextDouble() * 10) - 5,
        eastKm: (rng.nextDouble() * 10) - 5,
      );

      slot = slot.add(Duration(minutes: 20 + rng.nextInt(40)));

      final reference = 'LG-${nextNumber + i}';
      final delivery = Delivery(
        id: uuid.v4(),
        reference: reference,
        customerName: customer,
        address: address,
        latitude: point.latitude,
        longitude: point.longitude,
        status: DeliveryStatus.pending,
        scheduledFor: slot,
        notes: _notes[rng.nextInt(_notes.length)],
        parcelCount: residential ? 1 : rng.nextInt(8) + 1,
        barcode: _barcodeFor(reference, nextNumber + i),
        customerPhone: rng.nextInt(3) == 0
            ? null
            : _phoneFor(nextNumber + i, residential: residential),
      );
      await repository.saveDelivery(delivery);
      created.add(delivery);
    }

    return created;
  }

  /// A parcel label for a seeded stop.
  ///
  /// Shaped like a courier barcode — two letters and a long numeric run — so
  /// scanning the seeded manifest exercises the same path a real label would.
  /// Derived from the reference rather than random, so the same stop always
  /// carries the same label.
  static String _barcodeFor(String reference, int seed) {
    final digits = reference.replaceAll(RegExp(r'\D'), '');
    return 'JD$digits${(seed * 7919 % 1000000).toString().padLeft(6, '0')}';
  }

  /// Numbers come from the ranges reserved for fiction (07700 900xxx and
  /// 020 7946 0xxx), so a seeded manifest can never dial a real person.
  static String _phoneFor(int seed, {bool residential = false}) {
    final tail = (seed * 137 % 1000).toString().padLeft(3, '0');
    return residential ? '07700 900$tail' : '020 7946 0$tail';
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
