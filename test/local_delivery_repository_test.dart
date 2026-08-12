import 'package:flutter_test/flutter_test.dart';
import 'package:logistics_app/data/app_database.dart';
import 'package:logistics_app/data/local_delivery_repository.dart';
import 'package:logistics_app/models/delivery.dart';
import 'package:logistics_app/models/trip_point.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Delivery _stop(String id, {DeliveryStatus status = DeliveryStatus.pending}) =>
    Delivery(
      id: id,
      reference: 'LG-$id',
      customerName: 'Customer $id',
      address: '$id Test Street',
      latitude: 51.5,
      longitude: -0.12,
      status: status,
      scheduledFor: DateTime(2026, 8, 11, 9),
      parcelCount: 2,
    );

TripPoint _point(
  String tripId, {
  required double lat,
  required double lng,
  double accuracy = 5,
  required DateTime at,
}) => TripPoint(
  tripId: tripId,
  latitude: lat,
  longitude: lng,
  accuracy: accuracy,
  speed: 8,
  heading: 90,
  altitude: 20,
  recordedAt: at,
);

void main() {
  sqfliteFfiInit();

  late Database db;
  late LocalDeliveryRepository repository;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      ),
    );
    await AppDatabase.createSchemaForTesting(db);
    repository = LocalDeliveryRepository(db);
  });

  tearDown(() => db.close());

  test('saves and reads back a delivery with every field intact', () async {
    final original = _stop('1').copyWith(
      status: DeliveryStatus.delivered,
      completedAt: DateTime(2026, 8, 11, 10, 30),
      recipientName: 'A. Receiver',
      proofPhotoPath: '/tmp/proof.jpg',
    );
    await repository.saveDelivery(original);

    final loaded = await repository.fetchDelivery('1');

    expect(loaded, isNotNull);
    expect(loaded!.reference, 'LG-1');
    expect(loaded.status, DeliveryStatus.delivered);
    expect(loaded.recipientName, 'A. Receiver');
    expect(loaded.proofPhotoPath, '/tmp/proof.jpg');
    expect(loaded.parcelCount, 2);
    expect(loaded.completedAt, DateTime(2026, 8, 11, 10, 30));
    expect(loaded.scheduledFor, DateTime(2026, 8, 11, 9));
  });

  test('deliveries come back ordered by scheduled slot', () async {
    await repository.saveDelivery(_stop('late'));
    await repository.saveDelivery(
      Delivery(
        id: 'early',
        reference: 'LG-early',
        customerName: 'Early',
        address: 'Somewhere',
        latitude: 51.5,
        longitude: -0.12,
        status: DeliveryStatus.pending,
        scheduledFor: DateTime(2026, 8, 11, 7),
      ),
    );

    final all = await repository.fetchDeliveries();

    expect(all.map((d) => d.id), ['early', 'late']);
  });

  test('starting a trip flips the stop to in transit', () async {
    await repository.saveDelivery(_stop('1'));

    final trip = await repository.startTrip('1');

    expect(trip.isActive, isTrue);
    expect(trip.deliveryId, '1');
    expect(
      (await repository.fetchDelivery('1'))!.status,
      DeliveryStatus.inTransit,
    );
    expect((await repository.activeTrip())!.id, trip.id);
  });

  test('a second concurrent trip is refused', () async {
    await repository.saveDelivery(_stop('1'));
    await repository.saveDelivery(_stop('2'));
    await repository.startTrip('1');

    expect(repository.startTrip('2'), throwsStateError);
    // The refused stop must not have been left mid-flight.
    expect(
      (await repository.fetchDelivery('2'))!.status,
      DeliveryStatus.pending,
    );
  });

  test('a new trip can start once the previous one ended', () async {
    await repository.saveDelivery(_stop('1'));
    await repository.saveDelivery(_stop('2'));
    final first = await repository.startTrip('1');
    await repository.endTrip(first.id, distanceMeters: 1200);

    final second = await repository.startTrip('2');

    expect(second.deliveryId, '2');
    expect((await repository.activeTrip())!.id, second.id);
  });

  test('ending a trip stores the distance and closes it', () async {
    await repository.saveDelivery(_stop('1'));
    final trip = await repository.startTrip('1');

    final ended = await repository.endTrip(trip.id, distanceMeters: 3456.7);

    expect(ended.isActive, isFalse);
    expect(ended.distanceMeters, closeTo(3456.7, 0.001));
    expect(await repository.activeTrip(), isNull);
  });

  test('ending a trip releases the stop back to pending', () async {
    await repository.saveDelivery(_stop('1'));
    final trip = await repository.startTrip('1');
    expect(
      (await repository.fetchDelivery('1'))!.status,
      DeliveryStatus.inTransit,
    );

    await repository.endTrip(trip.id, distanceMeters: 100);

    // Otherwise the stop reads "In transit" on the manifest for the rest of
    // the day with nothing recording behind it.
    expect(
      (await repository.fetchDelivery('1'))!.status,
      DeliveryStatus.pending,
    );
  });

  test('closing out a stop keeps its recorded trip and trail', () async {
    await repository.saveDelivery(_stop('1'));
    final trip = await repository.startTrip('1');
    await repository.appendPoint(
      _point(trip.id, lat: 51.50, lng: -0.12, at: DateTime(2026, 8, 11, 9)),
    );
    await repository.endTrip(trip.id, distanceMeters: 4200);

    // Exactly what completeDelivery does after ending the trip. Saved with
    // INSERT OR REPLACE this cascaded the trip and its breadcrumbs away, so
    // every finished stop lost the distance it had just recorded.
    await repository.saveDelivery(
      (await repository.fetchDelivery(
        '1',
      ))!.copyWith(status: DeliveryStatus.delivered, recipientName: 'Sam'),
    );

    expect(await repository.fetchTrips(), hasLength(1));
    expect((await repository.tripForDelivery('1'))!.distanceMeters, 4200);
    expect(await repository.pointsForTrip(trip.id), hasLength(1));
    expect(
      (await repository.fetchDelivery('1'))!.recipientName,
      'Sam',
      reason: 'the update still has to land',
    );
  });

  test('ending a trip leaves a stop that was already closed out', () async {
    await repository.saveDelivery(_stop('1'));
    final trip = await repository.startTrip('1');
    // The order completeDelivery uses: close the trip, then write the
    // outcome. Re-ending must not resurrect a delivered stop.
    await repository.saveDelivery(
      _stop('1').copyWith(status: DeliveryStatus.delivered),
    );

    await repository.endTrip(trip.id, distanceMeters: 100);

    expect(
      (await repository.fetchDelivery('1'))!.status,
      DeliveryStatus.delivered,
    );
  });

  test('breadcrumbs read back in the order they were recorded', () async {
    await repository.saveDelivery(_stop('1'));
    final trip = await repository.startTrip('1');
    final base = DateTime(2026, 8, 11, 9);

    // Inserted out of order on purpose: the query, not the caller, owns
    // ordering.
    await repository.appendPoint(
      _point(
        trip.id,
        lat: 51.52,
        lng: -0.10,
        at: base.add(const Duration(seconds: 20)),
      ),
    );
    await repository.appendPoint(
      _point(trip.id, lat: 51.50, lng: -0.12, at: base),
    );

    final points = await repository.pointsForTrip(trip.id);

    expect(points, hasLength(2));
    expect(points.first.latitude, closeTo(51.50, 1e-9));
    expect(points.last.latitude, closeTo(51.52, 1e-9));
    expect(points.first.accuracy, 5);
  });

  test('deleting a delivery takes its trips and breadcrumbs with it', () async {
    await repository.saveDelivery(_stop('1'));
    final trip = await repository.startTrip('1');
    await repository.appendPoint(
      _point(trip.id, lat: 51.5, lng: -0.12, at: DateTime(2026, 8, 11, 9)),
    );

    await db.delete('deliveries', where: 'id = ?', whereArgs: ['1']);

    expect(await repository.fetchTrips(), isEmpty);
    expect(await repository.pointsForTrip(trip.id), isEmpty);
  });
}
