import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/delivery.dart';
import '../services/location_service.dart';
import '../state/tracking_controller.dart';
import 'delivery_actions.dart';
import 'formatters.dart';
import 'widgets/stat_tile.dart';
import 'widgets/trip_map.dart';

/// Live view of the trip in progress: where the driver is, where they have
/// been, and how far there is left to go.
class LiveTab extends StatefulWidget {
  const LiveTab({super.key, required this.onBrowseManifest});

  final VoidCallback onBrowseManifest;

  @override
  State<LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends State<LiveTab> {
  /// The elapsed clock has to tick even when no new fix has arrived, so it
  /// gets its own timer rather than riding on position updates.
  Timer? _clock;
  bool _followDriver = true;
  bool _backgroundPermissionGranted = true;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && context.read<TrackingController>().isTracking) {
        setState(() {});
      }
    });
    _checkBackgroundPermission();
  }

  Future<void> _checkBackgroundPermission() async {
    final granted = await context
        .read<LocationService>()
        .hasBackgroundPermission();
    if (mounted) setState(() => _backgroundPermissionGranted = granted);
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tracking = context.watch<TrackingController>();
    final delivery = tracking.delivery;
    final trip = tracking.trip;

    if (delivery == null || trip == null) {
      return _IdleView(onBrowseManifest: widget.onBrowseManifest);
    }

    final trail = [for (final point in tracking.points) point.latLng];
    final current = tracking.lastPosition;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: TripMap(
              destination: LatLng(delivery.latitude, delivery.longitude),
              trail: trail,
              current: current == null
                  ? null
                  : LatLng(current.latitude, current.longitude),
              followDriver: _followDriver,
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                _DestinationBanner(
                  delivery: delivery,
                  isRecording: tracking.isTracking,
                ),
                if (!_backgroundPermissionGranted && tracking.isTracking)
                  _BackgroundPermissionNudge(
                    onGrant: () async {
                      await tracking.requestBackgroundPermission();
                      await _checkBackgroundPermission();
                    },
                    onDismiss: () =>
                        setState(() => _backgroundPermissionGranted = true),
                  ),
                const Spacer(),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12, bottom: 8),
                    child: FloatingActionButton.small(
                      heroTag: 'follow',
                      onPressed: () =>
                          setState(() => _followDriver = !_followDriver),
                      tooltip: _followDriver
                          ? 'Stop following'
                          : 'Follow my position',
                      child: Icon(
                        _followDriver ? Icons.gps_fixed : Icons.gps_not_fixed,
                      ),
                    ),
                  ),
                ),
                _TripPanel(
                  tracking: tracking,
                  delivery: delivery,
                  onArrived: () => completeDelivery(context, delivery),
                  onFailed: () => failDelivery(context, delivery),
                  onEndTrip: tracking.stop,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IdleView extends StatelessWidget {
  const _IdleView({required this.onBrowseManifest});

  final VoidCallback onBrowseManifest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Live tracking')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.radar,
                size: 56,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text('Not tracking', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Pick a stop from the manifest and start the trip. Your route '
                'is recorded on this device and shown here as you drive.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.tonalIcon(
                onPressed: onBrowseManifest,
                icon: const Icon(Icons.list_alt),
                label: const Text('Open manifest'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DestinationBanner extends StatelessWidget {
  const _DestinationBanner({required this.delivery, required this.isRecording});

  final Delivery delivery;
  final bool isRecording;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            _RecordingDot(active: isRecording),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${delivery.reference} · ${delivery.customerName}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    delivery.address,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingDot extends StatelessWidget {
  const _RecordingDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? scheme.error : scheme.outline,
      ),
    );
  }
}

class _BackgroundPermissionNudge extends StatelessWidget {
  const _BackgroundPermissionNudge({
    required this.onGrant,
    required this.onDismiss,
  });

  final VoidCallback onGrant;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Allow location "all the time" so tracking keeps running with '
                'the screen off.',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
            TextButton(onPressed: onGrant, child: const Text('Allow')),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Dismiss',
            ),
          ],
        ),
      ),
    );
  }
}

class _TripPanel extends StatelessWidget {
  const _TripPanel({
    required this.tracking,
    required this.delivery,
    required this.onArrived,
    required this.onFailed,
    required this.onEndTrip,
  });

  final TrackingController tracking;
  final Delivery delivery;
  final VoidCallback onArrived;
  final VoidCallback onFailed;
  final Future<void> Function() onEndTrip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fix = tracking.lastPosition;
    final remaining = tracking.metersToDestination;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: StatTile(
                    label: 'TO GO',
                    value: remaining == null ? '—' : formatDistance(remaining),
                    icon: Icons.flag_outlined,
                    emphasis: true,
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'DRIVEN',
                    value: formatDistance(tracking.distanceMeters),
                    icon: Icons.route_outlined,
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'ELAPSED',
                    value: formatDuration(tracking.elapsed),
                    icon: Icons.timer_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: StatTile(
                    label: 'SPEED',
                    value: formatSpeed(fix?.speed ?? 0),
                    icon: Icons.speed,
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'ACCURACY',
                    value: fix == null ? '—' : formatAccuracy(fix.accuracy),
                    icon: Icons.my_location,
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'FIXES',
                    value: '${tracking.points.length}',
                    icon: Icons.location_searching,
                  ),
                ),
              ],
            ),

            if (fix == null && tracking.isTracking) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Waiting for the first GPS fix…',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ],

            if (tracking.error case final Object error) ...[
              const SizedBox(height: 10),
              Text(
                '$error',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: tracking.isBusy ? null : onArrived,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Arrived — complete delivery'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: tracking.isBusy ? null : onFailed,
                    icon: const Icon(
                      Icons.report_gmailerrorred_outlined,
                      size: 18,
                    ),
                    label: const Text("Couldn't deliver"),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: tracking.isBusy || !tracking.isTracking
                        ? null
                        : () => onEndTrip(),
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('Stop recording'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
