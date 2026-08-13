import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/app_settings.dart';
import '../models/delivery.dart';
import '../models/fix.dart';
import '../services/app_haptics.dart';
import '../services/location_service.dart';
import '../state/tracking_controller.dart';
import '../state/settings_controller.dart';
import '../services/bearing.dart';
import 'delivery_actions.dart';
import 'formatters.dart';
import 'shift_actions.dart';
import 'widgets/app_sheet.dart';
import 'widgets/outcome_colors.dart';
import 'widgets/slide_to_arrive.dart';
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

  /// Everything except the map hidden, on a long press. Worth having on a
  /// phone clamped to a windscreen: the panel and the banner cover about half
  /// the map, and a driver checking which way the road bends does not need
  /// either of them.
  bool _chromeHidden = false;

  /// The trip panel dragged down to its peek bar. Between "everything" and
  /// the long-press "nothing": the driver still sees which stop they are on
  /// and how far is left, and gets two thirds of the screen back for the map.
  bool _panelCollapsed = false;

  /// Set once the arrival state has been shown for this trip, so collapsing
  /// the panel and arriving cannot fight each other — arriving opens the
  /// panel once, and after that the driver's choice stands.
  bool _openedOnArrival = false;

  /// Which trip [_openedOnArrival] belongs to.
  String? _armedTripId;

  /// Map turned so the way the driver is going is up the screen. Seeded from
  /// their setting, and toggled from the compass button for one round.
  bool _courseUp = false;
  bool _backgroundPermissionGranted = true;
  int _seenFixes = 0;
  int _recentreRequests = 0;

  /// Lets us re-arm the slide handle when the driver backs out of the
  /// completion sheet. Without this the handle stays latched at the end after
  /// a successful slide and the stop can never be completed again.
  final _slideKey = GlobalKey<SlideToArriveState>();
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
    final settings = context.read<SettingsController>().settings;
    _followDriver = settings.followMode == MapFollowMode.follow;
    _courseUp = settings.mapOrientation == MapOrientation.courseUp;
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

    // A new trip starts with a fresh panel: the arrival state belongs to the
    // stop it fired for.
    if (tracking.trip?.id != _armedTripId) {
      _armedTripId = tracking.trip?.id;
      _openedOnArrival = false;
    }

    // Arriving opens the panel, once. The driver is about to need the
    // complete and failed buttons, and hunting for a collapsed panel with a
    // parcel under one arm is exactly the moment not to make them.
    if (tracking.hasArrived && !_openedOnArrival && mounted) {
      _openedOnArrival = true;
      if (_panelCollapsed || _chromeHidden) {
        setState(() {
          _panelCollapsed = false;
          _chromeHidden = false;
        });
      }
    }

    _syncWakelock(tracking.isTracking);
  }

  void _togglePanel() {
    AppHaptics.select();
    setState(() => _panelCollapsed = !_panelCollapsed);
  }

  /// North-up or course-up, for this round. The setting is the default; this
  /// is the driver changing their mind halfway down a lane.
  void _toggleOrientation() {
    AppHaptics.select();
    setState(() => _courseUp = !_courseUp);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _courseUp
              ? 'The map now turns with you.'
              : 'The map is back to north up.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Starts recording again for the stop already on screen.
  ///
  /// The live view could stop a recording and never start one: a driver who
  /// stopped by mistake, or stopped to nip into a depot, had to go back to
  /// the manifest and find the stop again. It asks first for the same reason
  /// stopping does — it turns the GPS back on.
  Future<void> _startRecording(Delivery delivery) async {
    final confirmed = await showAppSheet<bool>(
      context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: 'Start recording again?',
              subtitle:
                  '${delivery.reference} · ${delivery.customerName}. Your '
                  'route and your position are recorded on this phone until '
                  'you stop or close the stop out.',
              icon: Icons.play_circle_outline,
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: () => Navigator.of(sheetContext).pop(true),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start recording'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(false),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    // The same check the manifest makes: recording against no shift keeps the
    // distance and loses the hours.
    if (!await ensureOnShift(context) || !mounted) return;

    final tracking = context.read<TrackingController>();
    final messenger = ScaffoldMessenger.of(context);
    final started = await tracking.start(delivery);

    if (started) {
      await AppHaptics.trackingStarted();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Recording ${delivery.customerName} again.')),
      );
      return;
    }

    await AppHaptics.error();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(tracking.error?.toString() ?? tracking.readiness.message),
      ),
    );
  }

  /// Long press hides the chrome; long press again brings it back. Announced
  /// the first time it happens, because a screen that has just emptied itself
  /// needs to say how to undo that.
  void _toggleChrome() {
    AppHaptics.select();
    setState(() => _chromeHidden = !_chromeHidden);
    if (!_chromeHidden) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Just the map. Long press again to bring it back.'),
        duration: Duration(seconds: 3),
      ),
    );
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
              onLongPress: _toggleChrome,
              headingDegrees: tracking.headingDegrees,
              courseUp: _courseUp,
              // Only while the trip is live: a straight line to a stop you
              // have already closed out is noise.
              showBearingLine: tracking.isTracking,
            ),
          ),

          // Faded rather than removed, and ignoring pointers while hidden, so
          // the map underneath takes every touch and the panel cannot be
          // pressed by accident through it.
          IgnorePointer(
            ignoring: _chromeHidden,
            child: AnimatedOpacity(
              opacity: _chromeHidden ? 0 : 1,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: SafeArea(
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
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FloatingActionButton.small(
                              heroTag: 'orientation',
                              onPressed: _toggleOrientation,
                              tooltip: _courseUp
                                  ? 'Face the map north'
                                  : 'Turn the map with me',
                              child: Icon(
                                _courseUp
                                    ? Icons.navigation
                                    : Icons.explore_outlined,
                              ),
                            ),
                            const SizedBox(height: 10),
                            FloatingActionButton.small(
                              heroTag: 'follow',
                              onPressed: () =>
                                  _recentre(hasFix: current != null),
                              tooltip: _followDriver
                                  ? 'Recentre'
                                  : 'Follow my position',
                              child: Icon(
                                _followDriver
                                    ? Icons.gps_fixed
                                    : Icons.gps_not_fixed,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _TripPanel(
                      tracking: tracking,
                      delivery: delivery,
                      slideKey: _slideKey,
                      collapsed: _panelCollapsed,
                      onToggleCollapsed: _togglePanel,
                      onArrived: () => _arrived(delivery),
                      onFailed: () => failDelivery(context, delivery),
                      onEndTrip: _stopRecording,
                      onStartTrip: () => _startRecording(delivery),
                    ),
                  ],
                ),
              ),
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

/// Which way the stop is from here.
///
/// An arrow that points at the address, turned relative to the way the driver
/// is facing, and the same thing said in words. Not a route: there is no road
/// network behind it, and the wording is deliberately vague enough that it
/// cannot be mistaken for one.
class _DirectionLine extends StatelessWidget {
  const _DirectionLine({required this.bearing, required this.relative});

  /// Clockwise from true north.
  final double? bearing;

  /// Relative to the driver's heading, when they are moving fast enough for
  /// the GPS to have one.
  final double? relative;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final heading = bearing;
    if (heading == null) return const SizedBox.shrink();

    // Pointed relative to the driver when their heading is known, and at true
    // north when it is not — a stationary van gets a compass, not a lie about
    // which way it is facing.
    final turn = relative ?? heading;

    return Row(
      children: [
        Transform.rotate(
          angle: turn * math.pi / 180,
          child: Icon(Icons.arrow_upward, size: 20, color: scheme.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            relative == null
                ? 'The stop is ${compassPoint(heading)} of you'
                : 'The stop is ${describeRelative(relative!)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          compassPoint(heading),
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// The trip panel folded down to one line.
///
/// Keeps the two things a driver needs while actually driving — which stop
/// they are on and how far is left — and gives the rest of the screen back to
/// the map. Everything else is one tap away.
class _PeekBar extends StatelessWidget {
  const _PeekBar({
    required this.delivery,
    required this.remaining,
    required this.eta,
    required this.arrived,
    required this.onExpand,
  });

  final Delivery delivery;
  final double? remaining;
  final Duration? eta;
  final bool arrived;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = context.distanceUnit;
    final foreground = arrived ? context.onDeliveredContainer : null;

    return InkWell(
      onTap: onExpand,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 10, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onVerticalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) < 0) onExpand();
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: (foreground ?? theme.colorScheme.onSurfaceVariant)
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Icon(
                  arrived ? Icons.where_to_vote : Icons.flag_outlined,
                  size: 20,
                  color: foreground ?? theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        arrived
                            ? "You're here"
                            : remaining == null
                            ? 'Waiting for a fix'
                            : '${formatDistance(remaining!, unit: unit)} to go'
                                  '${eta == null ? '' : ' · ${formatDuration(eta!)}'}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: foreground,
                        ),
                      ),
                      Text(
                        delivery.customerName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              foreground ?? theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_up,
                  color: foreground ?? theme.colorScheme.onSurfaceVariant,
                ),
              ],
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
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onArrived,
    required this.onFailed,
    required this.onEndTrip,
    required this.onStartTrip,
  });

  final TrackingController tracking;
  final Delivery delivery;

  /// Dragged down to the peek bar.
  final bool collapsed;

  final VoidCallback onToggleCollapsed;
  final GlobalKey<SlideToArriveState> slideKey;
  final VoidCallback onArrived;
  final VoidCallback onFailed;
  final Future<void> Function() onEndTrip;

  /// Picks the recording back up for the stop already on screen.
  final VoidCallback onStartTrip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = context.distanceUnit;
    final fix = tracking.lastPosition;
    final remaining = tracking.metersToDestination;
    final eta = tracking.etaToDestination;
    final arrived = tracking.hasArrived && tracking.isTracking;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      elevation: 4,
      // Green at the door: the panel changing colour is the fastest way to
      // say "you are here" to someone glancing at a phone on a mount.
      color: arrived ? context.deliveredContainer : null,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: Alignment.bottomCenter,
        child: collapsed
            ? _PeekBar(
                delivery: delivery,
                remaining: remaining,
                eta: eta,
                arrived: arrived,
                onExpand: onToggleCollapsed,
              )
            : _full(context, theme, unit, fix, remaining, eta, arrived),
      ),
    );
  }

  Widget _full(
    BuildContext context,
    ThemeData theme,
    DistanceUnit unit,
    Fix? fix,
    double? remaining,
    Duration? eta,
    bool arrived,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The grab handle. Tappable as well as draggable, because a tap is
          // what everyone tries first.
          GestureDetector(
            onTap: onToggleCollapsed,
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) > 0) onToggleCollapsed();
            },
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),

          if (arrived) ...[
            Row(
              children: [
                Icon(Icons.where_to_vote, color: context.onDeliveredContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "You're here — ${delivery.customerName}",
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.onDeliveredContainer,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],

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
                  // Straight-line, from the pace actually being driven.
                  // "—" until there is enough trip to average, which is
                  // better than a confident number pulled out of nothing.
                  label: 'ETA',
                  value: eta == null ? '—' : formatDuration(eta),
                  icon: Icons.schedule,
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
          // Which way it is, in words. A bearing on its own means nothing at
          // a junction; "ahead and to your right" is what a passenger would
          // say, and it is the honest limit of what a straight line to an
          // address can tell anyone.
          if (!arrived && remaining != null) ...[
            const SizedBox(height: 10),
            _DirectionLine(
              bearing: tracking.bearingToDestination,
              relative: tracking.relativeBearingToDestination,
            ),
          ],

          const SizedBox(height: 12),
          // The second row is instrumentation rather than driving
          // information, so it stands down once the driver is at the door
          // and the panel has a job to do.
          if (!arrived)
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

          // Location switched off under a running trip. Without this the trail
          // just stops growing, which looks exactly like driving through a
          // tunnel — and the driver finds out at the end of the day.
          if (tracking.locationTurnedOff && tracking.isTracking) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.location_disabled,
                  size: 16,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Location is switched off on this phone. Nothing is being '
                    'recorded until it goes back on.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      context.read<LocationService>().openLocationSettings(),
                  child: const Text('Turn on'),
                ),
              ],
            ),
          ],

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
            SlideToArrive(
              key: slideKey,
              label: arrived
                  ? "You're here — slide to complete"
                  : 'Slide when you have arrived',
              enabled: !tracking.isBusy,
              onConfirmed: onArrived,
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
              // Stopping and starting are the same button in two states.
              // Stopping used to be a one-way door: a driver who stopped by
              // mistake, or who stopped while nipping into the depot, had to
              // go back to the manifest and find the stop all over again.
              Expanded(
                child: tracking.isTracking
                    ? TextButton.icon(
                        onPressed: tracking.isBusy ? null : () => onEndTrip(),
                        icon: const Icon(Icons.stop_circle_outlined, size: 18),
                        label: const Text('Stop recording'),
                      )
                    : TextButton.icon(
                        onPressed: tracking.isBusy ? null : onStartTrip,
                        icon: const Icon(Icons.play_circle_outline, size: 18),
                        label: const Text('Start recording'),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
