import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:libre_location/libre_location.dart' as libre;

import '../models/app_settings.dart';
import '../models/fix.dart';
import 'bearing.dart';

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

/// What the phone reckons the driver is doing.
///
/// Reported by the platform's activity recognition, not inferred from speed —
/// which is the difference between "stopped at a light" and "parked at the
/// door".
enum MotionState {
  driving,
  onFoot,
  still,
  unknown;

  bool get isDriving => this == MotionState.driving;
}

/// The app's only door to the phone's location hardware.
///
/// Backed by `libre_location`, which drives Android's own `LocationManager`
/// rather than Google's fused provider. Two things that buys a delivery app:
/// it keeps working on a phone with no Play Services — a degoogled handset, or
/// a van phone with a stripped ROM — and its background tracking is built for
/// this job rather than being a side effect of holding a stream subscription
/// open.
///
/// Readings come back as [Fix], the app's own type, so nothing above this
/// class knows which plugin produced them. Swapping back is this one file.
class LocationService {
  const LocationService();

  /// Asks for permission if needed and reports whether tracking can proceed.
  Future<LocationReadiness> ensureReady() async {
    if (!await libre.LibreLocation.isLocationServiceEnabled()) {
      return LocationReadiness.serviceDisabled;
    }

    var permission = await libre.LibreLocation.checkPermission();
    if (permission == libre.LocationPermission.denied) {
      permission = await libre.LibreLocation.requestPermission();
    }

    return _readinessFor(permission);
  }

  /// Reports the current state **without prompting**.
  ///
  /// Used by the settings screen, where someone who came to change the theme
  /// should not be ambushed by a permission dialog.
  Future<LocationReadiness> currentReadiness() async {
    if (!await libre.LibreLocation.isLocationServiceEnabled()) {
      return LocationReadiness.serviceDisabled;
    }
    return _readinessFor(await libre.LibreLocation.checkPermission());
  }

  LocationReadiness _readinessFor(libre.LocationPermission permission) =>
      switch (permission) {
        libre.LocationPermission.always ||
        libre.LocationPermission.whileInUse => LocationReadiness.ready,
        libre.LocationPermission.deniedForever =>
          LocationReadiness.deniedForever,
        libre.LocationPermission.denied => LocationReadiness.denied,
      };

  /// Asks for the "allow all the time" upgrade, which Android requires as a
  /// second, separate prompt after while-in-use is already granted.
  ///
  /// Tracking still works without it — the foreground service keeps fixes
  /// coming while the app is backgrounded — but the OS may throttle or stop
  /// updates once the screen is locked for a long stretch.
  Future<bool> requestBackgroundPermission() async {
    final permission = await libre.LibreLocation.requestAlwaysPermission();
    return permission == libre.LocationPermission.always;
  }

  Future<bool> hasBackgroundPermission() async =>
      await libre.LibreLocation.checkPermission() ==
      libre.LocationPermission.always;

  /// Opens the OS settings page so the driver can undo a permanent denial.
  Future<bool> openSettings() => libre.LibreLocation.openAppSettings();

  Future<bool> openLocationSettings() =>
      libre.LibreLocation.openLocationSettings();

  /// A single fix, for centring the map or stamping a completion.
  ///
  /// Three samples averaged: a one-shot reading taken cold between tall
  /// buildings can be a hundred metres out, and this is the fix that decides
  /// which stop looks nearest.
  Future<Fix> currentPosition() async {
    final position = await libre.LibreLocation.getCurrentPosition(
      accuracy: libre.Accuracy.high,
      samples: 3,
      timeout: 20,
    );
    return _toFix(position);
  }

  /// A recent fix if the phone already has one — instant, possibly stale.
  ///
  /// `maximumAge` is what makes this cheap: it hands back a reading the device
  /// already has rather than waking the GPS, which is the entire point of the
  /// call. Never throws — every caller treats a missing fix as "no distance
  /// column today" rather than as an error.
  Future<Fix?> lastKnownPosition() async {
    try {
      final position = await libre.LibreLocation.getCurrentPosition(
        accuracy: libre.Accuracy.balanced,
        samples: 1,
        timeout: 5,
        // Five minutes. Older than that and it is worth waiting for a real one.
        maximumAge: 300,
        persist: false,
      );
      return _toFix(position);
    } catch (error) {
      debugPrint('location: no cached fix — $error');
      return null;
    }
  }

