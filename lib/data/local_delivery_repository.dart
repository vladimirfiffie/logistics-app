import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/delivery.dart';
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
    await _db.insert(
      'deliveries',
      delivery.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
  Future<void> deleteEverything() async {
    await _db.transaction((txn) async {
      // Explicit rather than relying on cascade, so this still empties the
      // tables if a row was ever orphaned.
      await txn.delete('trip_points');
      await txn.delete('trips');
      await txn.delete('deliveries');
    });
  }

  @override
  Future<Trip> endTrip(String tripId, {required double distanceMeters}) async {
    final endedAt = DateTime.now();
    await _db.update(
      'trips',
      {
        'ended_at': endedAt.toUtc().millisecondsSinceEpoch,
        'distance_meters': distanceMeters,
      },
      where: 'id = ?',
      whereArgs: [tripId],
    );

    final rows = await _db.query(
      'trips',
      where: 'id = ?',
      whereArgs: [tripId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Trip $tripId no longer exists.');
    return Trip.fromMap(rows.first);
  }
}
