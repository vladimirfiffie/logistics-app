import 'package:flutter_test/flutter_test.dart';
import 'package:logistics_app/models/app_settings.dart';
import 'package:logistics_app/services/app_haptics.dart';
import 'package:logistics_app/services/app_preferences.dart';
import 'package:logistics_app/state/settings_controller.dart';
import 'package:logistics_app/ui/formatters.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('SettingsController', () {
    test('starts on sane defaults when nothing is stored', () async {
      final controller = SettingsController();
      await controller.load();

      expect(controller.settings.theme, ThemeChoice.system);
      expect(controller.settings.distanceUnit, DistanceUnit.metric);
      expect(controller.settings.hapticsEnabled, isTrue);
      expect(controller.settings.keepScreenOn, isFalse);
      expect(controller.settings.accuracy, TrackingAccuracy.balanced);
      expect(controller.settings.confirmWithSlide, isTrue);
      expect(controller.isLoaded, isTrue);
    });

    test('persists a change and reads it back on the next launch', () async {
      final first = SettingsController();
      await first.load();
      await first.setDistanceUnit(DistanceUnit.imperial);
      await first.setAccuracy(TrackingAccuracy.saver);
      await first.setTheme(ThemeChoice.dark);
      await first.setHapticsEnabled(false);

      final second = SettingsController();
      await second.load();

      expect(second.settings.distanceUnit, DistanceUnit.imperial);
      expect(second.settings.accuracy, TrackingAccuracy.saver);
      expect(second.settings.theme, ThemeChoice.dark);
      expect(second.settings.hapticsEnabled, isFalse);
    });

    test('falls back when a stored value is not recognised', () async {
      // Simulates a downgrade, or an enum renamed between builds. Startup
      // must not throw over it.
      SharedPreferences.setMockInitialValues({
        'settings.theme': 'ultraviolet',
        'settings.tracking_accuracy': 'telepathic',
      });

      final controller = SettingsController();
      await controller.load();

      expect(controller.settings.theme, ThemeChoice.system);
      expect(controller.settings.accuracy, TrackingAccuracy.balanced);
    });

    test('mirrors the haptics flag onto AppHaptics', () async {
      final controller = SettingsController();
      await controller.load();
      expect(AppHaptics.enabled, isTrue);

      await controller.setHapticsEnabled(false);
      expect(AppHaptics.enabled, isFalse);

      await controller.setHapticsEnabled(true);
      expect(AppHaptics.enabled, isTrue);
    });

    test('notifies listeners only when the value actually changes', () async {
      final controller = SettingsController();
      await controller.load();

      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.setTheme(ThemeChoice.dark);
      expect(notifications, 1);

      await controller.setTheme(ThemeChoice.dark);
      expect(notifications, 1, reason: 'same value should be a no-op');
    });

    test('reset puts everything back and survives a reload', () async {
      final controller = SettingsController();
      await controller.load();
      await controller.setTheme(ThemeChoice.dark);
      await controller.setDistanceUnit(DistanceUnit.imperial);

      await controller.resetToDefaults();
      expect(controller.settings, const AppSettings());

      final reloaded = SettingsController();
      await reloaded.load();
      expect(reloaded.settings, const AppSettings());
    });
  });

  group('onboarding flag', () {
    test('a fresh install has not seen onboarding', () async {
      expect(await const AppPreferences().onboardingComplete(), isFalse);
    });

    test('survives being set, and can be reset to replay the intro', () async {
      const preferences = AppPreferences();

      await preferences.setOnboardingComplete(true);
      expect(await preferences.onboardingComplete(), isTrue);

      // "Replay the introduction" clears it, shows the flow, then sets it
      // again — a driver who backs out halfway is not ambushed next launch.
      await preferences.setOnboardingComplete(false);
      expect(await preferences.onboardingComplete(), isFalse);

      await preferences.setOnboardingComplete(true);
      expect(await preferences.onboardingComplete(), isTrue);
    });

    test('is independent of the seen-version marker', () async {
      const preferences = AppPreferences();
      await preferences.setOnboardingComplete(true);
      await preferences.setLastSeenVersion('9.9.9');

      await preferences.setOnboardingComplete(false);

      // Replaying the intro must not also re-trigger the changelog.
      expect(await preferences.lastSeenVersion(), '9.9.9');
    });
  });

  group('new preferences', () {
    test('driver details and weather round-trip', () async {
      final first = SettingsController();
      await first.load();
      await first.setDriverName('  Vlad  ');
      await first.setVehicleLabel('LT21 KXR');
      await first.setShowWeather(false);
      await first.setArrivalRadius(300);
      await first.setAccent(AccentColor.hiVis);
      await first.setAmoled(true);

      final second = SettingsController();
      await second.load();

      // Names are trimmed on the way in, so the greeting cannot render with
      // stray whitespace.
      expect(second.settings.driverName, 'Vlad');
      expect(second.settings.vehicleLabel, 'LT21 KXR');
      expect(second.settings.showWeather, isFalse);
      expect(second.settings.arrivalRadiusMeters, 300);
      expect(second.settings.accent, AccentColor.hiVis);
      expect(second.settings.amoled, isTrue);
    });

    test('formats, temperature and the tag prompt round-trip', () async {
      final first = SettingsController();
      await first.load();
      // Defaults first: these must not silently change what existing
      // installs see.
      expect(first.settings.temperatureUnit, TemperatureUnit.matchUnits);
      expect(first.settings.dateStyle, DateStyle.dayMonth);
      expect(first.settings.clockStyle, ClockStyle.twentyFour);
      expect(first.settings.nfcClockOn, isTrue);

      await first.setTemperatureUnit(TemperatureUnit.fahrenheit);
      await first.setDateStyle(DateStyle.iso);
      await first.setClockStyle(ClockStyle.twelveHour);
      await first.setNfcClockOn(false);

      final second = SettingsController();
      await second.load();

      expect(second.settings.temperatureUnit, TemperatureUnit.fahrenheit);
      expect(second.settings.dateStyle, DateStyle.iso);
      expect(second.settings.clockStyle, ClockStyle.twelveHour);
      expect(second.settings.nfcClockOn, isFalse);
    });

    test('reset clears the newer keys too', () async {
      final controller = SettingsController();
      await controller.load();
      await controller.setDriverName('Vlad');
      await controller.setAmoled(true);
      await controller.setShowWeather(false);
      await controller.setDateStyle(DateStyle.iso);
      await controller.setTemperatureUnit(TemperatureUnit.fahrenheit);
      await controller.setNfcClockOn(false);

      await controller.resetToDefaults();

      expect(controller.settings, const AppSettings());
      expect(controller.settings.driverName, isEmpty);
      expect(controller.settings.showWeather, isTrue);
    });
  });

  group('unit formatting', () {
    test('metric keeps metres below a kilometre', () {
      expect(formatDistance(842), '842 m');
      expect(formatDistance(4237), '4.24 km');
    });

    test('imperial uses feet below a tenth of a mile', () {
      // 100 m is 0.06 mi — useless on a doorstep, so it reads in feet.
      expect(formatDistance(100, unit: DistanceUnit.imperial), '328 ft');
      expect(formatDistance(1609.344, unit: DistanceUnit.imperial), '1.00 mi');
      expect(formatDistance(32186.9, unit: DistanceUnit.imperial), '20.0 mi');
    });

    test('speed converts to mph', () {
      expect(formatSpeed(0, unit: DistanceUnit.imperial), '0.0 mph');
      // 13.4 m/s is just under 30 mph.
      expect(formatSpeed(13.4, unit: DistanceUnit.imperial), '30.0 mph');
      expect(formatSpeed(13.4), '48.2 km/h');
    });

    test('accuracy follows the unit too', () {
      expect(formatAccuracy(5), '±5 m');
      expect(formatAccuracy(5, unit: DistanceUnit.imperial), '±16 ft');
    });

    test('non-finite distances stay readable in both units', () {
      expect(formatDistance(double.nan), '—');
      expect(formatDistance(double.infinity, unit: DistanceUnit.imperial), '—');
    });
  });

  group('weather units', () {
    test('temperature converts and rounds', () {
      expect(formatTemperature(14.4), '14°C');
      expect(formatTemperature(0, fahrenheit: true), '32°F');
      expect(formatTemperature(100, fahrenheit: true), '212°F');
      expect(formatTemperature(double.nan), '—');
    });

    test('wind renders in every unit it offers', () {
      expect(formatWindSpeed(48), '48 km/h');
      // 48 km/h is just under 30 mph, 13.3 m/s and 26 knots.
      expect(formatWindSpeed(48, unit: WindUnit.mph), '30 mph');
      expect(formatWindSpeed(48, unit: WindUnit.metresPerSecond), '13.3 m/s');
      expect(formatWindSpeed(48, unit: WindUnit.knots), '26 kn');
    });

    test('unresolved "match my units" falls back rather than throwing', () {
      expect(formatWindSpeed(48, unit: WindUnit.matchUnits), '48 km/h');
      expect(
        formatPrecipitation(2, unit: PrecipitationUnit.matchUnits),
        '2.0 mm',
      );
    });

    test('precipitation keeps two decimals in inches', () {
      expect(formatPrecipitation(2.5), '2.5 mm');
      // 2.5mm is a tenth of an inch — one decimal would read "0.1 in".
      expect(
        formatPrecipitation(2.5, unit: PrecipitationUnit.inches),
        '0.10 in',
      );
    });

    test('wind and rain resolve independently of distance', () {
      const settings = AppSettings(
        distanceUnit: DistanceUnit.imperial,
        windUnit: WindUnit.knots,
        precipitationUnit: PrecipitationUnit.millimetres,
      );
      expect(settings.resolvedWindUnit, WindUnit.knots);
      expect(settings.resolvedPrecipitationUnit, PrecipitationUnit.millimetres);

      // Left on "match", they follow the distance unit as before.
      const matching = AppSettings(distanceUnit: DistanceUnit.imperial);
      expect(matching.resolvedWindUnit, WindUnit.mph);
      expect(matching.resolvedPrecipitationUnit, PrecipitationUnit.inches);
    });

    test('"match my units" resolves against the distance unit', () {
      const metric = AppSettings();
      const imperial = AppSettings(distanceUnit: DistanceUnit.imperial);

      expect(metric.usesFahrenheit, isFalse);
      expect(imperial.usesFahrenheit, isTrue);
    });

    test('an explicit choice overrides the distance unit', () {
      // The UK case: miles on the road, Celsius on the forecast.
      const settings = AppSettings(
        distanceUnit: DistanceUnit.imperial,
        temperatureUnit: TemperatureUnit.celsius,
      );
      expect(settings.usesFahrenheit, isFalse);

      const other = AppSettings(temperatureUnit: TemperatureUnit.fahrenheit);
      expect(other.usesFahrenheit, isTrue);
    });
  });

  group('date and time formats', () {
    final when = DateTime(2026, 8, 12, 17, 45);

    tearDown(() {
      DateFormatting.date = DateStyle.dayMonth;
      DateFormatting.clock = ClockStyle.twentyFour;
    });

    test('every date style renders what its label advertises', () {
      for (final style in DateStyle.values) {
        DateFormatting.date = style;
        expect(formatDate(when), style.label);
      }
    });

    test('the clock switches between 24- and 12-hour', () {
      DateFormatting.clock = ClockStyle.twentyFour;
      expect(formatTime(when), '17:45');

      DateFormatting.clock = ClockStyle.twelveHour;
      expect(formatTime(when), '5:45 PM');
    });

    test('a combined date-time uses both choices', () {
      DateFormatting.date = DateStyle.iso;
      DateFormatting.clock = ClockStyle.twelveHour;

      expect(formatDateTime(when), '2026-08-12, 5:45 PM');
    });

    test('the controller mirrors the choice onto the formatters', () async {
      final controller = SettingsController();
      await controller.load();

      await controller.setDateStyle(DateStyle.iso);
      await controller.setClockStyle(ClockStyle.twelveHour);

      // formatDate is called from plain functions with no provider in reach,
      // so the mirror is the only thing keeping them in step.
      expect(formatDate(when), '2026-08-12');
      expect(formatTime(when), '5:45 PM');
    });
  });

  group('TrackingAccuracy', () {
    test('presets get progressively coarser', () {
      expect(
        TrackingAccuracy.precise.distanceFilterMeters,
        lessThan(TrackingAccuracy.balanced.distanceFilterMeters),
      );
      expect(
        TrackingAccuracy.balanced.distanceFilterMeters,
        lessThan(TrackingAccuracy.saver.distanceFilterMeters),
      );
      expect(
        TrackingAccuracy.precise.interval,
        lessThan(TrackingAccuracy.saver.interval),
      );
    });
  });
}
