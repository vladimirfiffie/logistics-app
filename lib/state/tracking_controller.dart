import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../data/delivery_repository.dart';
import '../models/delivery.dart';
import '../models/trip.dart';
import '../models/trip_point.dart';
import '../services/location_service.dart';

/// Drives the live tracking session: permissions, the position stream, the
/// breadcrumb trail, and the running odometer.
class TrackingController extends ChangeNotifier {
  TrackingController({
    required DeliveryRepository repository,
    required LocationService locationService,
    this.onManifestChanged,
  }) : _repository = repository,
       _location = locationService;

  final DeliveryRepository _repository;
  final LocationService _location;

  /// Called when a start/stop changes a delivery's status, so the manifest
  /// list can re-read it.
  final Future<void> Function()? onManifestChanged;

  /// Fixes worse than this are recorded but excluded from the odometer — a
  /// 200m-accuracy reading between two good fixes would otherwise add a
  /// phantom kilometre to the trip.
  static const _maxOdometerAccuracyMeters = 50.0;

  Trip? _trip;
  Delivery? _delivery;
  List<TripPoint> _points = const [];
  double _distanceMeters = 0;
  Position? _lastPosition;
  StreamSubscription<Position>? _subscription;
  LocationReadiness _readiness = LocationReadiness.ready;
  Object? _error;
  bool _isBusy = false;

  Trip? get trip => _trip;
  Delivery? get delivery => _delivery;
  List<TripPoint> get points => _points;
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
    notifyListeners();

    final readiness = await _location.ensureReady();
    _readiness = readiness;
    if (readiness == LocationReadiness.ready) {
      _listen();
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
      _points = const [];
      _distanceMeters = 0;
      _lastPosition = null;
      _listen();
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
      await _subscription?.cancel();
      _subscription = null;
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
    _points = const [];
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

  void _listen() {
    _subscription?.cancel();
    final label = _delivery?.customerName ?? 'Delivery in progress';
    _subscription = _location
        .trackPosition(notificationText: 'On the way to $label')
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

    _points = [..._points, point];
    _lastPosition = position;
    notifyListeners();

    try {
      await _repository.appendPoint(point);
    } catch (error) {
      // A dropped breadcrumb should not tear down a live trip; the trail in
      // memory stays correct and the next write will likely succeed.
      _error = error;
      notifyListeners();
    }
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
