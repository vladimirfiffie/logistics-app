import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../data/delivery_repository.dart';
import '../models/app_settings.dart';
import '../models/delivery.dart';
import '../models/trip.dart';
import '../models/trip_point.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';

/// Drives the live tracking session: permissions, the position stream, the
/// breadcrumb trail, and the running odometer.
class TrackingController extends ChangeNotifier {
  TrackingController({
    required DeliveryRepository repository,
    required LocationService locationService,
    required AppSettings Function() settings,
    NotificationService? notifications,
    this.onManifestChanged,
  }) : _repository = repository,
       _location = locationService,
       _settings = settings,
       _notifications = notifications ?? NotificationService();

  final DeliveryRepository _repository;
  final LocationService _location;

  /// Read lazily rather than captured, so a trip started after the driver
  /// changes a setting uses the new value without rewiring providers.
  final AppSettings Function() _settings;

  final NotificationService _notifications;

  /// Arrival fires once per trip, not once per fix inside the radius.
  bool _announcedArrival = false;

  /// Called when a start/stop changes a delivery's status, so the manifest
  /// list can re-read it.
  final Future<void> Function()? onManifestChanged;

  /// Fixes worse than this are recorded but excluded from the odometer — a
  /// 200m-accuracy reading between two good fixes would otherwise add a
  /// phantom kilometre to the trip.
  static const _maxOdometerAccuracyMeters = 50.0;

  Trip? _trip;
  Delivery? _delivery;

  /// Appended to in place. Copying the whole trail on every fix — which is
  /// what `_points = [..._points, point]` did — is quadratic: a ten-hour round
  /// at a fix every five seconds copied about 26 million elements over the
  /// day, and got slower the longer the driver worked.
  List<TripPoint> _points = [];
  double _distanceMeters = 0;
  Position? _lastPosition;
  StreamSubscription<Position>? _subscription;
  LocationReadiness _readiness = LocationReadiness.ready;
  Object? _error;
  bool _isBusy = false;

  Trip? get trip => _trip;
  Delivery? get delivery => _delivery;

  /// Read-only: the trail is appended to in place, so handing out the live
  /// list would let a caller corrupt the odometer's source data.
  List<TripPoint> get points => UnmodifiableListView(_points);
  double get distanceMeters => _distanceMeters;
  Position? get lastPosition => _lastPosition;
  LocationReadiness get readiness => _readiness;
  Object? get error => _error;
  bool get isBusy => _isBusy;

  bool get isTracking => _trip != null && _trip!.isActive;

  Duration get elapsed => _trip?.duration ?? Duration.zero;

  /// Average speed over the whole trip, in m/s. Zero until the clock and the
  /// odometer both have something in them.
  double get averageSpeed {
    final seconds = elapsed.inSeconds;
    if (seconds <= 0 || _distanceMeters <= 0) return 0;
    return _distanceMeters / seconds;
  }

  /// Straight-line metres from the latest fix to the stop's address.
  double? get metersToDestination {
    final position = _lastPosition;
    final destination = _delivery;
    if (position == null || destination == null) return null;
    return _location.distanceBetween(
      position.latitude,
      position.longitude,
      destination.latitude,
      destination.longitude,
    );
  }

  /// Roughly how long the rest of the way will take.
  ///
  /// Straight-line distance over the pace actually being driven, which is a
  /// blunt instrument — it knows nothing about the roads, and the last stop of
  /// a round through a housing estate will beat it badly. It is honest about
  /// the order of magnitude, which is what "do I stop for a coffee first?"
  /// actually needs.
  ///
  /// The trip average is used rather than the instantaneous speed: a driver
  /// sitting at a red light is not stationary for the rest of the day, and an
  /// ETA that jumps to infinity every junction is worse than none. Null until
  /// there is enough of a trip to average, or when the pace is implausible.
  Duration? get etaToDestination {
    final remaining = metersToDestination;
    if (remaining == null) return null;

    final live = _lastPosition?.speed ?? 0;
    // Weighted towards the average, nudged by current speed so pulling onto a
    // fast road shortens it a little rather than not at all.
    final pace = averageSpeed <= 0
        ? live
        : (averageSpeed * 0.7) + (live.clamp(0, 40) * 0.3);
    if (pace < 0.5) return null;

    final seconds = remaining / pace;
    if (!seconds.isFinite || seconds > 6 * 60 * 60) return null;
    return Duration(seconds: seconds.round());
  }

  /// Whether the driver is inside the arrival radius of the stop. Drives the
  /// live view's arrival state, and is deliberately the same threshold the
  /// arrival notification uses — two different definitions of "here" on one
  /// screen would be indefensible.
  bool get hasArrived {
    final remaining = metersToDestination;
    if (remaining == null) return false;
    return remaining <= _settings().arrivalRadiusMeters;
  }

  /// Picks up a session that survived an app restart. Android can kill the UI
  /// while the foreground service keeps running, so on launch we check whether
  /// a trip was left open and resume streaming into it.
  Future<void> restore() async {
    final open = await _repository.activeTrip();
    if (open == null) return;

    _trip = open;
    _delivery = await _repository.fetchDelivery(open.deliveryId);
    _points = await _repository.pointsForTrip(open.id);
    _distanceMeters = open.distanceMeters > 0
        ? open.distanceMeters
        : _measureTrail(_points);
    _lastPosition = null;

    // A resumed trip may already have announced arrival before the UI was
    // killed. The flag lives in memory, so it comes back false and the driver
    // gets told a second time about a stop they reached ten minutes ago —
    // unless the trail says they are already inside the radius.
    _announcedArrival = _trailReachedDestination();
    notifyListeners();

    final readiness = await _location.ensureReady();
    _readiness = readiness;
    if (readiness == LocationReadiness.ready) {
      await _listen();
    }
    notifyListeners();
  }

