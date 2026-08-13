import 'package:flutter_test/flutter_test.dart';
import 'package:logistics_app/data/app_database.dart';
import 'package:logistics_app/data/local_delivery_repository.dart';
import 'package:logistics_app/models/delivery.dart';
import 'package:logistics_app/models/shift_break.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The schema exactly as v2 shipped, written out by hand.
///
/// Deliberately not built from the current `_createSchema` — the whole point
/// is to start from what a beta.3 phone actually has on disk and prove it
/// catches up. Deriving it from today's code would test nothing.
Future<void> _createV2Schema(Database db) async {
  await db.execute('''
    CREATE TABLE deliveries (
      id TEXT PRIMARY KEY,
      reference TEXT NOT NULL,
      customer_name TEXT NOT NULL,
      address TEXT NOT NULL,
      latitude REAL NOT NULL,
      longitude REAL NOT NULL,
      status TEXT NOT NULL,
      scheduled_for INTEGER NOT NULL,
      notes TEXT,
      parcel_count INTEGER NOT NULL DEFAULT 1,
      completed_at INTEGER,
      recipient_name TEXT,
      proof_photo_path TEXT,
      failure_reason TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE trips (
      id TEXT PRIMARY KEY,
      delivery_id TEXT NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
      started_at INTEGER NOT NULL,
      ended_at INTEGER,
      distance_meters REAL NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE trip_points (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
      latitude REAL NOT NULL,
      longitude REAL NOT NULL,
      accuracy REAL NOT NULL,
      speed REAL NOT NULL,
      heading REAL NOT NULL,
      altitude REAL NOT NULL,
      recorded_at INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE shifts (
      id TEXT PRIMARY KEY,
      started_at INTEGER NOT NULL,
      ended_at INTEGER,
      vehicle_label TEXT,
      started_by_tag INTEGER NOT NULL DEFAULT 0
    )
  ''');
}

