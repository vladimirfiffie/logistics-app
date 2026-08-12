import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../services/app_haptics.dart';
import '../ui/formatters.dart';

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
  static const _temperatureKey = 'settings.temperature_unit';
  static const _dateStyleKey = 'settings.date_style';
  static const _clockStyleKey = 'settings.clock_style';
  static const _nfcClockOnKey = 'settings.nfc_clock_on';
  static const _windKey = 'settings.wind_unit';
  static const _precipitationKey = 'settings.precipitation_unit';
  static const _defaultSortKey = 'settings.default_sort';
  static const _signatureKey = 'settings.signature_mode';
  static const _autoTrackKey = 'settings.auto_track_next_stop';
  static const _onShiftNotificationKey = 'settings.on_shift_notification';
  static const _breakReminderKey = 'settings.break_reminder_minutes';

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
      temperatureUnit: _readEnum(
        prefs.getString(_temperatureKey),
        TemperatureUnit.values,
        TemperatureUnit.matchUnits,
      ),
      dateStyle: _readEnum(
        prefs.getString(_dateStyleKey),
        DateStyle.values,
        DateStyle.dayMonth,
      ),
      clockStyle: _readEnum(
        prefs.getString(_clockStyleKey),
        ClockStyle.values,
        ClockStyle.twentyFour,
      ),
      nfcClockOn: prefs.getBool(_nfcClockOnKey) ?? true,
      windUnit: _readEnum(
        prefs.getString(_windKey),
        WindUnit.values,
        WindUnit.matchUnits,
      ),
      precipitationUnit: _readEnum(
        prefs.getString(_precipitationKey),
        PrecipitationUnit.values,
        PrecipitationUnit.matchUnits,
      ),
      defaultSort: _readEnum(
        prefs.getString(_defaultSortKey),
        StopSort.values,
        StopSort.time,
      ),
      signatureMode: _readEnum(
        prefs.getString(_signatureKey),
        SignatureMode.values,
        SignatureMode.optional,
      ),
      autoTrackNextStop: prefs.getBool(_autoTrackKey) ?? false,
      onShiftNotification: prefs.getBool(_onShiftNotificationKey) ?? true,
      breakReminderMinutes: prefs.getInt(_breakReminderKey) ?? 0,
    );
    _isLoaded = true;
    _syncMirrors();
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

  Future<void> setTemperatureUnit(TemperatureUnit value) async {
    await _update(_settings.copyWith(temperatureUnit: value), (prefs) {
      return prefs.setString(_temperatureKey, value.name);
    });
  }

  Future<void> setDateStyle(DateStyle value) async {
    await _update(_settings.copyWith(dateStyle: value), (prefs) {
      return prefs.setString(_dateStyleKey, value.name);
    });
  }

  Future<void> setClockStyle(ClockStyle value) async {
    await _update(_settings.copyWith(clockStyle: value), (prefs) {
      return prefs.setString(_clockStyleKey, value.name);
    });
  }

  Future<void> setNfcClockOn(bool value) async {
    await _update(_settings.copyWith(nfcClockOn: value), (prefs) {
      return prefs.setBool(_nfcClockOnKey, value);
    });
  }

  Future<void> setWindUnit(WindUnit value) async {
    await _update(_settings.copyWith(windUnit: value), (prefs) {
      return prefs.setString(_windKey, value.name);
    });
  }

  Future<void> setPrecipitationUnit(PrecipitationUnit value) async {
    await _update(_settings.copyWith(precipitationUnit: value), (prefs) {
      return prefs.setString(_precipitationKey, value.name);
    });
  }

  Future<void> setDefaultSort(StopSort value) async {
    await _update(_settings.copyWith(defaultSort: value), (prefs) {
      return prefs.setString(_defaultSortKey, value.name);
    });
  }

  Future<void> setSignatureMode(SignatureMode value) async {
    await _update(_settings.copyWith(signatureMode: value), (prefs) {
      return prefs.setString(_signatureKey, value.name);
    });
  }

  Future<void> setAutoTrackNextStop(bool value) async {
    await _update(_settings.copyWith(autoTrackNextStop: value), (prefs) {
      return prefs.setBool(_autoTrackKey, value);
    });
  }

  Future<void> setOnShiftNotification(bool value) async {
    await _update(_settings.copyWith(onShiftNotification: value), (prefs) {
      return prefs.setBool(_onShiftNotificationKey, value);
    });
  }

  Future<void> setBreakReminderMinutes(int value) async {
    await _update(_settings.copyWith(breakReminderMinutes: value), (prefs) {
      return prefs.setInt(_breakReminderKey, value);
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
      _temperatureKey,
      _dateStyleKey,
      _clockStyleKey,
      _nfcClockOnKey,
      _windKey,
      _precipitationKey,
      _defaultSortKey,
      _signatureKey,
      _autoTrackKey,
      _onShiftNotificationKey,
      _breakReminderKey,
    ]) {
      await prefs.remove(key);
    }
    _settings = const AppSettings();
    _syncMirrors();
    notifyListeners();
  }

  Future<void> _update(
    AppSettings next,
    Future<void> Function(SharedPreferences) write,
  ) async {
    if (next == _settings) return;
    _settings = next;
    _syncMirrors();
    notifyListeners();
    await write(await SharedPreferences.getInstance());
  }

  /// Haptics and the date formatters are reached from places that have no easy
  /// access to a provider — plain functions in delivery_actions.dart, and
  /// `formatDate` called from every list row — so those two settings are
  /// mirrored onto them rather than threaded through every call.
  void _syncMirrors() {
    AppHaptics.enabled = _settings.hapticsEnabled;
    DateFormatting.date = _settings.dateStyle;
    DateFormatting.clock = _settings.clockStyle;
  }

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
