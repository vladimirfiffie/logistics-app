import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/delivery.dart';
import '../models/shift.dart';
import '../models/trip.dart';
import '../models/trip_point.dart';
import 'delivery_repository.dart';

/// SQLite-backed implementation. Everything lives on the device; nothing is
/// uploaded.
class LocalDeliveryRepository implements DeliveryRepository {
  LocalDeliveryRepository(this._db, {Uuid uuid = const Uuid()}) : _uuid = uuid;

  final Database _db;

  /// Injectable so tests can pin the generated ids.
  final Uuid _uuid;

  @override
  Future<List<Delivery>> fetchDeliveries() async {
    final rows = await _db.query('deliveries', orderBy: 'scheduled_for ASC');
    return rows.map(Delivery.fromMap).toList();
  }

  @override
  Future<Delivery?> fetchDelivery(String id) async {
    final rows = await _db.query(
      'deliveries',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Delivery.fromMap(rows.first);
  }

  @override
  Future<void> saveDelivery(Delivery delivery) async {
    // Update-then-insert rather than INSERT OR REPLACE. SQLite implements
    // REPLACE as a delete followed by an insert, which fires
    // `trips.delivery_id ... ON DELETE CASCADE` — so re-saving a stop to mark
    // it delivered was silently taking its recorded trip and every breadcrumb
    // with it.
    final row = delivery.toMap();
    await _db.transaction((txn) async {
      final updated = await txn.update(
        'deliveries',
        row,
        where: 'id = ?',
        whereArgs: [delivery.id],
      );
      if (updated == 0) await txn.insert('deliveries', row);
    });
  }

  @override
  Future<Trip> startTrip(String deliveryId) async {
    final existing = await activeTrip();
    if (existing != null) {
      throw StateError(
        'A trip is already recording (${existing.id}). End it before starting '
        'another.',
      );
    }

    final trip = Trip(
      id: _uuid.v4(),
      deliveryId: deliveryId,
      startedAt: DateTime.now(),
    );

    await _db.transaction((txn) async {
      await txn.insert('trips', trip.toMap());
      await txn.update(
        'deliveries',
        {'status': DeliveryStatus.inTransit.name},
        where: 'id = ?',
        whereArgs: [deliveryId],
      );
    });

    return trip;
  }

  @override
  Future<Trip?> activeTrip() async {
    final rows = await _db.query(
      'trips',
      where: 'ended_at IS NULL',
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : Trip.fromMap(rows.first);
  }

  @override
  Future<Trip?> tripForDelivery(String deliveryId) async {
    final rows = await _db.query(
      'trips',
      where: 'delivery_id = ?',
      whereArgs: [deliveryId],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : Trip.fromMap(rows.first);
  }

  @override
  Future<List<Trip>> fetchTrips() async {
    final rows = await _db.query('trips', orderBy: 'started_at DESC');
    return rows.map(Trip.fromMap).toList();
  }

  @override
  Future<void> appendPoint(TripPoint point) async {
    await _db.insert('trip_points', point.toMap());
  }

  @override
  Future<List<TripPoint>> pointsForTrip(String tripId) async {
    final rows = await _db.query(
      'trip_points',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'recorded_at ASC, id ASC',
    );
    return rows.map(TripPoint.fromMap).toList();
  }

  @override
  Future<int> deleteClosedDeliveries() async {
    // Trips and breadcrumbs go with them via ON DELETE CASCADE.
    return _db.delete(
      'deliveries',
      where: 'status IN (?, ?)',
      whereArgs: [DeliveryStatus.delivered.name, DeliveryStatus.failed.name],
    );
  }

  @override
  Future<Shift?> activeShift() async {
    final rows = await _db.query(
      'shifts',
      where: 'ended_at IS NULL',
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : Shift.fromMap(rows.first);
  }

  @override
  Future<Shift> startShift({
    String? vehicleLabel,
    bool startedByTag = false,
  }) async {
    final existing = await activeShift();
    if (existing != null) {
      throw StateError('Already clocked on since ${existing.startedAt}.');
    }
    final shift = Shift(
      id: _uuid.v4(),
      startedAt: DateTime.now(),
      vehicleLabel: vehicleLabel,
      startedByTag: startedByTag,
    );
    await _db.insert('shifts', shift.toMap());
    return shift;
  }

  @override
  Future<Shift> endShift(String shiftId) async {
    await _db.update(
      'shifts',
      {'ended_at': DateTime.now().toUtc().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [shiftId],
    );
    final rows = await _db.query(
      'shifts',
      where: 'id = ?',
      whereArgs: [shiftId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Shift $shiftId no longer exists.');
    return Shift.fromMap(rows.first);
  }

  @override
  Future<List<Shift>> fetchShifts() async {
    final rows = await _db.query('shifts', orderBy: 'started_at DESC');
    return rows.map(Shift.fromMap).toList();
  }

  @override
  Future<void> deleteEverything() async {
    await _db.transaction((txn) async {
      // Explicit rather than relying on cascade, so this still empties the
      // tables if a row was ever orphaned.
      await txn.delete('trip_points');
      await txn.delete('trips');
      await txn.delete('deliveries');
      await txn.delete('shifts');
    });
  }

  @override
  Future<Trip> endTrip(String tripId, {required double distanceMeters}) async {
    final endedAt = DateTime.now();

    // Ending the trip has to release the stop as well. `startTrip` moves it to
    // inTransit, and nothing else moves it back — so without this the stop
    // stays "In transit" on the manifest for the rest of the day even though
    // no recording is running. Delivered and failed stops are left alone:
    // those are closed outcomes written after the trip ended.
    final rows = await _db.transaction((txn) async {
      await txn.update(
        'trips',
        {
          'ended_at': endedAt.toUtc().millisecondsSinceEpoch,
          'distance_meters': distanceMeters,
        },
        where: 'id = ?',
        whereArgs: [tripId],
      );

      final found = await txn.query(
        'trips',
        where: 'id = ?',
        whereArgs: [tripId],
        limit: 1,
      );
      if (found.isEmpty) throw StateError('Trip $tripId no longer exists.');

      await txn.update(
        'deliveries',
        {'status': DeliveryStatus.pending.name},
        where: 'id = ? AND status = ?',
        whereArgs: [
          found.first['delivery_id'] as String,
          DeliveryStatus.inTransit.name,
        ],
      );

      return found;
    });

    return Trip.fromMap(rows.first);
  }
}
