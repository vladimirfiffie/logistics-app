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
  });

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
  }

  void _recentre(LatLng target) {
    if (!_mapReady) return;
    _controller.move(target, _controller.camera.zoom);
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
        onMapReady: () => _mapReady = true,
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
              child: _DestinationPin(color: scheme.error),
            ),
            if (widget.current != null)
              Marker(
                point: widget.current!,
                width: 26,
                height: 26,
                child: _DriverDot(color: scheme.primary, ring: scheme.surface),
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