void main() {
  sqfliteFfiInit();

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      ),
    );
  });

  tearDown(() => db.close());

  test('a v2 install upgrades to the current version keeping '
      'everything it had', () async {
    await _createV2Schema(db);

    // A round already part-done on the old version.
    await db.insert('deliveries', {
      'id': 'd1',
      'reference': 'LG-1040',
      'customer_name': 'Harlow & Sons',
      'address': '14 Bridgewater Road',
      'latitude': 51.52,
      'longitude': -0.10,
      'status': DeliveryStatus.delivered.name,
      'scheduled_for': DateTime.utc(2026, 8, 11, 9).millisecondsSinceEpoch,
      'parcel_count': 2,
      'recipient_name': 'Sam',
      'proof_photo_path': '/tmp/proof.jpg',
    });
    await db.insert('trips', {
      'id': 't1',
      'delivery_id': 'd1',
      'started_at': DateTime.utc(2026, 8, 11, 9).millisecondsSinceEpoch,
      'ended_at': DateTime.utc(2026, 8, 11, 9, 20).millisecondsSinceEpoch,
      'distance_meters': 4200.0,
    });
    await db.insert('shifts', {
      'id': 's1',
      'started_at': DateTime.utc(2026, 8, 11, 8).millisecondsSinceEpoch,
      'ended_at': null,
      'vehicle_label': 'LT21 KXR',
      'started_by_tag': 1,
    });

    await AppDatabase.upgradeSchemaForTesting(db, 2);

    final repository = LocalDeliveryRepository(db);

    // Nothing lost.
    final delivery = await repository.fetchDelivery('d1');
    expect(delivery!.recipientName, 'Sam');
    expect(delivery.proofPhotoPath, '/tmp/proof.jpg');
    expect(delivery.status, DeliveryStatus.delivered);
    expect((await repository.fetchTrips()).single.distanceMeters, 4200);

    final shift = await repository.activeShift();
    expect(shift!.vehicleLabel, 'LT21 KXR');
    expect(shift.startedByTag, isTrue);

    // And every column added since exists, at its default.
    expect(delivery.signaturePath, isNull);
    expect(delivery.barcode, isNull);
    expect(delivery.customerPhone, isNull);
    expect(delivery.failureAction, isNull);
    expect(delivery.parcelsScanned, 0);
    expect(delivery.attempt, 1);
    expect(delivery.previousAttemptId, isNull);
  });

  test('a v3 install picks up the v4 columns', () async {
    await _createV2Schema(db);
    await AppDatabase.upgradeSchemaForTesting(db, 2);
    final repository = LocalDeliveryRepository(db);

    await repository.saveDelivery(
      Delivery(
        id: 'd3',
        reference: 'LG-1041',
        customerName: 'Meridian Dental',
        address: '221 Oakfield Avenue',
        latitude: 51.5,
        longitude: -0.12,
        status: DeliveryStatus.pending,
        scheduledFor: DateTime(2026, 8, 12, 9),
        parcelCount: 3,
        barcode: 'JD1041000042',
        customerPhone: '020 7946 0123',
        parcelsScanned: 2,
      ),
    );

    final found = await repository.findByBarcode('JD1041000042');
    expect(found!.id, 'd3');
    expect(found.customerPhone, '020 7946 0123');
    expect(found.parcelsScanned, 2);
  });

  test('a failed stop can raise its next attempt', () async {
    await AppDatabase.createSchemaForTesting(db);
    final repository = LocalDeliveryRepository(db);

    final first = Delivery(
      id: 'd4',
      reference: 'LG-1042',
      customerName: 'Nadia Okonkwo',
      address: 'Flat 12B, Perrin House',
      latitude: 51.5,
      longitude: -0.12,
      status: DeliveryStatus.failed,
      scheduledFor: DateTime(2026, 8, 12, 9),
      parcelCount: 2,
      barcode: 'JD1042000007',
      failureReason: 'Nobody home',
      failureAction: FailureAction.cardedRetryTomorrow,
      completedAt: DateTime(2026, 8, 12, 16, 30),
    );
    await repository.saveDelivery(first);

    final next = await repository.raiseNextAttempt(
      first,
      scheduledFor: DateTime(2026, 8, 13, 9),
    );

    expect(next.attempt, 2);
    expect(next.previousAttemptId, 'd4');
    expect(next.status, DeliveryStatus.pending);
    expect(next.failureReason, isNull);
    expect(next.parcelCount, 2);

    // The failed attempt is still there, untouched.
    final failed = await repository.fetchDelivery('d4');
    expect(failed!.status, DeliveryStatus.failed);
    expect(failed.failureAction, FailureAction.cardedRetryTomorrow);

    // And scanning the shared label finds the attempt still open.
    expect((await repository.findByBarcode('JD1042000007'))!.id, next.id);
  });

  test('the upgrade adds a working breaks table', () async {
    await _createV2Schema(db);
    await AppDatabase.upgradeSchemaForTesting(db, 2);

    final repository = LocalDeliveryRepository(db);
    final shift = await repository.startShift();
    final taken = await repository.startBreak(shift.id, kind: BreakKind.meal);

    expect((await repository.activeBreak(shift.id))!.id, taken.id);
  });

  test('the new column is writable after the upgrade', () async {
    await _createV2Schema(db);
    await AppDatabase.upgradeSchemaForTesting(db, 2);

    final repository = LocalDeliveryRepository(db);
    await repository.saveDelivery(
      Delivery(
        id: 'd2',
        reference: 'LG-2',
        customerName: 'New',
        address: 'Somewhere',
        latitude: 51.5,
        longitude: -0.12,
        status: DeliveryStatus.pending,
        scheduledFor: DateTime(2026, 8, 12, 9),
        signaturePath: '/tmp/sig.png',
      ),
    );

    expect(
      (await repository.fetchDelivery('d2'))!.signaturePath,
      '/tmp/sig.png',
    );
  });

  test('a fresh install lands on the current version directly', () async {
    await AppDatabase.createSchemaForTesting(db);
    expect(AppDatabase.schemaVersion, 4);

    final repository = LocalDeliveryRepository(db);
    final shift = await repository.startShift();
    await repository.startBreak(shift.id);

    expect(await repository.activeBreak(shift.id), isNotNull);
  });
}
