import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:logistics_app/models/delivery.dart';
import 'package:logistics_app/services/route_planner.dart';

/// Planar distance. Good enough over a delivery round, and it keeps the
/// expected orderings in these tests obvious by inspection.
double _planar(double lat1, double lng1, double lat2, double lng2) =>
    math.sqrt(math.pow(lat1 - lat2, 2) + math.pow(lng1 - lng2, 2));

Delivery _at(
  String id, {
  required double lat,
  required double lng,
  int hour = 9,
}) => Delivery(
  id: id,
  reference: 'LG-$id',
  customerName: 'Customer $id',
  address: '$id Test Street',
  latitude: lat,
  longitude: lng,
  status: DeliveryStatus.pending,
  scheduledFor: DateTime(2026, 8, 12, hour),
);

void main() {
  group('planRoute', () {
    test('visits the nearest unvisited stop each time', () {
      // Laid out along a line east of the driver, deliberately out of order.
      final stops = [
        _at('far', lat: 0, lng: 3),
        _at('near', lat: 0, lng: 1),
        _at('mid', lat: 0, lng: 2),
      ];

      final ordered = planRoute(
        stops,
        fromLatitude: 0,
        fromLongitude: 0,
        distanceBetween: _planar,
      );

      expect(ordered.map((stop) => stop.id), ['near', 'mid', 'far']);
    });

    test('keeps every stop exactly once', () {
      final stops = [
        for (var i = 0; i < 12; i++)
          _at('$i', lat: (i % 4).toDouble(), lng: (i % 3).toDouble()),
      ];

      final ordered = planRoute(
        stops,
        fromLatitude: 0,
        fromLongitude: 0,
        distanceBetween: _planar,
      );

      expect(ordered, hasLength(stops.length));
      expect(
        ordered.map((stop) => stop.id).toSet(),
        stops.map((stop) => stop.id).toSet(),
      );
    });

    test('does not mutate the list it was given', () {
      final stops = [_at('far', lat: 0, lng: 3), _at('near', lat: 0, lng: 1)];

      planRoute(
        stops,
        fromLatitude: 0,
        fromLongitude: 0,
        distanceBetween: _planar,
      );

      expect(stops.map((stop) => stop.id), ['far', 'near']);
    });

    test('handles empty and single-stop rounds', () {
      expect(
        planRoute(
          const [],
          fromLatitude: 0,
          fromLongitude: 0,
          distanceBetween: _planar,
        ),
        isEmpty,
      );
      expect(
        planRoute(
          [_at('only', lat: 1, lng: 1)],
          fromLatitude: 0,
          fromLongitude: 0,
          distanceBetween: _planar,
        ),
        hasLength(1),
      );
    });
  });

  group('routeLength', () {
    test('measures from the driver through every stop in order', () {
      final stops = [_at('a', lat: 0, lng: 1), _at('b', lat: 0, lng: 3)];

      // 0→1 then 1→3.
      expect(
        routeLength(
          stops,
          fromLatitude: 0,
          fromLongitude: 0,
          distanceBetween: _planar,
        ),
        closeTo(3, 1e-9),
      );
    });

    test('the planned order is never longer than the worst order', () {
      final stops = [
        _at('far', lat: 0, lng: 5),
        _at('near', lat: 0, lng: 1),
        _at('mid', lat: 0, lng: 3),
      ];

      double measure(List<Delivery> order) => routeLength(
        order,
        fromLatitude: 0,
        fromLongitude: 0,
        distanceBetween: _planar,
      );

      final planned = planRoute(
        stops,
        fromLatitude: 0,
        fromLongitude: 0,
        distanceBetween: _planar,
      );

      // far → near → mid is the pathological order; nearest-neighbour is
      // optimal on a line, so the saving here is real and large.
      expect(measure(planned), lessThan(measure(stops)));
      expect(measure(planned), closeTo(5, 1e-9));
    });
  });
}
