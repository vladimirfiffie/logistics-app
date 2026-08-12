import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/app_settings.dart';

/// Why the app can or cannot read the driver's position right now.
enum LocationReadiness {
  /// Good to go — at least while-in-use permission is granted.
  ready,

  /// The device's location toggle is off. Only the user can fix this.
  serviceDisabled,

  /// Denied this time; asking again is allowed.
  denied,

  /// Denied permanently (or blocked by policy). Requires a trip to Settings.
  deniedForever;

  String get message => switch (this) {
    LocationReadiness.ready => 'Location is available.',
    LocationReadiness.serviceDisabled =>
      'Location services are turned off on this device. Turn them on to track '
          'deliveries.',
    LocationReadiness.denied =>
      'Location permission is needed to record delivery tracking.',
    LocationReadiness.deniedForever =>
      'Location permission was permanently denied. Enable it in system '
          'settings to track deliveries.',
  };

  /// True when there is a settings screen that would actually resolve this.
  /// A plain [denied] is fixed by asking again, not by sending the driver off
  /// to Settings.
  bool get isFixableInSettings =>
      this == LocationReadiness.serviceDisabled ||
      this == LocationReadiness.deniedForever;
}

/// Thin wrapper over geolocator so the rest of the app never touches the
/// plugin directly — which also makes the controllers testable with a fake.
class LocationService {
  const LocationService();

  /// Asks for permission if needed and reports whether tracking can proceed.
  Future<LocationReadiness> ensureReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationReadiness.serviceDisabled;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return _readinessFor(permission);
  }

  /// Reports the current state **without prompting**.
  ///
  /// Used by the settings screen, where someone who came to change the theme
  /// should not be ambushed by a permission dialog.
  Future<LocationReadiness> currentReadiness() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationReadiness.serviceDisabled;
    }
    return _readinessFor(await Geolocator.checkPermission());
  }

  LocationReadiness _readinessFor(LocationPermission permission) =>
      switch (permission) {
        LocationPermission.always ||
        LocationPermission.whileInUse => LocationReadiness.ready,
        LocationPermission.deniedForever => LocationReadiness.deniedForever,
        LocationPermission.denied ||
        LocationPermission.unableToDetermine => LocationReadiness.denied,
      };

  /// Asks for the "allow all the time" upgrade, which Android requires as a
  /// second, separate prompt after while-in-use is already granted.
  ///
  /// Tracking still works without it — the foreground service keeps fixes
  /// coming while the app is backgrounded — but the OS may throttle or stop
  /// updates once the screen is locked for a long stretch.
  Future<bool> requestBackgroundPermission() async {
    final status = await Permission.locationAlways.request();
    return status.isGranted;
  }

  Future<bool> hasBackgroundPermission() => Permission.locationAlways.isGranted;

  /// Opens the OS settings page so the driver can undo a permanent denial.
  Future<bool> openSettings() => Geolocator.openAppSettings();

  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  /// A single fix, for centring the map or stamping a completion.
  Future<Position> currentPosition() => Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 20),
    ),
  );

  /// The last fix the OS cached — instant, possibly stale, may be null.
  Future<Position?> lastKnownPosition() => Geolocator.getLastKnownPosition();

  /// Continuous fixes for an active trip.
  ///
  /// On Android this runs as a foreground service with a persistent
  /// notification, which is what keeps location flowing when the driver
  /// switches to their nav app or pockets the phone.
  Stream<Position> trackPosition({
    required String notificationText,
    TrackingAccuracy accuracy = TrackingAccuracy.balanced,
  }) {
    return Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: switch (accuracy) {
          TrackingAccuracy.precise => LocationAccuracy.bestForNavigation,
          TrackingAccuracy.balanced => LocationAccuracy.high,
          TrackingAccuracy.saver => LocationAccuracy.medium,
        },
        distanceFilter: accuracy.distanceFilterMeters,
        intervalDuration: accuracy.interval,
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: 'Delivery tracking active',
          notificationText: notificationText,
          notificationIcon: const AndroidResource(
            name: 'ic_launcher',
            defType: 'mipmap',
          ),
          enableWakeLock: true,
          setOngoing: true,
        ),
      ),
    );
  }

  /// Great-circle distance in metres.
  double distanceBetween(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) => Geolocator.distanceBetween(
    startLatitude,
    startLongitude,
    endLatitude,
    endLongitude,
  );
}
