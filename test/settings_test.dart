import 'package:flutter_test/flutter_test.dart';
import 'package:logistics_app/models/app_settings.dart';
import 'package:logistics_app/services/app_haptics.dart';
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
