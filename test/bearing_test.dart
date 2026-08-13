import 'package:flutter_test/flutter_test.dart';
import 'package:logistics_app/services/bearing.dart';

void main() {
  // The odometer's arithmetic now that the app measures its own distances
  // rather than asking the location plugin to. Every recorded mile — and
  // every mileage claim made from one — comes through here.
  group('distanceBetweenMeters', () {
    test('a point is no distance from itself', () {
      expect(distanceBetweenMeters(51.5, -0.12, 51.5, -0.12), 0);
    });

    test('one degree of latitude is about 111 km, anywhere', () {
      expect(distanceBetweenMeters(0, 0, 1, 0), closeTo(111195, 5));
      expect(distanceBetweenMeters(51, -0.12, 52, -0.12), closeTo(111195, 5));
    });

    test('a degree of longitude shrinks towards the poles', () {
      final atEquator = distanceBetweenMeters(0, 0, 0, 1);
      final atLondon = distanceBetweenMeters(51.5, 0, 51.5, 1);

      expect(atEquator, closeTo(111195, 5));
      // cos(51.5°) ≈ 0.62, so roughly 69 km.
      expect(atLondon, closeTo(111195 * 0.6225, 200));
      expect(atLondon, lessThan(atEquator));
    });

    test('London to Paris comes out at the published distance', () {
      expect(
        distanceBetweenMeters(51.5074, -0.1278, 48.8566, 2.3522),
        closeTo(343500, 1500),
      );
    });

    test('measures the same both ways round', () {
      final there = distanceBetweenMeters(51.5074, -0.1278, 53.4808, -2.2426);
      final back = distanceBetweenMeters(53.4808, -2.2426, 51.5074, -0.1278);
      expect(there, closeTo(back, 0.001));
    });

    test('a door-to-door hop is metres, not kilometres', () {
      // 0.0001° of latitude — about eleven metres, the scale the odometer
      // actually adds up over a round.
      expect(
        distanceBetweenMeters(51.5, -0.12, 51.5001, -0.12),
        closeTo(11, 1),
      );
    });
  });

  group('bearingDegrees', () {
    // Around London, so the numbers are the ones the app actually deals in.
    const lat = 51.5;
    const lng = -0.12;

    test('reads north, east, south and west off a compass', () {
      expect(bearingDegrees(lat, lng, lat + 0.1, lng), closeTo(0, 0.5));
      expect(bearingDegrees(lat, lng, lat, lng + 0.1), closeTo(90, 0.5));
      expect(bearingDegrees(lat, lng, lat - 0.1, lng), closeTo(180, 0.5));
      expect(bearingDegrees(lat, lng, lat, lng - 0.1), closeTo(270, 0.5));
    });

    test('always comes back in 0–360, never negative', () {
      final west = bearingDegrees(lat, lng, lat, lng - 0.5);
      expect(west, greaterThanOrEqualTo(0));
      expect(west, lessThan(360));
    });

    test('a stop you are standing on has no meaningful bearing, but does not '
        'blow up', () {
      expect(bearingDegrees(lat, lng, lat, lng), isA<double>());
    });
  });

  group('compassPoint', () {
    test('names the eight points', () {
      expect(compassPoint(0), 'N');
      expect(compassPoint(45), 'NE');
      expect(compassPoint(90), 'E');
      expect(compassPoint(135), 'SE');
      expect(compassPoint(180), 'S');
      expect(compassPoint(225), 'SW');
      expect(compassPoint(270), 'W');
      expect(compassPoint(315), 'NW');
    });

    test('rounds to the nearest point at the boundaries', () {
      expect(compassPoint(22), 'N');
      expect(compassPoint(23), 'NE');
      expect(compassPoint(359), 'N');
      // Wrapping past a full turn is the same direction.
      expect(compassPoint(360 + 90), 'E');
      expect(compassPoint(-90), 'W');
    });
  });

  group('relativeBearing', () {
    test('0 is dead ahead whichever way you are facing', () {
      expect(relativeBearing(0, 0), 0);
      expect(relativeBearing(270, 270), 0);
    });

    test('positive is to the right, negative to the left', () {
      // Facing north, the stop is due east: a right turn.
      expect(relativeBearing(90, 0), 90);
      // Facing north, the stop is due west: a left turn.
      expect(relativeBearing(270, 0), -90);
    });

    test('takes the short way round the compass', () {
      // Facing north-west, stop just east of north — a small turn right, not
      // a 315° sweep.
      expect(relativeBearing(10, 315), closeTo(55, 0.001));
      expect(relativeBearing(350, 10), closeTo(-20, 0.001));
    });
  });

  group('describeRelative', () {
    test('says what a passenger would say', () {
      expect(describeRelative(0), 'straight ahead');
      expect(describeRelative(-15), 'straight ahead');
      expect(describeRelative(40), 'ahead and to your right');
      expect(describeRelative(-40), 'ahead and to your left');
      expect(describeRelative(95), 'to your right');
      expect(describeRelative(-95), 'to your left');
      expect(describeRelative(140), 'behind you, to the right');
      expect(describeRelative(179), 'behind you');
      expect(describeRelative(-180), 'behind you');
    });
  });
}
