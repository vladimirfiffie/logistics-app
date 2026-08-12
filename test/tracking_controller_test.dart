import 'package:flutter_test/flutter_test.dart';
import 'package:logistics_app/models/delivery.dart';
import 'package:logistics_app/models/trip.dart';
import 'package:logistics_app/services/location_service.dart';
import 'package:logistics_app/state/tracking_controller.dart';

import 'fakes.dart';

void main() {
  late FakeDeliveryRepository repository;
  late FakeLocationService location;
  late TrackingController controller;
  late int manifestRefreshes;

  setUp(() {
    repository = FakeDeliveryRepository();
    location = FakeLocationService();
    manifestRefreshes = 0;
    controller = TrackingController(
      repository: repository,
      locationService: location,
      onManifestChanged: () async => manifestRefreshes++,
    );
  });

  tearDown(() async {
    controller.dispose();
    await location.dispose();
  });

  group('start', () {
    test('opens a trip and marks the stop in transit', () async {
      final delivery = makeDelivery();
      await repository.saveDelivery(delivery);

      final started = await controller.start(delivery);

      expect(started, isTrue);
      expect(controller.isTracking, isTrue);
      expect(controller.delivery, delivery);
      expect(repository.deliveries['d1']!.status, DeliveryStatus.inTransit);
      expect(manifestRefreshes, 1);
    });

    test('names the stop in the tracking notification', () async {
      final delivery = makeDelivery();
      await repository.saveDelivery(delivery);

      await controller.start(delivery);

      expect(location.lastNotificationText, contains('Harlow & Sons'));
    });

    test('refuses to start when permission is denied', () async {
      location.readiness = LocationReadiness.deniedForever;
      final delivery = makeDelivery();
      await repository.saveDelivery(delivery);

      final started = await controller.start(delivery);

      expect(started, isFalse);
      expect(controller.isTracking, isFalse);
      expect(controller.readiness, LocationReadiness.deniedForever);
      // Nothing may be written when tracking could not begin.
      expect(repository.trips, isEmpty);
      expect(repository.deliveries['d1']!.status, DeliveryStatus.pending);
    });

    test('surfaces a repository failure instead of half-starting', () async {
      final delivery = makeDelivery();
      await repository.saveDelivery(delivery);
      await repository.startTrip('other');

      final started = await controller.start(delivery);

      expect(started, isFalse);
      expect(controller.isTracking, isFalse);
      expect(controller.error, isStateError);
    });
  });

  group('odometer', () {
    test('accumulates one segment per fix after the first', () async {
      final delivery = makeDelivery();
      await repository.saveDelivery(delivery);
      await controller.start(delivery);

      location.emit(makePosition());
      await pumpEventQueue();
      expect(controller.distanceMeters, 0, reason: 'first fix has no segment');

      location.emit(makePosition(latitude: 51.51));
      location.emit(makePosition(latitude: 51.52));
      await pumpEventQueue();

      expect(controller.distanceMeters, 200);
      expect(controller.points, hasLength(3));
      expect(repository.points, hasLength(3));
    });

    test(
      'records a low-accuracy fix but keeps it out of the odometer',
      () async {
        final delivery = makeDelivery();
        await repository.saveDelivery(delivery);
        await controller.start(delivery);

        location.emit(makePosition());
        location.emit(makePosition(latitude: 51.6, accuracy: 400));
        location.emit(makePosition(latitude: 51.52));
        await pumpEventQueue();

        // Both segments touch the 400m fix, so neither counts — but the
        // breadcrumb is still on the trail.
        expect(controller.distanceMeters, 0);
        expect(controller.points, hasLength(3));
      },
    );

    test('a failed write does not tear down the live trip', () async {
      final delivery = makeDelivery();
      await repository.saveDelivery(delivery);
      await controller.start(delivery);
      repository.failOnAppend = true;

      location.emit(makePosition());
      location.emit(makePosition(latitude: 51.51));
      await pumpEventQueue();

      expect(controller.isTracking, isTrue);
      expect(controller.points, hasLength(2));
      expect(controller.distanceMeters, 100);
      expect(controller.error, isNotNull);
    });

    test('a stream error is surfaced without ending the trip', () async {
      final delivery = makeDelivery();
      await repository.saveDelivery(delivery);
      await controller.start(delivery);

      location.emitError(StateError('GPS hardware failure'));
      await pumpEventQueue();

      expect(controller.error, isStateError);
      expect(controller.isTracking, isTrue);
    });
  });

  group('stop', () {
    test('writes the final distance and stops listening', () async {
      final delivery = makeDelivery();
      await repository.saveDelivery(delivery);
      await controller.start(delivery);
      location.emit(makePosition());
      location.emit(makePosition(latitude: 51.51));
      await pumpEventQueue();

      final finished = await controller.stop();

      expect(finished, isNotNull);
      expect(finished!.isActive, isFalse);
      expect(finished.distanceMeters, 100);
      expect(controller.isTracking, isFalse);
      expect(manifestRefreshes, 2);

      // Fixes arriving after the stop must not be recorded.
      location.emit(makePosition(latitude: 51.9));
      await pumpEventQueue();
      expect(controller.points, hasLength(2));
    });

    test('clear() only drops a finished trip', () async {
      final delivery = makeDelivery();
      await repository.saveDelivery(delivery);
      await controller.start(delivery);

      controller.clear();
      expect(controller.trip, isNotNull, reason: 'still recording');

      await controller.stop();
      controller.clear();
      expect(controller.trip, isNull);
      expect(controller.delivery, isNull);
      expect(controller.points, isEmpty);
    });
  });

  group('restore', () {
    test('picks up a trip left open by a previous process', () async {
      final delivery = makeDelivery();
      await repository.saveDelivery(delivery);
      final orphan = await repository.startTrip('d1');
      await repository.appendPoint(
        makeTripPoint(orphan.id, DateTime(2026, 8, 11, 9)),
      );
      await repository.appendPoint(
        makeTripPoint(orphan.id, DateTime(2026, 8, 11, 9, 1)),
      );
      await repository.appendPoint(
        makeTripPoint(orphan.id, DateTime(2026, 8, 11, 9, 2)),
      );

      await controller.restore();

      expect(controller.isTracking, isTrue);
      expect(controller.trip!.id, orphan.id);
      expect(controller.delivery!.id, 'd1');
      expect(controller.points, hasLength(3));
      // Two segments, rebuilt from the stored breadcrumbs.
      expect(controller.distanceMeters, 200);

      // And it is genuinely listening again.
      location.emit(makePosition());
      await pumpEventQueue();
      expect(controller.points, hasLength(4));
    });

    test('trusts the stored distance when the trip already had one', () async {
      final delivery = makeDelivery();
      await repository.saveDelivery(delivery);
      final orphan = await repository.startTrip('d1');
      repository.trips[orphan.id] = Trip(
        id: orphan.id,
        deliveryId: 'd1',
        startedAt: orphan.startedAt,
        distanceMeters: 5000,
      );

      await controller.restore();

      expect(controller.distanceMeters, 5000);
    });

    test('does nothing when no trip was left open', () async {
      await controller.restore();

      expect(controller.isTracking, isFalse);
      expect(controller.trip, isNull);
    });
  });

  test(
    'openRelevantSettings picks the screen that matches the problem',
    () async {
      location.readiness = LocationReadiness.serviceDisabled;
      await controller.start(makeDelivery());
      await controller.openRelevantSettings();
      expect(location.locationSettingsOpened, 1);
      expect(location.settingsOpened, 0);

      location.readiness = LocationReadiness.deniedForever;
      await controller.start(makeDelivery());
      await controller.openRelevantSettings();
      expect(location.settingsOpened, 1);
    },
  );
}
