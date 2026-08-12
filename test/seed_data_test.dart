import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:logistics_app/data/seed_data.dart';
import 'package:logistics_app/models/delivery.dart';

import 'fakes.dart';

void main() {
  late FakeDeliveryRepository repository;

  setUp(() => repository = FakeDeliveryRepository());

  test('seeds a full day of pending stops on an empty repository', () async {
    await SeedData.ensureSeeded(repository);

    final stops = await repository.fetchDeliveries();
    expect(stops, hasLength(6));
    expect(
      stops.every((stop) => stop.status == DeliveryStatus.pending),
      isTrue,
    );
    expect(stops.map((stop) => stop.reference).toSet(), hasLength(6));
  });

  test('does not seed twice', () async {
    await SeedData.ensureSeeded(repository);
    await SeedData.ensureSeeded(repository);

    expect(await repository.fetchDeliveries(), hasLength(6));
  });

  test('places stops within a few km of the driver', () async {
    const origin = LatLng(40.7128, -74.0060);
    final distance = const Distance();

    await SeedData.ensureSeeded(repository, origin: origin);

    for (final stop in await repository.fetchDeliveries()) {
      final metres = distance.as(
        LengthUnit.Meter,
        origin,
        LatLng(stop.latitude, stop.longitude),
      );
      expect(
        metres,
        lessThan(6000),
        reason: '${stop.customerName} should be on the same round',
      );
      expect(metres, greaterThan(200));
    }
  });

  test('falls back to a fixed origin when there is no fix', () async {
    final distance = const Distance();

    await SeedData.ensureSeeded(repository, origin: null);

    for (final stop in await repository.fetchDeliveries()) {
      expect(
        distance.as(
          LengthUnit.Meter,
          SeedData.fallbackOrigin,
          LatLng(stop.latitude, stop.longitude),
        ),
        lessThan(6000),
      );
    }
  });

  test('schedules the stops across the working day', () async {
    await SeedData.ensureSeeded(repository, now: DateTime(2026, 8, 11, 14, 30));

    final stops = await repository.fetchDeliveries()
      ..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));

    expect(stops.first.scheduledFor, DateTime(2026, 8, 11, 9));
    expect(stops.last.scheduledFor, DateTime(2026, 8, 11, 14));
  });
}
