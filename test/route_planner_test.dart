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

  group('planRoute time slots', () {
    test('never moves a later slot ahead of an earlier one', () {
      // The afternoon stop is right next to the driver and the morning stops
      // are miles east. Distance alone would do the afternoon one first.
      final stops = [
        _at('morning-far', lat: 0, lng: 8, hour: 9),
        _at('morning-near', lat: 0, lng: 6, hour: 9),
        _at('afternoon', lat: 0, lng: 1, hour: 15),
      ];

      final ordered = planRoute(
        stops,
        fromLatitude: 0,
        fromLongitude: 0,
        distanceBetween: _planar,
      );

      expect(ordered.map((stop) => stop.id), [
        'morning-near',
        'morning-far',
        'afternoon',
      ]);
    });

    test('optimises freely within a slot', () {
      final stops = [
        _at('c', lat: 0, lng: 3, hour: 9),
        _at('a', lat: 0, lng: 1, hour: 9),
        _at('b', lat: 0, lng: 2, hour: 9),
      ];

      expect(
        planRoute(
          stops,
          fromLatitude: 0,
          fromLongitude: 0,
          distanceBetween: _planar,
        ).map((stop) => stop.id),
        ['a', 'b', 'c'],
      );
    });

    test('respectSlots false ignores the booking times entirely', () {
      final stops = [
        _at('morning', lat: 0, lng: 8, hour: 9),
        _at('afternoon', lat: 0, lng: 1, hour: 15),
      ];

      expect(
        planRoute(
          stops,
          fromLatitude: 0,
          fromLongitude: 0,
          distanceBetween: _planar,
          respectSlots: false,
        ).map((stop) => stop.id),
        ['afternoon', 'morning'],
      );
    });
  });

  group('planRoute 2-opt', () {
    test('beats the order nearest-neighbour would have given', () {
      // Two stops east and two west. Nearest-neighbour takes the closer
      // eastern stop first and has to come back out for the other one before
      // heading west: 14.12. Doing the far eastern stop first and sweeping
      // back through the near one costs 12.81.
      final stops = [
        _at('east-near', lat: 2, lng: -3),
        _at('east-far', lat: 4, lng: -2),
        _at('west-near', lat: -3, lng: -4),
        _at('west-far', lat: -4, lng: -4),
      ];

      final planned = planRoute(
        stops,
        fromLatitude: 0,
        fromLongitude: 0,
        distanceBetween: _planar,
      );

      expect(planned.map((stop) => stop.id), [
        'east-far',
        'east-near',
        'west-near',
        'west-far',
      ]);
      expect(
        routeLength(
          planned,
          fromLatitude: 0,
          fromLongitude: 0,
          distanceBetween: _planar,
        ),
        closeTo(12.807, 0.001),
      );
    });

    test('keeps every stop exactly once after reordering', () {
      final stops = [
        for (var i = 0; i < 15; i++)
          _at(
            '$i',
            lat: ((i * 7) % 5).toDouble(),
            lng: ((i * 11) % 7).toDouble(),
          ),
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
