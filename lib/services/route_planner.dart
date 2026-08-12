import '../models/delivery.dart';

/// Measures metres between two coordinates. Injected so the planner can be
/// tested without geolocator, and so it uses the same haversine the odometer
/// does in production.
typedef DistanceBetween =
    double Function(double lat1, double lng1, double lat2, double lng2);

/// Suggests an order for the remaining stops.
///
/// Nearest-neighbour: start where the driver is, repeatedly go to the closest
/// stop not yet visited. It is not the optimal tour — that is TSP, and solving
/// it properly for fifty stops is not something to do on a phone between
/// drops — but it is typically within about 25% of optimal and it is
/// instant, which is the trade a driver actually wants.
///
/// Deliberately advisory. The result is an order to *show*, not a commitment:
/// time slots, one-way streets and a customer who is only in after four all
/// beat straight-line distance, and the driver knows about those.
List<Delivery> planRoute(
  List<Delivery> stops, {
  required double fromLatitude,
  required double fromLongitude,
  required DistanceBetween distanceBetween,
}) {
  if (stops.length <= 1) return [...stops];

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
