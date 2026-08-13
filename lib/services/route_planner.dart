import '../models/delivery.dart';

/// Measures metres between two coordinates. Injected so the planner can be
/// tested without geolocator, and so it uses the same haversine the odometer
/// does in production.
typedef DistanceBetween =
    double Function(double lat1, double lng1, double lat2, double lng2);

/// Suggests an order for the remaining stops.
///
/// Two passes over each group of stops. Nearest-neighbour first — start where
/// the driver is, repeatedly go to the closest stop not yet visited — then
/// 2-opt, which repeatedly reverses a run of stops whenever doing so shortens
/// the route. Nearest-neighbour alone lands within roughly 25% of optimal and
/// leaves one characteristic mistake: a long hop back across ground it has
/// already covered, because the last stop it skipped is now miles away. That
/// is exactly the mistake 2-opt undoes, and both are instant on a phone for a
/// round of any realistic size.
///
/// Time slots outrank distance. A stop booked for nine and a stop booked for
/// four in the afternoon are not interchangeable however close they are, so
/// stops are grouped into slots first and only reordered within a group.
/// [slotWindow] is how far apart two stops can be booked and still count as
/// the same slot; pass [respectSlots] false for pure distance.
///
/// Deliberately advisory. The result is an order to *show*, not a commitment:
/// one-way streets and a customer who is only in after four beat straight-line
/// distance, and the driver knows about those.
List<Delivery> planRoute(
  List<Delivery> stops, {
  required double fromLatitude,
  required double fromLongitude,
  required DistanceBetween distanceBetween,
  bool respectSlots = true,
  Duration slotWindow = const Duration(hours: 1),
}) {
  if (stops.length <= 1) return [...stops];

  final groups = respectSlots
      ? _bySlot(stops, slotWindow)
      : [
          [...stops],
        ];

  final ordered = <Delivery>[];
  var currentLat = fromLatitude;
  var currentLng = fromLongitude;

  for (final group in groups) {
    final leg = _twoOpt(
      _nearestNeighbour(
        group,
        fromLatitude: currentLat,
        fromLongitude: currentLng,
        distanceBetween: distanceBetween,
      ),
      fromLatitude: currentLat,
      fromLongitude: currentLng,
      distanceBetween: distanceBetween,
    );

    ordered.addAll(leg);
    if (leg.isNotEmpty) {
      currentLat = leg.last.latitude;
      currentLng = leg.last.longitude;
    }
  }

  return ordered;
}

/// Splits [stops] into runs that share a delivery slot, earliest first.
///
/// A new group starts as soon as a stop is booked more than [window] after the
/// one that opened the current group — so a morning of half-hourly slots is
/// one group to optimise across, while this morning and this afternoon stay
/// apart.
List<List<Delivery>> _bySlot(List<Delivery> stops, Duration window) {
  final sorted = [...stops]
    ..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));

  final groups = <List<Delivery>>[];
  DateTime? openedAt;

  for (final stop in sorted) {
    if (openedAt == null || stop.scheduledFor.difference(openedAt) > window) {
      groups.add([stop]);
      openedAt = stop.scheduledFor;
    } else {
      groups.last.add(stop);
    }
  }
  return groups;
}

List<Delivery> _nearestNeighbour(
  List<Delivery> stops, {
  required double fromLatitude,
  required double fromLongitude,
  required DistanceBetween distanceBetween,
}) {
  final remaining = [...stops];
  final ordered = <Delivery>[];

  var currentLat = fromLatitude;
  var currentLng = fromLongitude;

  while (remaining.isNotEmpty) {
    var bestIndex = 0;
    var bestDistance = double.infinity;

    for (var i = 0; i < remaining.length; i++) {
      final candidate = remaining[i];
      final distance = distanceBetween(
        currentLat,
        currentLng,
        candidate.latitude,
        candidate.longitude,
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }

    final next = remaining.removeAt(bestIndex);
    ordered.add(next);
    currentLat = next.latitude;
    currentLng = next.longitude;
  }

  return ordered;
}

/// Improves an order by reversing runs of stops while that shortens the route.
///
/// An open path, not a loop: the driver starts where they are and finishes
/// wherever the last stop is, so reversing a run that ends at the final stop
/// only changes the one edge leading into it.
///
/// Bounded rather than run to convergence. Each pass is O(n²) and a round of
/// eighty stops is not worth more than a few of them on a phone between drops
/// — the first pass takes out almost all of what there is to take out.
List<Delivery> _twoOpt(
  List<Delivery> order, {
  required double fromLatitude,
  required double fromLongitude,
  required DistanceBetween distanceBetween,
  int maxPasses = 6,
}) {
  if (order.length < 3) return order;

  final route = [...order];
  final n = route.length;

  double gapTo(int index, double lat, double lng) =>
      distanceBetween(lat, lng, route[index].latitude, route[index].longitude);

  for (var pass = 0; pass < maxPasses; pass++) {
    var improved = false;

    for (var i = 0; i < n - 1; i++) {
      // What comes immediately before the run being reversed: the driver
      // themselves for the first stop, otherwise the stop before it.
      final beforeLat = i == 0 ? fromLatitude : route[i - 1].latitude;
      final beforeLng = i == 0 ? fromLongitude : route[i - 1].longitude;

      for (var j = i + 1; j < n; j++) {
        final removedIn = gapTo(i, beforeLat, beforeLng);
        final addedIn = gapTo(j, beforeLat, beforeLng);

        // The edge out of the run only exists when the run stops short of the
        // end of the route.
        var removedOut = 0.0;
        var addedOut = 0.0;
        if (j + 1 < n) {
          final after = route[j + 1];
          removedOut = distanceBetween(
            route[j].latitude,
            route[j].longitude,
            after.latitude,
            after.longitude,
          );
          addedOut = distanceBetween(
            route[i].latitude,
            route[i].longitude,
            after.latitude,
            after.longitude,
          );
        }

        final delta = (addedIn + addedOut) - (removedIn + removedOut);
        // A tolerance rather than < 0: floating-point noise would otherwise
        // let two orders of identical length flip back and forth forever.
        if (delta < -1e-9) {
          _reverse(route, i, j);
          improved = true;
        }
      }
    }

    if (!improved) break;
  }

  return route;
}

void _reverse(List<Delivery> route, int from, int to) {
  var i = from;
  var j = to;
  while (i < j) {
    final swap = route[i];
    route[i] = route[j];
    route[j] = swap;
    i++;
    j--;
  }
}

/// Total straight-line distance of [stops] in the order given, starting from
/// the driver. Used to tell them whether reordering is worth it.
double routeLength(
  List<Delivery> stops, {
  required double fromLatitude,
  required double fromLongitude,
  required DistanceBetween distanceBetween,
}) {
  var total = 0.0;
  var currentLat = fromLatitude;
  var currentLng = fromLongitude;

  for (final stop in stops) {
    total += distanceBetween(
      currentLat,
      currentLng,
      stop.latitude,
      stop.longitude,
    );
    currentLat = stop.latitude;
    currentLng = stop.longitude;
  }
  return total;
}
