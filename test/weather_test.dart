import 'package:flutter_test/flutter_test.dart';
import 'package:logistics_app/services/weather_service.dart';

String _body({
  double temperature = 11.4,
  int code = 3,
  double wind = 12.0,
  int isDay = 1,
}) =>
    '''
{"latitude":51.5,"longitude":-0.12,
 "current":{"time":"2026-08-11T09:00","temperature_2m":$temperature,
 "apparent_temperature":9.8,"precipitation":0.0,"weather_code":$code,
 "wind_speed_10m":$wind,"is_day":$isDay}}
''';

void main() {
  group('parsing', () {
    test('reads the current block', () {
      final weather = WeatherService.parse(_body())!;

      expect(weather.temperatureC, closeTo(11.4, 0.001));
      expect(weather.feelsLikeC, closeTo(9.8, 0.001));
      expect(weather.windKph, closeTo(12.0, 0.001));
      expect(weather.code, 3);
      expect(weather.isDay, isTrue);
      expect(weather.description, 'Overcast');
    });

    test('returns null rather than throwing on junk', () {
      // A captive-portal HTML page, a truncated body and an unexpected shape
      // all have to degrade to "no weather card" rather than an error.
      expect(WeatherService.parse('<html>not json</html>'), isNull);
      expect(WeatherService.parse('{"current":'), isNull);
      expect(WeatherService.parse('[]'), isNull);
      expect(WeatherService.parse('{"current":"nope"}'), isNull);
    });

    test('missing fields fall back to zero rather than crashing', () {
      final weather = WeatherService.parse('{"current":{"weather_code":0}}')!;

      expect(weather.temperatureC, 0);
      expect(weather.windKph, 0);
      expect(weather.code, 0);
    });

    test('an unknown WMO code still renders', () {
      final weather = WeatherService.parse(_body(code: 4242))!;

      expect(weather.description, 'Unknown');
      expect(weather.icon, isNotNull);
    });
  });

  group('driving warnings', () {
    test('flags the conditions that change how a round is driven', () {
      expect(
        WeatherService.parse(_body(code: 67))!.drivingWarning,
        contains('ice'),
      );
      expect(
        WeatherService.parse(_body(code: 75))!.drivingWarning,
        contains('Snow'),
      );
      expect(
        WeatherService.parse(_body(code: 45))!.drivingWarning,
        contains('Fog'),
      );
      expect(
        WeatherService.parse(_body(code: 95))!.drivingWarning,
        contains('Thunderstorm'),
      );
      expect(
        WeatherService.parse(_body(code: 65))!.drivingWarning,
        contains('Heavy rain'),
      );
    });

    test('strong wind is flagged even in otherwise clear weather', () {
      expect(
        WeatherService.parse(_body(code: 0, wind: 75))!.drivingWarning,
        contains('wind'),
      );
    });

    test('ordinary weather carries no warning', () {
      expect(WeatherService.parse(_body(code: 0))!.drivingWarning, isNull);
      expect(WeatherService.parse(_body(code: 2))!.drivingWarning, isNull);
      expect(WeatherService.parse(_body(code: 61))!.drivingWarning, isNull);
    });
  });

  test('night uses a different icon to day for clear skies', () {
    final day = WeatherService.parse(_body(code: 0, isDay: 1))!;
    final night = WeatherService.parse(_body(code: 0, isDay: 0))!;

    expect(day.icon, isNot(night.icon));
  });
}
