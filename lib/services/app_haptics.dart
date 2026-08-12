import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:haptic_kit/haptic_kit.dart';

/// Haptics named by what happened, not by how strong the buzz is.
///
/// Two reasons this exists rather than calling [Haptics] at each call site:
/// the vocabulary stays consistent (every success in the app feels the same),
/// and every call is swallowed on failure. A phone with no vibrator, or a
/// platform channel that is not there, must never take down a delivery flow —
/// haptics are the least important thing happening at that moment.
class AppHaptics {
  const AppHaptics._();

  /// Mirrored from `SettingsController` so the plain functions in
  /// delivery_actions.dart, which have no provider access, still respect the
  /// driver's choice.
  static bool enabled = true;

  /// Pre-warms the generators so the first buzz is not late. Optional.
  static Future<void> warmUp() => _guard(Haptics.prepare);

  /// A trip started recording.
  static Future<void> trackingStarted() =>
      _guard(() => Haptics.impact(HapticImpactStyle.medium));

  /// Tracking stopped.
  static Future<void> trackingStopped() =>
      _guard(() => Haptics.impact(HapticImpactStyle.soft));

  /// The first GPS fix landed. Deliberately light: it tells the driver
  /// tracking is genuinely live without them having to look at the screen.
  static Future<void> firstFix() =>
      _guard(() => Haptics.impact(HapticImpactStyle.light));

  /// A stop was delivered.
  static Future<void> delivered() =>
      _guard(() => Haptics.notification(HapticNotificationStyle.success));

  /// A stop could not be delivered. Warning rather than error — it is a
  /// normal outcome on a round, not a malfunction.
  static Future<void> deliveryFailed() =>
      _guard(() => Haptics.notification(HapticNotificationStyle.warning));

  /// Something actually went wrong: permission refused, GPS unavailable.
  static Future<void> error() =>
      _guard(() => Haptics.notification(HapticNotificationStyle.error));

  /// Moving between discrete choices — reason chips, sort modes.
  static Future<void> select() => _guard(Haptics.selection);

  /// A photo was captured.
  static Future<void> captured() =>
      _guard(() => Haptics.impact(HapticImpactStyle.light));

  static Future<void> _guard(Future<void> Function() action) async {
    if (!enabled) return;
    try {
      await action();
    } on VibrationException catch (error) {
      // Unsupported hardware, or a platform call that failed. Nothing the
      // driver can do about it and nothing worth interrupting them for.
      debugPrint('haptics unavailable: $error');
    } on MissingPluginException catch (_) {
      // Tests and any platform where the plugin is not registered.
    }
  }
}
