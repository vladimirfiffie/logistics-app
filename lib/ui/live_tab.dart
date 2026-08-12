import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:haptic_kit/haptic_kit.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/app_settings.dart';
import '../models/delivery.dart';
import '../services/app_haptics.dart';
import '../services/location_service.dart';
import '../state/tracking_controller.dart';
import '../state/settings_controller.dart';
import 'delivery_actions.dart';
import 'formatters.dart';
import 'widgets/app_sheet.dart';
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

  /// Seeded from the driver's default in initState rather than hardcoded.
  bool _followDriver = true;
  bool _backgroundPermissionGranted = true;
  int _seenFixes = 0;
  int _recentreRequests = 0;

  /// Lets us re-arm the slide handle when the driver backs out of the
  /// completion sheet. Without this the handle stays latched at the end after
  /// a successful slide and the stop can never be completed again.
  final _slideKey = GlobalKey<SlideToConfirmState>();
  bool _wakelockOn = false;
  TrackingController? _tracking;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && context.read<TrackingController>().isTracking) {
        setState(() {});
      }
    });
    _followDriver =
        context.read<SettingsController>().settings.followMode ==
        MapFollowMode.follow;
    _checkBackgroundPermission();
    _tracking = context.read<TrackingController>()..addListener(_onTracking);
  }

  /// Buzzes the moment the first fix lands, so the driver knows tracking is
  /// genuinely live without looking at the screen. Also drives the wakelock,
  /// which has to follow both the setting and whether a trip is running.
  void _onTracking() {
    final tracking = _tracking;
    if (tracking == null) return;

    final fixes = tracking.points.length;
    if (_seenFixes == 0 && fixes > 0) AppHaptics.firstFix();
    _seenFixes = fixes;

    _syncWakelock(tracking.isTracking);
  }

  /// Jumps the map to the driver and turns following back on.
  ///
  /// Always recentres rather than only toggling: someone who has panned away
  /// and taps the location button wants to be taken back, not to change a
  /// mode.
  void _recentre({required bool hasFix}) {
    AppHaptics.select();
    if (!hasFix) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting for the first GPS fix…')),
      );
      return;
    }
    setState(() {
      _followDriver = true;
      _recentreRequests++;
    });
  }

  /// Completing can be abandoned — the driver may cancel the sheet, or be
  /// blocked by the "proof photo required" setting. Either way the slide has
  /// already latched, so it has to be put back.
  Future<void> _arrived(Delivery delivery) async {
    final closed = await completeDelivery(context, delivery);
    if (!closed) _slideKey.currentState?.reset();
  }

  /// Stopping is the one action here that silently changes what the phone is
  /// doing in the background, so it asks first and reports back afterwards.
  /// Without either, the driver has no way to tell whether the tap landed and
  /// whether their location is still being shared.
  Future<void> _stopRecording() async {
    final tracking = context.read<TrackingController>();
    final unit = context.read<SettingsController>().settings.distanceUnit;
    final messenger = ScaffoldMessenger.of(context);
    final reference = tracking.delivery?.reference;
    final recorded = formatDistance(tracking.distanceMeters, unit: unit);

    final confirmed = await _confirmStop(recorded);
    if (confirmed != true || !mounted) return;

    final finished = await tracking.stop();
    await AppHaptics.trackingStopped();
    if (!mounted) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          finished == null
              ? 'Could not stop the recording. Try again.'
              : 'Recording stopped · location sharing ended · $recorded '
                    'recorded.'
                    '${reference == null ? '' : ' $reference is back on the '
                              'manifest.'}',
        ),
      ),
    );
  }

  Future<bool?> _confirmStop(String recorded) {
    final scheme = Theme.of(context).colorScheme;
    return showAppSheet<bool>(
      context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: 'Stop recording?',
              subtitle:
                  'Location sharing ends and the trail stops here, with '
                  '$recorded recorded. The stop goes back on the manifest so '
                  'you can pick it up again — nothing is closed out.',
              icon: Icons.stop_circle_outlined,
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: () => Navigator.of(sheetContext).pop(true),
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Stop recording'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(false),
              child: const Text('Keep sharing my location'),
            ),
          ],
        ),
      ),
    );
  }

  void _syncWakelock(bool isTracking) {
    final wanted =
        isTracking && context.read<SettingsController>().settings.keepScreenOn;
    if (wanted == _wakelockOn) return;
    _wakelockOn = wanted;
    WakelockPlus.toggle(enable: wanted);
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
    _tracking?.removeListener(_onTracking);
    // Never leave the screen pinned awake after leaving this tab.
    if (_wakelockOn) WakelockPlus.disable();
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
              recentreRequest: _recentreRequests,
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
                      onPressed: () => _recentre(hasFix: current != null),
                      tooltip: _followDriver
                          ? 'Recentre'
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
                  slideKey: _slideKey,
                  onArrived: () => _arrived(delivery),
                  onFailed: () => failDelivery(context, delivery),
                  onEndTrip: _stopRecording,
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
    required this.slideKey,
    required this.onArrived,
    required this.onFailed,
    required this.onEndTrip,
  });

  final TrackingController tracking;
  final Delivery delivery;
  final GlobalKey<SlideToConfirmState> slideKey;
  final VoidCallback onArrived;
  final VoidCallback onFailed;
  final Future<void> Function() onEndTrip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = context.distanceUnit;
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
                    value: remaining == null
                        ? '—'
                        : formatDistance(remaining, unit: unit),
                    icon: Icons.flag_outlined,
                    emphasis: true,
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'DRIVEN',
                    value: formatDistance(tracking.distanceMeters, unit: unit),
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
                    value: formatSpeed(fix?.speed ?? 0, unit: unit),
                    icon: Icons.speed,
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'ACCURACY',
                    value: fix == null
                        ? '—'
                        : formatAccuracy(fix.accuracy, unit: unit),
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

            // A finished trip still on screen looks exactly like a running
            // one otherwise, which is half of why "stop" felt like it had not
            // worked.
            if (!tracking.isTracking) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.location_off_outlined,
                    size: 15,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Recording stopped. Your location is no longer being '
                      'shared.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
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
            // A tap is easy to hit by accident on a phone bouncing in a van,
            // and closing out the wrong stop is a nuisance to undo — so the
            // default is a deliberate slide.
            if (context.appSettings.confirmWithSlide)
              SlideToConfirm(
                key: slideKey,
                label: 'Slide when you have arrived',
                onConfirmed: tracking.isBusy ? () {} : onArrived,
                trackColor: theme.colorScheme.surfaceContainerHighest,
                handleColor: theme.colorScheme.primary,
                textColor: theme.colorScheme.onSurfaceVariant,
              )
            else
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
