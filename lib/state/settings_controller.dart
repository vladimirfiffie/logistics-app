import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../services/app_haptics.dart';

/// Sugar for the settings a widget needs mid-build, so call sites read
/// `formatDistance(x, unit: context.distanceUnit)` rather than three lines of
/// provider plumbing each time.
extension SettingsContext on BuildContext {
  AppSettings get appSettings => watch<SettingsController>().settings;

  DistanceUnit get distanceUnit => appSettings.distanceUnit;
}

/// Loads, exposes and persists [AppSettings].
///
/// Every setter writes to disk and notifies immediately — settings screens
/// should feel instant, and there is nothing here worth batching.
class SettingsController extends ChangeNotifier {
  SettingsController();

  static const _themeKey = 'settings.theme';
  static const _accentKey = 'settings.accent';
  static const _amoledKey = 'settings.amoled';
  static const _unitKey = 'settings.distance_unit';
  static const _hapticsKey = 'settings.haptics_enabled';
  static const _keepScreenOnKey = 'settings.keep_screen_on';
  static const _accuracyKey = 'settings.tracking_accuracy';
  static const _slideKey = 'settings.confirm_with_slide';
  static const _driverNameKey = 'settings.driver_name';
  static const _vehicleKey = 'settings.vehicle_label';
  static const _followKey = 'settings.follow_mode';
  static const _celebrateKey = 'settings.celebrate_deliveries';
  static const _requirePhotoKey = 'settings.require_proof_photo';
  static const _arrivalAlertsKey = 'settings.arrival_alerts';
  static const _arrivalRadiusKey = 'settings.arrival_radius_meters';
  static const _weatherKey = 'settings.show_weather';

  AppSettings _settings = const AppSettings();
  bool _isLoaded = false;

