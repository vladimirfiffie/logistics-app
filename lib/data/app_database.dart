import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Opens (and migrates) the on-device SQLite database.
class AppDatabase {
  AppDatabase._();

  static const _fileName = 'logistics.db';
  static const _version = 1;

  static Database? _instance;

  static Future<Database> open() async {
    if (_instance != null) return _instance!;
    final directory = await getDatabasesPath();
    _instance = await openDatabase(
      p.join(directory, _fileName),
      version: _version,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _createSchema,
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
  }

  /// Schema statements, exposed so tests can build the same tables in memory.
  static Future<void> createSchemaForTesting(Database db) =>
      _createSchema(db, _version);
}
