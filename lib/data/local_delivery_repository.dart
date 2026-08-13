import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/delivery.dart';
import '../models/shift.dart';
import '../models/shift_break.dart';
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
  Future<Delivery?> findByBarcode(String barcode) async {
    final trimmed = barcode.trim();
    if (trimmed.isEmpty) return null;

    // Open stops first, then the most recent closed one — scanning a label
    // for a stop already delivered should still find it, so the sheet can say
    // "this one is done" rather than "not on your manifest".
    final rows = await _db.query(
      'deliveries',
      where: 'barcode = ?',
      whereArgs: [trimmed],
      orderBy: 'attempt DESC, scheduled_for ASC',
    );
    if (rows.isEmpty) return null;

    final found = rows.map(Delivery.fromMap).toList();
    for (final delivery in found) {
      if (delivery.status.isOpen) return delivery;
    }
    return found.first;
  }

  @override
  Future<Delivery> raiseNextAttempt(
    Delivery failed, {
    required DateTime scheduledFor,
  }) async {
    final next = failed.nextAttempt(id: _uuid.v4(), scheduledFor: scheduledFor);
    await _db.insert('deliveries', next.toMap());
    return next;
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
    // Read the attachments before the rows go: ON DELETE CASCADE cleans up
    // trips and breadcrumbs, but SQLite knows nothing about the files on
    // disk, and a deleted stop's proof photo has no business outliving it.
    final closed = await _db.query(
      'deliveries',
      columns: ['proof_photo_path', 'signature_path'],
      where: 'status IN (?, ?)',
      whereArgs: [DeliveryStatus.delivered.name, DeliveryStatus.failed.name],
    );

    final removed = await _db.delete(
      'deliveries',
      where: 'status IN (?, ?)',
      whereArgs: [DeliveryStatus.delivered.name, DeliveryStatus.failed.name],
    );

    await _deleteFiles([
      for (final row in closed) ...[
        row['proof_photo_path'] as String?,
        row['signature_path'] as String?,
      ],
    ]);
    return removed;
  }

  /// Best-effort. A file that has already gone, or one on storage that has
  /// been unmounted, must not turn "clear history" into an error — the rows
  /// are the record, the files are only attachments.
  Future<void> _deleteFiles(Iterable<String?> paths) async {
    for (final path in paths) {
      if (path == null || path.isEmpty) continue;
      try {
        final file = File(path);
        if (file.existsSync()) await file.delete();
      } catch (error) {
        debugPrint('could not delete attachment $path: $error');
      }
    }
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
    final rows = await _db.transaction((txn) async {
      // `ended_at IS NULL` in the WHERE clause, not just the id: ending an
      // already-closed shift would otherwise silently rewrite the end time on
      // a timesheet the driver is paid from.
      final closed = await txn.update(
        'shifts',
        {'ended_at': DateTime.now().toUtc().millisecondsSinceEpoch},
        where: 'id = ? AND ended_at IS NULL',
        whereArgs: [shiftId],
      );

      final found = await txn.query(
        'shifts',
        where: 'id = ?',
        whereArgs: [shiftId],
        limit: 1,
      );
      if (found.isEmpty) throw StateError('Shift $shiftId no longer exists.');
      if (closed == 0) {
        throw StateError('Shift $shiftId was already clocked off.');
      }

      // A break left running ends with the shift rather than being left open
      // forever and counting against every future total.
      await txn.update(
        'breaks',
        {'ended_at': DateTime.now().toUtc().millisecondsSinceEpoch},
        where: 'shift_id = ? AND ended_at IS NULL',
        whereArgs: [shiftId],
      );

      return found;
    });

    return Shift.fromMap(rows.first);
  }

  @override
  Future<List<Shift>> fetchShifts() async {
    final rows = await _db.query('shifts', orderBy: 'started_at DESC');
    return rows.map(Shift.fromMap).toList();
  }

  @override
  Future<ShiftBreak?> activeBreak(String shiftId) async {
    final rows = await _db.query(
      'breaks',
      where: 'shift_id = ? AND ended_at IS NULL',
      whereArgs: [shiftId],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : ShiftBreak.fromMap(rows.first);
  }

  @override
  Future<ShiftBreak> startBreak(
    String shiftId, {
    BreakKind kind = BreakKind.rest,
  }) async {
    final existing = await activeBreak(shiftId);
    if (existing != null) {
      throw StateError('A break has been running since ${existing.startedAt}.');
    }
    final taken = ShiftBreak(
      id: _uuid.v4(),
      shiftId: shiftId,
      startedAt: DateTime.now(),
      kind: kind,
    );
    await _db.insert('breaks', taken.toMap());
    return taken;
  }

  @override
  Future<ShiftBreak> endBreak(String breakId) async {
    final rows = await _db.transaction((txn) async {
      final closed = await txn.update(
        'breaks',
        {'ended_at': DateTime.now().toUtc().millisecondsSinceEpoch},
        where: 'id = ? AND ended_at IS NULL',
        whereArgs: [breakId],
      );
      final found = await txn.query(
        'breaks',
        where: 'id = ?',
        whereArgs: [breakId],
        limit: 1,
      );
      if (found.isEmpty) throw StateError('Break $breakId no longer exists.');
      if (closed == 0) throw StateError('Break $breakId already ended.');
      return found;
    });
    return ShiftBreak.fromMap(rows.first);
  }

  @override
  Future<List<ShiftBreak>> breaksForShift(String shiftId) async {
    final rows = await _db.query(
      'breaks',
      where: 'shift_id = ?',
      whereArgs: [shiftId],
      orderBy: 'started_at ASC',
    );
    return rows.map(ShiftBreak.fromMap).toList();
  }

  @override
  Future<Map<String, List<ShiftBreak>>> breaksForShifts(
    List<String> shiftIds,
  ) async {
    if (shiftIds.isEmpty) return const {};
    final placeholders = List.filled(shiftIds.length, '?').join(', ');
    final rows = await _db.query(
      'breaks',
      where: 'shift_id IN ($placeholders)',
      whereArgs: shiftIds,
      orderBy: 'started_at ASC',
    );

    final grouped = <String, List<ShiftBreak>>{};
    for (final row in rows) {
      final taken = ShiftBreak.fromMap(row);
      grouped.putIfAbsent(taken.shiftId, () => []).add(taken);
    }
    return grouped;
  }

  @override
  Future<void> deleteEverything() async {
    final attachments = await _db.query(
      'deliveries',
      columns: ['proof_photo_path', 'signature_path'],
    );

    await _db.transaction((txn) async {
      // Explicit rather than relying on cascade, so this still empties the
      // tables if a row was ever orphaned.
      await txn.delete('trip_points');
      await txn.delete('trips');
      await txn.delete('deliveries');
      await txn.delete('breaks');
      await txn.delete('shifts');
    });

    await _deleteFiles([
      for (final row in attachments) ...[
        row['proof_photo_path'] as String?,
        row['signature_path'] as String?,
      ],
    ]);
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