  /// Continuous fixes for an active trip.
  ///
  /// Tracking starts when something listens and stops when the listener
  /// cancels, which keeps the contract the tracking controller was already
  /// written against — stopping a trip is a subscription being cancelled. The
  /// plugin's own start and stop are explicit calls, so they are tied to the
  /// stream here rather than left for every caller to remember.
  ///
  /// On Android this runs as a foreground service with a persistent
  /// notification, which is what keeps location flowing when the driver
  /// switches to their nav app or pockets the phone.
  Stream<Fix> trackPosition({
    required String notificationText,
    TrackingAccuracy accuracy = TrackingAccuracy.balanced,
  }) {
    StreamSubscription<libre.Position>? subscription;
    late final StreamController<Fix> controller;

    controller = StreamController<Fix>(
      onListen: () async {
        try {
          await libre.LibreLocation.start(
            preset: switch (accuracy) {
              TrackingAccuracy.precise => libre.TrackingPreset.high,
              TrackingAccuracy.balanced => libre.TrackingPreset.balanced,
              TrackingAccuracy.saver => libre.TrackingPreset.low,
            },
            config: libre.LocationConfig(
              notification: libre.NotificationConfig(
                title: 'Delivery tracking active',
                text: notificationText,
              ),
              // A trip outlives the UI being killed — the controller restores
              // it on the next launch — so the service must not stop when the
              // app is swiped away.
              stopOnTerminate: false,
              // Recording that resumes by itself after a reboot is not
              // something any driver asked for, and the app promises tracking
              // runs only while a trip does.
              startOnBoot: false,
              // Nothing registers a headless dispatcher, so there would be
              // nobody listening on the other side of it.
              enableHeadless: false,
            ),
          );
        } catch (error) {
          controller.addError(error);
          return;
        }

        subscription = libre.LibreLocation.onLocation.listen(
          (position) => controller.add(_toFix(position)),
          onError: controller.addError,
        );
      },
      onCancel: () async {
        await subscription?.cancel();
        subscription = null;
        try {
          await libre.LibreLocation.stop();
        } catch (error) {
          // A failed stop must not hang the caller: the trip is over either
          // way, and the service dies with the app at worst.
          debugPrint('location: could not stop tracking — $error');
        }
      },
    );

    return controller.stream;
  }

  /// Asks the OS to watch a circle around a stop and say when the driver
  /// enters it.
  ///
  /// The app already measures the distance to the stop on every fix, and that
  /// is fine while it is the app doing the measuring. The point of handing
  /// the circle to the system is what happens when it is not: Android
  /// throttles a backgrounded app's fixes, and the arrival alert exists
  /// precisely for the driver who is in their nav app with this one out of
  /// sight. A watched region is checked by the platform regardless.
  ///
  /// Best-effort. A refusal — no background permission, too many regions
  /// registered — leaves the in-app distance check as it was.
  Future<void> watchArrival({
    required String id,
    required double latitude,
    required double longitude,
    required double radiusMeters,
  }) async {
    try {
      await libre.LibreLocation.addGeofence(
        libre.Geofence(
          id: id,
          latitude: latitude,
          longitude: longitude,
          radiusMeters: radiusMeters,
          // Arriving is the only transition worth waking anything up for.
          triggers: const {libre.GeofenceTransition.enter},
        ),
      );
    } catch (error) {
      debugPrint('location: could not watch $id — $error');
    }
  }

  Future<void> stopWatchingArrival(String id) async {
    try {
      await libre.LibreLocation.removeGeofence(id);
    } catch (error) {
      debugPrint('location: could not stop watching $id — $error');
    }
  }

  /// The ids of watched stops as the driver arrives at them.
  Stream<String> get arrivals => libre.LibreLocation.geofenceStream
      .where((event) => event.transition == libre.GeofenceTransition.enter)
      .map((event) => event.geofence.id);

  /// Whether the device's location providers are switched on, as they change.
  ///
  /// A driver who turns GPS off mid-round — or whose phone does it for them
  /// on a battery saver — currently just stops producing fixes, and a trail
  /// that quietly flatlines looks exactly like a trail through a tunnel. The
  /// platform says so directly, so the app can too.
  Stream<bool> get locationEnabled =>
      libre.LibreLocation.onProviderChange.map((event) => event.enabled);

  /// What the phone thinks the driver is doing, as it changes.
  ///
  /// Comes from the platform's own activity recognition rather than being
  /// guessed at from speed, so it survives a phone sitting in a cradle at a
  /// red light.
  Stream<MotionState> get motion => libre.LibreLocation.onActivityChange.map(
    (event) => switch (event.activity) {
      'in_vehicle' => MotionState.driving,
      'on_bicycle' || 'walking' || 'running' => MotionState.onFoot,
      'still' => MotionState.still,
      _ => MotionState.unknown,
    },
  );

  /// Whether Android is battery-managing this app.
  ///
  /// The single most common reason a recorded trail has holes in it: an OEM
  /// battery manager decides a backgrounded app has had enough and stops its
  /// service. Worth telling the driver about before it costs them a round,
  /// rather than after.
  Future<bool> isBatteryOptimised() async {
    try {
      // The plugin reports whether the app is *exempt*, which is the answer
      // to the opposite question.
      return !await libre.LibreLocation.checkBatteryOptimization();
    } catch (error) {
      debugPrint('location: could not read battery optimisation — $error');
      return false;
    }
  }

  /// Sends the driver to the system prompt that exempts this app.
  Future<bool> requestBatteryExemption() async {
    try {
      return await libre.LibreLocation.requestBatteryOptimizationExemption();
    } catch (error) {
      debugPrint('location: could not ask for exemption — $error');
      return false;
    }
  }

  /// Great-circle distance in metres.
  double distanceBetween(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) => distanceBetweenMeters(
    startLatitude,
    startLongitude,
    endLatitude,
    endLongitude,
  );

  /// The plugin's reading, in the app's terms.
  static Fix _toFix(libre.Position position) => Fix(
    latitude: position.latitude,
    longitude: position.longitude,
    accuracy: position.accuracy,
    speed: position.speed,
    heading: position.heading,
    altitude: position.altitude,
    timestamp: position.timestamp,
  );
}
