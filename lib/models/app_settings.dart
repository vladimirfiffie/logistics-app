import 'package:flutter/material.dart';

/// Distance and speed units. Drivers in the US and UK read miles; the rest of
/// the world reads kilometres, and getting it wrong makes every readout in the
/// app useless to them.
enum DistanceUnit {
  metric('Kilometres', 'km / km-h'),
  imperial('Miles', 'mi / mph');

  const DistanceUnit(this.label, this.detail);

  final String label;
  final String detail;
}

enum ThemeChoice {
  system('Follow system', Icons.brightness_auto_outlined),
  light('Light', Icons.light_mode_outlined),
  dark('Dark', Icons.dark_mode_outlined);

  const ThemeChoice(this.label, this.icon);

  final String label;
  final IconData icon;

  ThemeMode get mode => switch (this) {
    ThemeChoice.system => ThemeMode.system,
    ThemeChoice.light => ThemeMode.light,
    ThemeChoice.dark => ThemeMode.dark,
  };
}

/// How hard to push the GPS while a trip is recording.
///
/// This is the one setting with a real cost attached: [precise] gives the
/// tightest trail and the fastest speed readings, and flattens the battery on
/// a long round.
enum TrackingAccuracy {
  precise(
    'Precise',
    'Best trail and speed. Heaviest on battery.',
    distanceFilterMeters: 5,
    intervalSeconds: 3,
  ),
  balanced(
    'Balanced',
    'Accurate enough for a delivery round. Recommended.',
    distanceFilterMeters: 10,
    intervalSeconds: 5,
  ),
  saver(
    'Battery saver',
    'Coarser trail, noticeably longer battery life.',
    distanceFilterMeters: 40,
    intervalSeconds: 20,
  );

  const TrackingAccuracy(
    this.label,
    this.detail, {
    required this.distanceFilterMeters,
    required this.intervalSeconds,
  });

  final String label;
  final String detail;

  /// Metres the driver must move before a new fix is emitted.
  final int distanceFilterMeters;

  /// Android's requested interval between fixes.
  final int intervalSeconds;

  Duration get interval => Duration(seconds: intervalSeconds);
}

/// Everything the driver can change. Immutable; [copyWith] produces the next
/// value and the controller persists it.
@immutable
class AppSettings {
  const AppSettings({
    this.theme = ThemeChoice.system,
    this.distanceUnit = DistanceUnit.metric,
    this.hapticsEnabled = true,
    this.keepScreenOn = false,
    this.accuracy = TrackingAccuracy.balanced,
    this.confirmWithSlide = true,
  });

  final ThemeChoice theme;
  final DistanceUnit distanceUnit;
  final bool hapticsEnabled;

  /// Hold the screen awake while a trip records. Off by default — it is a
  /// battery decision, and most drivers pocket the phone.
  final bool keepScreenOn;

  final TrackingAccuracy accuracy;

  /// Require a slide rather than a tap to complete a delivery. On by default:
  /// a tap is easy to trigger by accident in a moving van, and closing out
  /// the wrong stop is annoying to undo.
  final bool confirmWithSlide;

  AppSettings copyWith({
    ThemeChoice? theme,
    DistanceUnit? distanceUnit,
    bool? hapticsEnabled,
    bool? keepScreenOn,
    TrackingAccuracy? accuracy,
    bool? confirmWithSlide,
  }) => AppSettings(
    theme: theme ?? this.theme,
    distanceUnit: distanceUnit ?? this.distanceUnit,
    hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
    keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    accuracy: accuracy ?? this.accuracy,
    confirmWithSlide: confirmWithSlide ?? this.confirmWithSlide,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.theme == theme &&
      other.distanceUnit == distanceUnit &&
      other.hapticsEnabled == hapticsEnabled &&
      other.keepScreenOn == keepScreenOn &&
      other.accuracy == accuracy &&
      other.confirmWithSlide == confirmWithSlide;

  @override
  int get hashCode => Object.hash(
    theme,
    distanceUnit,
    hapticsEnabled,
    keepScreenOn,
    accuracy,
    confirmWithSlide,
  );
}
