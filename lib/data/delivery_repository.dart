import '../models/delivery.dart';
import '../models/shift.dart';
import '../models/shift_break.dart';
import '../models/trip.dart';
import '../models/trip_point.dart';

/// The only contract the UI knows about.
///
/// Everything above this line is storage-agnostic, so pointing the app at a
/// real dispatch backend later means writing one more implementation of this
/// interface and changing the single construction site in `main.dart` — no UI
/// or controller changes.
abstract interface class DeliveryRepository {
  Future<List<Delivery>> fetchDeliveries();

  Future<Delivery?> fetchDelivery(String id);

  Future<void> saveDelivery(Delivery delivery);

  /// Opens a tracking session for [deliveryId] and flips the stop to
  /// [DeliveryStatus.inTransit].
  Future<Trip> startTrip(String deliveryId);

  /// The trip that is currently recording, if any. At most one exists.
  Future<Trip?> activeTrip();

  Future<Trip?> tripForDelivery(String deliveryId);

  /// Every recorded trip, newest first. Used for the day's totals.
  Future<List<Trip>> fetchTrips();

  Future<void> appendPoint(TripPoint point);

  Future<List<TripPoint>> pointsForTrip(String tripId);

  /// Closes the session and stamps the final odometer reading.
  Future<Trip> endTrip(String tripId, {required double distanceMeters});

  /// Removes closed-out stops and everything recorded against them, including
  /// their proof photos and signatures on disk. Open stops are left alone, so
  /// this can be run mid-round. Returns how many went.
  Future<int> deleteClosedDeliveries();

  /// Wipes every delivery, trip, breadcrumb and attachment. Used by "start a
  /// new day", which then re-seeds a fresh manifest.
  Future<void> deleteEverything();

  /// The shift currently clocked on, if any. At most one exists.
  Future<Shift?> activeShift();

  /// Clocks on. Throws [StateError] if a shift is already running.
  Future<Shift> startShift({String? vehicleLabel, bool startedByTag = false});

  /// Clocks off and returns the finished shift. Throws [StateError] if that
  /// shift has already been closed — re-ending would rewrite a timesheet.
  Future<Shift> endShift(String shiftId);

  /// Every shift, newest first.
  Future<List<Shift>> fetchShifts();

  /// The break currently running, if any. At most one exists per shift.
  Future<ShiftBreak?> activeBreak(String shiftId);

  /// Starts a break. Throws [StateError] if one is already running.
  Future<ShiftBreak> startBreak(String shiftId, {BreakKind kind});

  Future<ShiftBreak> endBreak(String breakId);

  /// Every break taken during [shiftId], oldest first.
  Future<List<ShiftBreak>> breaksForShift(String shiftId);

  /// Breaks for several shifts at once, keyed by shift id — so a timesheet
  /// does not fire one query per row.
  Future<Map<String, List<ShiftBreak>>> breaksForShifts(List<String> shiftIds);
}
