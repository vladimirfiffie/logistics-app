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
}
