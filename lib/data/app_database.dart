import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Opens (and migrates) the on-device SQLite database.
class AppDatabase {
  AppDatabase._();

  static const _fileName = 'logistics.db';

  /// v2 added the `shifts` table.
  /// v3 added the `breaks` table and `deliveries.signature_path`.
  static const _version = 3;

  static Database? _instance;

  static Future<Database> open() async {
    if (_instance != null) return _instance!;
    final directory = await getDatabasesPath();
    _instance = await openDatabase(
      p.join(directory, _fileName),
      version: _version,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
    return _instance!;
  }

  /// Used by tests to point at an in-memory database.
  static void overrideForTesting(Database db) => _instance = db;

  static Future<void> close() async {
    await _instance?.close();
    _instance = null;
  }

  static Future<void> _createSchema(Database db, int version) async {
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
        signature_path TEXT,
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

    // Breadcrumbs are always read as an ordered run for one trip.
    await db.execute(
      'CREATE INDEX idx_trip_points_trip ON trip_points(trip_id, recorded_at)',
    );
    await db.execute('CREATE INDEX idx_trips_delivery ON trips(delivery_id)');

    await _createShifts(db);
    await _createBreaks(db);
  }

  static Future<void> _createShifts(Database db) async {
    await db.execute('''
      CREATE TABLE shifts (
        id TEXT PRIMARY KEY,
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        vehicle_label TEXT,
        started_by_tag INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX idx_shifts_started ON shifts(started_at)');
  }

  /// Breaks belong to a shift and go with it: a deleted shift has no breaks to
  /// account for.
  static Future<void> _createBreaks(Database db) async {
    await db.execute('''
      CREATE TABLE breaks (
        id TEXT PRIMARY KEY,
        shift_id TEXT NOT NULL REFERENCES shifts(id) ON DELETE CASCADE,
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        kind TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_breaks_shift ON breaks(shift_id)');
  }

  /// Migrations run in order, each guarded by the version it introduced, so a
  /// device two versions behind catches up in one open rather than needing a
  /// reinstall.
  static Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) await _createShifts(db);
    if (oldVersion < 3) {
      await _createBreaks(db);
      await db.execute('ALTER TABLE deliveries ADD COLUMN signature_path TEXT');
    }
  }

  /// Schema statements, exposed so tests can build the same tables in memory.
  static Future<void> createSchemaForTesting(Database db) =>
      _createSchema(db, _version);

  /// Exposed so a test can prove an install two versions behind catches up
  /// without losing what it already had.
  static Future<void> upgradeSchemaForTesting(Database db, int from) =>
      _upgradeSchema(db, from, _version);

  static int get schemaVersion => _version;
}