  AppSettings get settings => _settings;
  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _settings = AppSettings(
      theme: _readEnum(
        prefs.getString(_themeKey),
        ThemeChoice.values,
        ThemeChoice.system,
      ),
      accent: _readEnum(
        prefs.getString(_accentKey),
        AccentColor.values,
        AccentColor.fleet,
      ),
      amoled: prefs.getBool(_amoledKey) ?? false,
      distanceUnit: _readEnum(
        prefs.getString(_unitKey),
        DistanceUnit.values,
        DistanceUnit.metric,
      ),
      hapticsEnabled: prefs.getBool(_hapticsKey) ?? true,
      keepScreenOn: prefs.getBool(_keepScreenOnKey) ?? false,
      accuracy: _readEnum(
        prefs.getString(_accuracyKey),
        TrackingAccuracy.values,
        TrackingAccuracy.balanced,
      ),
      confirmWithSlide: prefs.getBool(_slideKey) ?? true,
      driverName: prefs.getString(_driverNameKey) ?? '',
      vehicleLabel: prefs.getString(_vehicleKey) ?? '',
      followMode: _readEnum(
        prefs.getString(_followKey),
        MapFollowMode.values,
        MapFollowMode.follow,
      ),
      celebrateDeliveries: prefs.getBool(_celebrateKey) ?? true,
      requireProofPhoto: prefs.getBool(_requirePhotoKey) ?? false,
      arrivalAlerts: prefs.getBool(_arrivalAlertsKey) ?? true,
      arrivalRadiusMeters: prefs.getInt(_arrivalRadiusKey) ?? 150,
      showWeather: prefs.getBool(_weatherKey) ?? true,
    );
    _isLoaded = true;
    _syncHaptics();
    notifyListeners();
  }

  Future<void> setTheme(ThemeChoice value) async {
    await _update(_settings.copyWith(theme: value), (prefs) {
      return prefs.setString(_themeKey, value.name);
    });
  }

  Future<void> setAccent(AccentColor value) async {
    await _update(_settings.copyWith(accent: value), (prefs) {
      return prefs.setString(_accentKey, value.name);
    });
  }

  Future<void> setAmoled(bool value) async {
    await _update(_settings.copyWith(amoled: value), (prefs) {
      return prefs.setBool(_amoledKey, value);
    });
  }

  Future<void> setDistanceUnit(DistanceUnit value) async {
    await _update(_settings.copyWith(distanceUnit: value), (prefs) {
      return prefs.setString(_unitKey, value.name);
    });
  }

  Future<void> setHapticsEnabled(bool value) async {
    await _update(_settings.copyWith(hapticsEnabled: value), (prefs) {
      return prefs.setBool(_hapticsKey, value);
    });
  }

  Future<void> setKeepScreenOn(bool value) async {
    await _update(_settings.copyWith(keepScreenOn: value), (prefs) {
      return prefs.setBool(_keepScreenOnKey, value);
    });
  }

  Future<void> setAccuracy(TrackingAccuracy value) async {
    await _update(_settings.copyWith(accuracy: value), (prefs) {
      return prefs.setString(_accuracyKey, value.name);
    });
  }

  Future<void> setConfirmWithSlide(bool value) async {
    await _update(_settings.copyWith(confirmWithSlide: value), (prefs) {
      return prefs.setBool(_slideKey, value);
    });
  }

  Future<void> setDriverName(String value) async {
    final trimmed = value.trim();
    await _update(_settings.copyWith(driverName: trimmed), (prefs) {
      return prefs.setString(_driverNameKey, trimmed);
    });
  }

  Future<void> setVehicleLabel(String value) async {
    final trimmed = value.trim();
    await _update(_settings.copyWith(vehicleLabel: trimmed), (prefs) {
      return prefs.setString(_vehicleKey, trimmed);
    });
  }

  Future<void> setFollowMode(MapFollowMode value) async {
    await _update(_settings.copyWith(followMode: value), (prefs) {
      return prefs.setString(_followKey, value.name);
    });
  }

  Future<void> setCelebrateDeliveries(bool value) async {
    await _update(_settings.copyWith(celebrateDeliveries: value), (prefs) {
      return prefs.setBool(_celebrateKey, value);
    });
  }

  Future<void> setRequireProofPhoto(bool value) async {
    await _update(_settings.copyWith(requireProofPhoto: value), (prefs) {
      return prefs.setBool(_requirePhotoKey, value);
    });
  }

  Future<void> setArrivalAlerts(bool value) async {
    await _update(_settings.copyWith(arrivalAlerts: value), (prefs) {
      return prefs.setBool(_arrivalAlertsKey, value);
    });
  }

  Future<void> setArrivalRadius(int meters) async {
    await _update(_settings.copyWith(arrivalRadiusMeters: meters), (prefs) {
      return prefs.setInt(_arrivalRadiusKey, meters);
    });
  }

  Future<void> setShowWeather(bool value) async {
    await _update(_settings.copyWith(showWeather: value), (prefs) {
      return prefs.setBool(_weatherKey, value);
    });
  }

  /// Puts everything back to defaults.
  Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in const [
      _themeKey,
      _accentKey,
      _amoledKey,
      _unitKey,
      _hapticsKey,
      _keepScreenOnKey,
      _accuracyKey,
      _slideKey,
      _driverNameKey,
      _vehicleKey,
      _followKey,
      _celebrateKey,
      _requirePhotoKey,
      _arrivalAlertsKey,
      _arrivalRadiusKey,
      _weatherKey,
    ]) {
      await prefs.remove(key);
    }
    _settings = const AppSettings();
    _syncHaptics();
    notifyListeners();
  }

  Future<void> _update(
    AppSettings next,
    Future<void> Function(SharedPreferences) write,
  ) async {
    if (next == _settings) return;
    _settings = next;
    _syncHaptics();
    notifyListeners();
    await write(await SharedPreferences.getInstance());
  }

  /// AppHaptics is called from places that have no easy access to a provider
  /// (plain functions in delivery_actions.dart), so the flag is mirrored onto
  /// it rather than threaded through every call.
  void _syncHaptics() => AppHaptics.enabled = _settings.hapticsEnabled;

  static T _readEnum<T extends Enum>(String? name, List<T> values, T fallback) {
    if (name == null) return fallback;
    for (final value in values) {
      if (value.name == name) return value;
    }
    // A value written by a newer build, or a renamed enum. Fall back rather
    // than throwing on startup.
    return fallback;
  }
}
