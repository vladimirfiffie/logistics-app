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
  static const _unitKey = 'settings.distance_unit';
  static const _hapticsKey = 'settings.haptics_enabled';
  static const _keepScreenOnKey = 'settings.keep_screen_on';
  static const _accuracyKey = 'settings.tracking_accuracy';
  static const _slideKey = 'settings.confirm_with_slide';

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

  /// Puts everything back to defaults.
  Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in const [
      _themeKey,
      _unitKey,
      _hapticsKey,
      _keepScreenOnKey,
      _accuracyKey,
      _slideKey,
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
