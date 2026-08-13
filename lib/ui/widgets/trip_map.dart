import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Map with the breadcrumb trail, the driver's current fix, and the
/// destination pin.
///
/// Tiles come from OpenStreetMap, which needs no API key — the trade-off is
/// that the map is blank without a network connection. The recorded trail is
/// local, so tracking itself keeps working offline.
class TripMap extends StatefulWidget {
  const TripMap({
    super.key,
    required this.destination,
    this.trail = const [],
    this.current,
    this.followDriver = true,
    this.recentreRequest = 0,
    this.interactive = true,
    this.onLongPress,
    this.headingDegrees,
    this.courseUp = false,
    this.showBearingLine = false,
  });

  /// Which way the driver is facing, clockwise from true north. Null when
  /// they are not moving fast enough for the GPS to know.
  final double? headingDegrees;

  /// Turn the map so the driver's course points up the screen, the way a nav
  /// app does. North-up otherwise.
  final bool courseUp;

  /// Draw a line from the driver straight to the stop, so which way it is
  /// takes no working out.
  final bool showBearingLine;

  /// Long press anywhere on the map. Goes through the map's own gesture
  /// handling rather than a `GestureDetector` over the top, which would have
  /// to fight the pan and pinch recognisers for it.
  final VoidCallback? onLongPress;

  /// The stop's address, drawn as a pin.
  final LatLng destination;

  /// Recorded positions, oldest first.
  final List<LatLng> trail;

  /// The latest fix, drawn as a pulsing dot. Null before the first fix lands.
  final LatLng? current;

  /// Keep the camera centred on [current] as new fixes arrive.
  final bool followDriver;

  /// Bump this to recentre right now, without waiting for the next fix.
  ///
  /// Needed because the position stream only emits after the driver has moved
  /// the distance filter — so a stationary driver tapping "my location" would
  /// otherwise sit there watching nothing happen.
  final int recentreRequest;

  final bool interactive;

  @override
  State<TripMap> createState() => _TripMapState();
}

class _TripMapState extends State<TripMap> {
  final _controller = MapController();
  bool _mapReady = false;

  @override
  void didUpdateWidget(TripMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = widget.current;
    if (widget.followDriver &&
        current != null &&
        current != oldWidget.current) {
      _recentre(current);
    }
    if (widget.courseUp != oldWidget.courseUp ||
        widget.headingDegrees != oldWidget.headingDegrees) {
      _applyRotation();
    }
  }

  void _recentre(LatLng target) {
    if (!_mapReady) return;
    _controller.move(target, _controller.camera.zoom);
  }

  /// Turns the map so the driver's course is up the screen, or squares it
  /// back to north.
  ///
  /// flutter_map takes rotation as degrees anticlockwise, so a driver heading
  /// east — bearing 90 — needs the map turned to -90 for east to be at the
  /// top. Held at the last known heading rather than snapping back to north
  /// when they stop, because a map that spins while you are parked at a door
  /// is worse than one that is slightly stale.
  void _applyRotation() {
    if (!_mapReady) return;
    final heading = widget.headingDegrees;
    if (!widget.courseUp) {
      if (_controller.camera.rotation != 0) _controller.rotate(0);
      return;
    }
    if (heading == null) return;
    _controller.rotate(-heading);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final centre = widget.current ?? widget.destination;

    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: centre,
        initialZoom: 14.5,
        initialRotation: widget.courseUp ? -(widget.headingDegrees ?? 0) : 0,
        onMapReady: () {
          _mapReady = true;
          _applyRotation();
        },
        onLongPress: widget.onLongPress == null
            ? null
            : (_, _) => widget.onLongPress!(),
        interactionOptions: InteractionOptions(
          flags: widget.interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.vlad.logistics_app',
          maxNativeZoom: 19,
        ),
        // Drawn under the trail: this is a straight line to the stop, not a
        // route, and it must never be mistaken for the road you drove.
        if (widget.showBearingLine && widget.current != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [widget.current!, widget.destination],
                strokeWidth: 2.5,
                color: scheme.error.withValues(alpha: 0.5),
              ),
            ],
          ),
        if (widget.trail.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: widget.trail,
                strokeWidth: 5,
                color: scheme.primary.withValues(alpha: 0.85),
                borderStrokeWidth: 1.5,
                borderColor: scheme.surface,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            Marker(
              point: widget.destination,
              width: 40,
              height: 40,
              alignment: Alignment.topCenter,
              // Stays upright however the map is turned: a pin lying on its
              // side reads as a bug.
              rotate: true,
              child: _DestinationPin(color: scheme.error),
            ),
            if (widget.current != null)
              Marker(
                point: widget.current!,
                width: 34,
                height: 34,
                // Deliberately *not* counter-rotated: this one is supposed to
                // turn with the world, because which way it points is the
                // information it carries.
                child: widget.headingDegrees == null
                    ? _DriverDot(color: scheme.primary, ring: scheme.surface)
                    : _DriverArrow(
                        headingDegrees: widget.headingDegrees!,
                        color: scheme.primary,
                        ring: scheme.surface,
                      ),
              ),
          ],
        ),
        RichAttributionWidget(
          alignment: AttributionAlignment.bottomLeft,
          attributions: [TextSourceAttribution('OpenStreetMap contributors')],
        ),
      ],
    );
  }
}

class _DestinationPin extends StatelessWidget {
  const _DestinationPin({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.location_on,
      color: color,
      size: 38,
      shadows: const [
        Shadow(blurRadius: 4, color: Colors.black38, offset: Offset(0, 1)),
      ],
    );
  }
}

/// The driver, pointed the way they are going.
///
/// Replaces the plain dot as soon as the GPS knows a heading. On a north-up
/// map it says which way you are facing; on a course-up map it sits pointing
/// at the top of the screen, which is the reassurance that the map has turned
/// with you rather than drifted.
class _DriverArrow extends StatelessWidget {
  const _DriverArrow({
    required this.headingDegrees,
    required this.color,
    required this.ring,
  });

  final double headingDegrees;
  final Color color;
  final Color ring;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Transform.rotate(
        angle: headingDegrees * math.pi / 180,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: ring,
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(blurRadius: 5, color: Colors.black38, spreadRadius: 1),
            ],
          ),
          child: Icon(Icons.navigation, size: 20, color: color),
        ),
      ),
    );
  }
}

class _DriverDot extends StatelessWidget {
  const _DriverDot({required this.color, required this.ring});

  final Color color;
  final Color ring;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: ring, width: 3),
          boxShadow: const [
            BoxShadow(blurRadius: 5, color: Colors.black38, spreadRadius: 1),
          ],
        ),
      ),
    );
  }
}
