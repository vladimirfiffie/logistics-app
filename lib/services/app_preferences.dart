import 'package:shared_preferences/shared_preferences.dart';

/// Small key/value settings that do not belong in the delivery database.
class AppPreferences {
  const AppPreferences();

  static const _lastSeenVersionKey = 'last_seen_release_version';
  static const _onboardingCompleteKey = 'onboarding_complete';

  /// Whether the driver has been through the first-run flow.
  ///
  /// Kept as its own flag rather than inferred from "are there any
  /// deliveries", which would wrongly replay onboarding after the manifest is
  /// cleared from Settings.
  Future<bool> onboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardingCompleteKey) ?? false;
  }

  Future<void> setOnboardingComplete(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingCompleteKey, value);
  }

  /// The release whose "What's new" sheet the driver has already been shown.
  /// Null on a fresh install.
  Future<String?> lastSeenVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastSeenVersionKey);
  }

  Future<void> setLastSeenVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSeenVersionKey, version);
  }
}

/// Decides whether the "What's new" sheet should appear.
///
/// A fresh install returns false: someone who has never used the app does not
/// want a changelog for a version they have no history with. The onboarding
/// screen covers them instead, and the version is recorded so the *next*
/// update shows properly.
bool shouldShowWhatsNew({
  required String? lastSeenVersion,
  required String currentVersion,
  required bool isFreshInstall,
}) {
  if (isFreshInstall) return false;
  if (lastSeenVersion == null) return false;
  return lastSeenVersion != currentVersion;
}
