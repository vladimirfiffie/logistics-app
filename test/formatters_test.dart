import 'package:flutter_test/flutter_test.dart';
import 'package:logistics_app/ui/formatters.dart';

void main() {
  group('formatDistance', () {
    test('stays in metres below a kilometre', () {
      expect(formatDistance(0), '0 m');
      expect(formatDistance(842.4), '842 m');
      expect(formatDistance(999.4), '999 m');
    });

    test('switches to kilometres, losing a decimal past 10km', () {
      expect(formatDistance(1000), '1.00 km');
      expect(formatDistance(4237), '4.24 km');
      expect(formatDistance(15400), '15.4 km');
    });

    test('does not print garbage for a non-finite distance', () {
      expect(formatDistance(double.nan), '—');
      expect(formatDistance(double.infinity), '—');
    });
  });

  group('formatDuration', () {
    test('drops seconds once there are hours to show', () {
      expect(formatDuration(const Duration(seconds: 45)), '45s');
      expect(formatDuration(const Duration(minutes: 7, seconds: 5)), '7m 05s');
      expect(formatDuration(const Duration(hours: 2, minutes: 3)), '2h 03m');
    });

    test('treats a negative duration as elapsed time, not a minus sign', () {
      expect(formatDuration(const Duration(seconds: -20)), '20s');
    });
  });

  test('formatSpeed converts m/s to km/h', () {
    expect(formatSpeed(0), '0.0 km/h');
    expect(formatSpeed(13.4), '48.2 km/h');
    expect(formatSpeed(-1), '—');
  });

  test('formatAccuracy reads as a tolerance', () {
    expect(formatAccuracy(4.6), '±5 m');
  });

  test('coordinates are pasteable into a map app', () {
    expect(formatCoordinates(51.507351, -0.127758), '51.50735, -0.12776');
  });
}