  /// Begins tracking [delivery]. Returns false if location is unavailable, in
  /// which case [readiness] explains why.
  Future<bool> start(Delivery delivery) async {
    if (isTracking) return false;
    _isBusy = true;
    _error = null;
    notifyListeners();

    try {
      final readiness = await _location.ensureReady();
      _readiness = readiness;
      if (readiness != LocationReadiness.ready) return false;

      _trip = await _repository.startTrip(delivery.id);
      _delivery = delivery;
      _points = [];
      _distanceMeters = 0;
      _lastPosition = null;
      _announcedArrival = false;
      await _notifications.cancelArrival();
      await _listen();
      await onManifestChanged?.call();
      return true;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  /// Closes the session and returns the finished trip.
  Future<Trip?> stop() async {
    final active = _trip;
    if (active == null) return null;

    _isBusy = true;
    notifyListeners();
    try {
      // Cancelling the subscription is what tears down the Android foreground
      // service and its persistent "sharing your location" notification, so it
      // happens first and is awaited — a stop that leaves the service running
      // is worse than a stop that takes an extra moment.
      await _subscription?.cancel();
      _subscription = null;
      _announcedArrival = false;

      // The arrival alert is not auto-dismissed, so without this it sits in
      // the shade after the trip it belongs to has finished.
      await _notifications.cancelArrival();

      final finished = await _repository.endTrip(
        active.id,
        distanceMeters: _distanceMeters,
      );
      _trip = finished;
      await onManifestChanged?.call();
      return finished;
    } catch (error) {
      _error = error;
      return null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  /// Drops the finished trip from view once the driver has closed out the stop.
  void clear() {
    if (isTracking) return;
    _trip = null;
    _delivery = null;
    _points = [];
    _distanceMeters = 0;
    _lastPosition = null;
    notifyListeners();
  }

  Future<bool> requestBackgroundPermission() =>
      _location.requestBackgroundPermission();

  /// Opens whichever settings screen would fix the current [readiness].
  Future<void> openRelevantSettings() async {
    if (_readiness == LocationReadiness.serviceDisabled) {
      await _location.openLocationSettings();
    } else {
      await _location.openSettings();
    }
  }

  /// Whether any breadcrumb already recorded came inside the arrival radius.
  /// Used on [restore] to decide whether the alert has effectively been given.
  bool _trailReachedDestination() {
    final stop = _delivery;
    if (stop == null || _points.isEmpty) return false;
    final radius = _settings().arrivalRadiusMeters;
    for (final point in _points) {
      final distance = _location.distanceBetween(
        point.latitude,
        point.longitude,
        stop.latitude,
        stop.longitude,
      );
      if (distance <= radius) return true;
    }
    return false;
  }

  /// Awaits the cancel before attaching the next stream: on Android each
  /// position stream owns a foreground service, and starting a second one
  /// before the first has released leaves an orphaned service behind.
  Future<void> _listen() async {
    await _subscription?.cancel();
    final label = _delivery?.customerName ?? 'Delivery in progress';
    _subscription = _location
        .trackPosition(
          notificationText: 'On the way to $label',
          accuracy: _settings().accuracy,
        )
        .listen(
          _onPosition,
          onError: (Object error) {
            _error = error;
            notifyListeners();
          },
        );
  }

  Future<void> _onPosition(Position position) async {
    final active = _trip;
    if (active == null) return;

    final point = TripPoint.fromPosition(active.id, position);
    final previous = _points.isEmpty ? null : _points.last;

    if (previous != null &&
        position.accuracy <= _maxOdometerAccuracyMeters &&
        previous.accuracy <= _maxOdometerAccuracyMeters) {
      _distanceMeters += _location.distanceBetween(
        previous.latitude,
        previous.longitude,
        point.latitude,
        point.longitude,
      );
    }

    _points.add(point);
    _lastPosition = position;
    notifyListeners();

    await _maybeAnnounceArrival();

    try {
      await _repository.appendPoint(point);
    } catch (error) {
      // A dropped breadcrumb should not tear down a live trip; the trail in
      // memory stays correct and the next write will likely succeed.
      _error = error;
      notifyListeners();
    }
  }

  /// Tells the driver they have arrived, once, when they come inside the
  /// configured radius. The phone is usually showing a nav app rather than
  /// this one, so a notification is the only way this lands.
  Future<void> _maybeAnnounceArrival() async {
    if (_announcedArrival) return;
    final settings = _settings();
    if (!settings.arrivalAlerts) return;

    final stop = _delivery;
    final distance = metersToDestination;
    if (stop == null || distance == null) return;
    if (distance > settings.arrivalRadiusMeters) return;

    // Set before awaiting: a burst of fixes inside the radius must not queue
    // up several notifications.
    _announcedArrival = true;
    await _notifications.showArrival(
      reference: stop.reference,
      customerName: stop.customerName,
      address: stop.address,
    );
  }

  double _measureTrail(List<TripPoint> trail) {
    var total = 0.0;
    for (var i = 1; i < trail.length; i++) {
      final a = trail[i - 1];
      final b = trail[i];
      if (a.accuracy > _maxOdometerAccuracyMeters ||
          b.accuracy > _maxOdometerAccuracyMeters) {
        continue;
      }
      total += _location.distanceBetween(
        a.latitude,
        a.longitude,
        b.latitude,
        b.longitude,
      );
    }
    return total;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
