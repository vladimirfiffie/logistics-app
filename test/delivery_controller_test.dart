import 'package:flutter_test/flutter_test.dart';
import 'package:logistics_app/models/delivery.dart';
import 'package:logistics_app/state/delivery_controller.dart';

import 'fakes.dart';

Delivery _stop(
  String id, {
  required DeliveryStatus status,
  required int hour,
  int parcels = 1,
  DateTime? completedAt,
}) => Delivery(
  id: id,
  reference: 'LG-$id',
  customerName: 'Customer $id',
  address: 'Somewhere',
  latitude: 51.5,
  longitude: -0.12,
  status: status,
  scheduledFor: DateTime(2026, 8, 11, hour),
  parcelCount: parcels,
  completedAt: completedAt,
);

void main() {
  late FakeDeliveryRepository repository;
  late DeliveryController controller;

  setUp(() {
    repository = FakeDeliveryRepository();
    controller = DeliveryController(repository);
  });

  test('splits the manifest into open and closed stops', () async {
    await repository.saveDelivery(
      _stop('a', status: DeliveryStatus.pending, hour: 9, parcels: 3),
    );
    await repository.saveDelivery(
      _stop('b', status: DeliveryStatus.inTransit, hour: 10, parcels: 2),
    );
    await repository.saveDelivery(
      _stop(
        'c',
        status: DeliveryStatus.delivered,
        hour: 8,
        completedAt: DateTime(2026, 8, 11, 8, 30),
      ),
    );
    await repository.saveDelivery(
      _stop(
        'd',
        status: DeliveryStatus.failed,
        hour: 7,
        completedAt: DateTime(2026, 8, 11, 11),
      ),
    );

    await controller.load();

    expect(controller.openStops.map((d) => d.id), ['a', 'b']);
    expect(controller.remainingParcels, 5);
    // Closed stops read newest-first, so the last thing done is at the top.
    expect(controller.closedStops.map((d) => d.id), ['d', 'c']);
  });

  test('marking delivered stores the proof and closes the stop', () async {
    await repository.saveDelivery(
      _stop('a', status: DeliveryStatus.inTransit, hour: 9),
    );
    await controller.load();

    await controller.markDelivered(
      controller.byId('a')!,
      recipientName: 'J. Smith',
      proofPhotoPath: '/proofs/a.jpg',
    );

    final stop = controller.byId('a')!;
    expect(stop.status, DeliveryStatus.delivered);
    expect(stop.recipientName, 'J. Smith');
    expect(stop.proofPhotoPath, '/proofs/a.jpg');
    expect(stop.completedAt, isNotNull);
    expect(controller.openStops, isEmpty);
  });

  test('marking failed records the reason', () async {
    await repository.saveDelivery(
      _stop('a', status: DeliveryStatus.inTransit, hour: 9),
    );
    await controller.load();

    await controller.markFailed(controller.byId('a')!, reason: 'Nobody home');

    final stop = controller.byId('a')!;
    expect(stop.status, DeliveryStatus.failed);
    expect(stop.failureReason, 'Nobody home');
    expect(controller.closedStops.single.id, 'a');
  });

  test('byId returns null for a stop that is not on the run', () async {
    await controller.load();

    expect(controller.byId('nope'), isNull);
  });

  group('failed stops', () {
    test('a carded stop comes back as a second attempt', () async {
      await repository.saveDelivery(
        _stop('a', status: DeliveryStatus.inTransit, hour: 9, parcels: 3),
      );
      await controller.load();

      final retry = await controller.markFailed(
        controller.byId('a')!,
        reason: 'Nobody home',
        action: FailureAction.cardedRetryTomorrow,
      );

      // The attempt that failed is still the record of what happened.
      final failed = controller.byId('a')!;
      expect(failed.status, DeliveryStatus.failed);
      expect(failed.failureAction, FailureAction.cardedRetryTomorrow);

      // And the parcel is on the run again, carrying everything it needs.
      expect(retry, isNotNull);
      expect(retry!.attempt, 2);
      expect(retry.previousAttemptId, 'a');
      expect(retry.status, DeliveryStatus.pending);
      expect(retry.parcelCount, 3);
      expect(retry.failureReason, isNull);
      expect(retry.completedAt, isNull);

      expect(controller.openStops.single.id, retry.id);
      expect(controller.closedStops.single.id, 'a');
    });

    test('returning to the depot raises nothing', () async {
      await repository.saveDelivery(
        _stop('a', status: DeliveryStatus.inTransit, hour: 9),
      );
      await controller.load();

      final retry = await controller.markFailed(
        controller.byId('a')!,
        reason: 'Refused by customer',
        action: FailureAction.returnToDepot,
      );

      expect(retry, isNull);
      expect(controller.openStops, isEmpty);
      expect(controller.byId('a')!.failureAction, FailureAction.returnToDepot);
    });

    test('a retry today is due in two hours, carding is tomorrow at nine', () {
      final failedAt = DateTime(2026, 8, 12, 16, 30);

      expect(
        FailureAction.retryToday.nextAttemptAfter(failedAt),
        DateTime(2026, 8, 12, 18, 30),
      );
      // Not "in 24 hours": a stop failed at half four should not come back at
      // half four the next day.
      expect(
        FailureAction.cardedRetryTomorrow.nextAttemptAfter(failedAt),
        DateTime(2026, 8, 13, 9),
      );
    });

    test('the follow-up rolls over the end of a month', () {
      expect(
        FailureAction.cardedRetryTomorrow.nextAttemptAfter(
          DateTime(2026, 8, 31, 17),
        ),
        DateTime(2026, 9, 1, 9),
      );
    });
  });

  group('parcels scanned', () {
    test('records what was scanned off, capped at the parcel count', () async {
      await repository.saveDelivery(
        _stop('a', status: DeliveryStatus.inTransit, hour: 9, parcels: 4),
      );
      await controller.load();

      await controller.recordParcelsScanned(controller.byId('a')!, 3);
      expect(controller.byId('a')!.parcelsScanned, 3);

      // Scanning the same label twice must not invent a fifth parcel.
      await controller.recordParcelsScanned(controller.byId('a')!, 9);
      expect(controller.byId('a')!.parcelsScanned, 4);

      await controller.recordParcelsScanned(controller.byId('a')!, -2);
      expect(controller.byId('a')!.parcelsScanned, 0);
    });

    test('a scanned label finds the attempt that is still open', () async {
      const barcode = 'JD1040000123';
      await repository.saveDelivery(
        Delivery(
          id: 'first',
          reference: 'LG-1040',
          customerName: 'Nadia Okonkwo',
          address: 'Flat 12B',
          latitude: 51.5,
          longitude: -0.12,
          status: DeliveryStatus.failed,
          scheduledFor: DateTime(2026, 8, 11, 9),
          barcode: barcode,
          completedAt: DateTime(2026, 8, 11, 16),
        ),
      );
      await controller.load();

      final retry = await repository.raiseNextAttempt(
        controller.byId('first')!,
        scheduledFor: DateTime(2026, 8, 12, 9),
      );
      await controller.refresh();

      expect((await controller.findByBarcode(barcode))!.id, retry.id);
      expect(await controller.findByBarcode('nothing-like-it'), isNull);
    });
  });
}
