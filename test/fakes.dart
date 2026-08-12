import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:logistics_app/data/delivery_repository.dart';
import 'package:logistics_app/models/app_settings.dart';
import 'package:logistics_app/models/delivery.dart';
import 'package:logistics_app/models/trip.dart';
import 'package:logistics_app/models/trip_point.dart';
import 'package:logistics_app/services/location_service.dart';

/// In-memory stand-in for the SQLite repository.
class FakeDeliveryRepository implements DeliveryRepository {
  final Map<String, Delivery> deliveries = {};
  final Map<String, Trip> trips = {};
  final List<TripPoint> points = [];

  /// Set to make [appendPoint] fail, exercising the "dropped breadcrumb"
  /// path.
  bool failOnAppend = false;

  var _nextTripId = 0;

  @override
  Future<List<Delivery>> fetchDeliveries() async => deliveries.values.toList();

  @override
  Future<Delivery?> fetchDelivery(String id) async => deliveries[id];

  @override
  Future<void> saveDelivery(Delivery delivery) async {
    deliveries[delivery.id] = delivery;
  }

  @override
  Future<Trip> startTrip(String deliveryId) async {
    if (trips.values.any((trip) => trip.isActive)) {
      throw StateError('A trip is already recording.');
    }
    final trip = Trip(
      id: 'trip-${_nextTripId++}',
      deliveryId: deliveryId,
      startedAt: DateTime.now(),
    );
    trips[trip.id] = trip;
    final delivery = deliveries[deliveryId];
    if (delivery != null) {
      deliveries[deliveryId] = delivery.copyWith(
        status: DeliveryStatus.inTransit,
      );
    }
    return trip;
  }

  @override
  Future<Trip?> activeTrip() async {
    for (final trip in trips.values) {
      if (trip.isActive) return trip;
    }
    return null;
  }

  @override
  Future<Trip?> tripForDelivery(String deliveryId) async {
    for (final trip in trips.values) {
      if (trip.deliveryId == deliveryId) return trip;
    }
    return null;
  }

  @override
  Future<List<Trip>> fetchTrips() async => trips.values.toList();

  @override
  Future<void> appendPoint(TripPoint point) async {
    if (failOnAppend) throw StateError('disk full');
    points.add(point);
  }

  @override
  Future<List<TripPoint>> pointsForTrip(String tripId) async =>
      points.where((point) => point.tripId == tripId).toList();

  @override
  Future<int> deleteClosedDeliveries() async {
    final closed = deliveries.values
        .where((delivery) => !delivery.status.isOpen)
        .map((delivery) => delivery.id)
        .toList();
    for (final id in closed) {
      deliveries.remove(id);
      final tripIds = trips.values
          .where((trip) => trip.deliveryId == id)
          .map((trip) => trip.id)
          .toList();
      for (final tripId in tripIds) {
        trips.remove(tripId);
        points.removeWhere((point) => point.tripId == tripId);
      }
    }
    return closed.length;
  }

  @override
  Future<void> deleteEverything() async {
    deliveries.clear();
    trips.clear();
    points.clear();
  }

  @override
  Future<Trip> endTrip(String tripId, {required double distanceMeters}) async {
    final trip = trips[tripId];
    if (trip == null) throw StateError('No such trip');
    final ended = trip.copyWith(
      endedAt: DateTime.now(),
      distanceMeters: distanceMeters,
    );
    trips[tripId] = ended;
    return ended;
  }
}

/// Stand-in for the GPS. Positions are pushed by the test rather than by the
/// device.
///
/// [distanceBetween] returns a fixed [segmentMeters] for any pair: the
/// haversine itself belongs to geolocator, and what these tests care about is
/// *which* segments the controller decides to count.
class FakeLocationService implements LocationService {
  FakeLocationService({
    this.readiness = LocationReadiness.ready,
    this.segmentMeters = 100,
    this.backgroundGranted = false,
  });

  LocationReadiness readiness;
  final double segmentMeters;
  bool backgroundGranted;

  final _positions = StreamController<Position>.broadcast();
  int settingsOpened = 0;
  int locationSettingsOpened = 0;
  String? lastNotificationText;

  void emit(Position position) => _positions.add(position);

  void emitError(Object error) => _positions.addError(error);

  Future<void> dispose() => _positions.close();

  @override
  Future<LocationReadiness> ensureReady() async => readiness;

  @override
  Future<LocationReadiness> currentReadiness() async => readiness;

  @override
  Future<bool> requestBackgroundPermission() async {
    backgroundGranted = true;
    return true;
  }

  @override
  Future<bool> hasBackgroundPermission() async => backgroundGranted;

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettingsOpened++;
    return true;
  }

  @override
  Future<Position> currentPosition() async => makePosition();

  @override
  Future<Position?> lastKnownPosition() async => null;

  /// The accuracy the controller asked for on the most recent start.
  TrackingAccuracy? lastAccuracy;

  @override
  Stream<Position> trackPosition({
    required String notificationText,
    TrackingAccuracy accuracy = TrackingAccuracy.balanced,
  }) {
    lastNotificationText = notificationText;
    lastAccuracy = accuracy;
    return _positions.stream;
  }

  @override
  double distanceBetween(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) => segmentMeters;
}

/// Builds a [Position] without needing a device.
Position makePosition({
  double latitude = 51.5,
  double longitude = -0.12,
  double accuracy = 5,
  double speed = 10,
  DateTime? timestamp,
}) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: timestamp ?? DateTime(2026, 8, 11, 9),
  accuracy: accuracy,
  altitude: 25,
  altitudeAccuracy: 3,
  heading: 90,
  headingAccuracy: 5,
  speed: speed,
  speedAccuracy: 1,
);

TripPoint makeTripPoint(
  String tripId,
  DateTime at, {
  double latitude = 51.5,
  double longitude = -0.12,
  double accuracy = 5,
}) => TripPoint(
  tripId: tripId,
  latitude: latitude,
  longitude: longitude,
  accuracy: accuracy,
  speed: 10,
  heading: 90,
  altitude: 25,
  recordedAt: at,
);

Delivery makeDelivery({
  String id = 'd1',
  DeliveryStatus status = DeliveryStatus.pending,
}) => Delivery(
  id: id,
  reference: 'LG-1040',
  customerName: 'Harlow & Sons',
  address: '14 Bridgewater Road',
  latitude: 51.52,
  longitude: -0.10,
  status: status,
  scheduledFor: DateTime(2026, 8, 11, 9),
);
