import 'dart:math';

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

  group('addStops', () {
    test('appends without disturbing what is already there', () async {
      await SeedData.ensureSeeded(repository);
      final before = await repository.fetchDeliveries();

      await SeedData.addStops(repository, count: 10, random: Random(1));

      final after = await repository.fetchDeliveries();
      expect(after, hasLength(before.length + 10));
      for (final original in before) {
        expect(after.any((stop) => stop.id == original.id), isTrue);
      }
    });

    test('references never collide with existing ones', () async {
      await SeedData.ensureSeeded(repository);
      await SeedData.addStops(repository, count: 25, random: Random(2));
      await SeedData.addStops(repository, count: 25, random: Random(3));

      final all = await repository.fetchDeliveries();
      final references = all.map((stop) => stop.reference).toList();

      expect(references.toSet(), hasLength(references.length));
    });

    test('added stops are pending and carry at least one parcel', () async {
      final created = await SeedData.addStops(
        repository,
        count: 20,
        random: Random(4),
      );

      for (final stop in created) {
        expect(stop.status, DeliveryStatus.pending);
        expect(stop.parcelCount, greaterThanOrEqualTo(1));
        expect(stop.customerName, isNotEmpty);
        expect(stop.address, isNotEmpty);
      }
    });

    test('queues new work after the latest slot already booked', () async {
      await SeedData.ensureSeeded(repository, now: DateTime(2026, 8, 11, 9));
      final latestBefore = (await repository.fetchDeliveries())
          .map((stop) => stop.scheduledFor)
          .reduce((a, b) => a.isAfter(b) ? a : b);

      final created = await SeedData.addStops(
        repository,
        count: 5,
        random: Random(5),
      );

      for (final stop in created) {
        expect(stop.scheduledFor.isAfter(latestBefore), isTrue);
      }
    });

    test('scatters stops around the driver, not into one quadrant', () async {
      const origin = LatLng(40.7128, -74.0060);
      final distance = const Distance();

      final created = await SeedData.addStops(
        repository,
        count: 30,
        origin: origin,
        random: Random(6),
      );

      var north = 0;
      var south = 0;
      for (final stop in created) {
        expect(
          distance.as(
            LengthUnit.Meter,
            origin,
            LatLng(stop.latitude, stop.longitude),
          ),
          lessThan(9000),
        );
        if (stop.latitude > origin.latitude) north++;
        if (stop.latitude < origin.latitude) south++;
      }
      expect(north, greaterThan(0));
      expect(south, greaterThan(0));
    });
  });
}
