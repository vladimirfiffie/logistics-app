import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../data/delivery_repository.dart';
import '../models/app_settings.dart';
import '../models/delivery.dart';
import '../models/shift.dart';
import '../models/shift_break.dart';
import '../models/trip.dart';
import '../services/app_haptics.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../state/delivery_controller.dart';
import '../state/settings_controller.dart';
import '../state/shift_controller.dart';
import '../state/tracking_controller.dart';
import 'delivery_detail_sheet.dart';
import 'nfc_scan_sheet.dart';
import 'formatters.dart';
import 'settings_screen.dart';
import 'widgets/app_sheet.dart';
import 'widgets/outcome_colors.dart';
import 'widgets/page_top_inset.dart';
import 'widgets/status_chip.dart';

/// The at-a-glance screen: how the day is going, what is next, and one tap to
/// get on with it.
class HomeTab extends StatefulWidget {
  const HomeTab({
    super.key,
    required this.onTrackingStarted,
    required this.onBrowseManifest,
    required this.onOpenLive,
  });

  final VoidCallback onTrackingStarted;
  final VoidCallback onBrowseManifest;
  final VoidCallback onOpenLive;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with WidgetsBindingObserver {
  List<Trip> _trips = const [];
  Weather? _weather;
  bool _loadingWeather = false;

  /// When [_weather] was fetched. Conditions that matter to a driver — ice,
  /// fog, a squall coming through — change over a round, and the card used to
  /// be fetched once at launch and left to go stale for the rest of the day.
  DateTime? _weatherFetchedAt;

  static const _weatherFreshFor = Duration(minutes: 15);

  bool get _weatherIsStale {
    final at = _weatherFetchedAt;
    return at == null || DateTime.now().difference(at) >= _weatherFreshFor;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadTrips();
    _loadWeather();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Coming back to the app after a couple of stops is the moment a stale
  /// card is most obvious, so that is when it is worth re-checking.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _weatherIsStale) _loadWeather();
  }

  Future<void> _toggleShift() async {
    final shifts = context.read<ShiftController>();
    // A second tap while the first write is in flight would clock on twice.
    if (shifts.isBusy) return;
    if (shifts.isOnShift) {
      await _clockOff(shifts);
    } else {
      await _clockOn(shifts);
    }
  }

  /// Clocking on offers the tag as a shortcut and never requires it — the
  /// sheet always carries a "start without a tag" button, so a phone with no
  /// NFC or a van with no sticker is not a dead end. Drivers who will never
  /// use a tag can turn the prompt off entirely in Settings.
  Future<void> _clockOn(ShiftController shifts) async {
    final settings = context.read<SettingsController>().settings;

    var vehicle = settings.vehicleLabel.isEmpty ? null : settings.vehicleLabel;
    var startedByTag = false;

    if (settings.nfcClockOn) {
      final result = await NfcScanSheet.show(
        context,
        title: 'Start your shift',
        subtitle: 'Tap the tag in your van, or start without one.',
        manualLabel: 'Start without a tag',
      );
      if (result == null || !mounted) return;
      if (result case NfcSheetTag(:final tag)) {
        vehicle = tag.label;
        startedByTag = true;
      }
    }

    final started = await shifts.start(
      vehicleLabel: vehicle,
      startedByTag: startedByTag,
    );
    if (!mounted) return;

    // A failed clock-on used to be completely silent: the button did nothing
    // and the card stayed on "Not on shift".
    if (started == null) {
      await AppHaptics.error();
      if (mounted) _say('Could not clock on. ${shifts.error ?? ''}'.trim());
      return;
    }

    await AppHaptics.trackingStarted();
    if (!mounted) return;
    _say(
      'Clocked on at ${formatTime(started.startedAt)}'
      '${vehicle == null ? '' : ' · $vehicle'}.',
    );
  }

  /// Clocking off is the end of the driver's paid day, and it is one tap away
  /// from a button they press all morning — so it confirms, and it says what
  /// it is about to do to a trip that is still recording.
  Future<void> _clockOff(ShiftController shifts) async {
    final tracking = context.read<TrackingController>();
    final wasRecording = tracking.isTracking;
    final worked = formatDuration(shifts.elapsed);

    final confirmed = await showAppSheet<bool>(
      context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: 'Clock off?',
              subtitle: wasRecording
                  ? "You've been on shift for $worked. A trip is still "
                        'recording — clocking off stops it and puts that stop '
                        'back on the manifest.'
                  : "You've been on shift for $worked.",
              icon: Icons.logout,
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: () => Navigator.of(sheetContext).pop(true),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text('Clock off'),
            ),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(false),
              child: const Text('Stay on shift'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    // Leaving the GPS recording after the driver has finished their day is a
    // privacy problem, not just an untidy one.
    if (wasRecording) await tracking.stop();

    final finished = await shifts.end();
    if (!mounted) return;

    if (finished == null) {
      await AppHaptics.error();
      if (mounted) _say('Could not clock off. ${shifts.error ?? ''}'.trim());
      return;
    }

    await AppHaptics.trackingStopped();
    if (!mounted) return;
    _say('Clocked off · ${formatDuration(finished.duration)} on shift.');
  }

  /// Breaks are one tap each way. The kind is only asked for when starting
  /// one, and only because a timesheet reads better with "Lunch" on it than
  /// with three identical rows.
  Future<void> _toggleBreak() async {
    final shifts = context.read<ShiftController>();
    if (shifts.isBusy) return;

    if (shifts.isOnBreak) {
      await _endBreak(shifts);
      return;
    }

    final kind = await showAppSheet<BreakKind>(
      context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SheetHeader(
                title: 'Take a break',
                subtitle:
                    'The shift clock keeps running; the break is subtracted '
                    'from your worked hours.',
                icon: Icons.free_breakfast_outlined,
              ),
            ),
            for (final kind in BreakKind.values)
              ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(kind.detail),
                onTap: () => Navigator.of(sheetContext).pop(kind),
              ),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;

    final started = await shifts.startBreak(kind: kind);
    await AppHaptics.trackingStopped();
    if (!mounted) return;
    _say(
      started == null
          ? 'Could not start a break.'
          : '${kind.detail} started. The clock is paused.',
    );
  }

  /// Going back on the clock confirms the same way clocking off does. It is
  /// the same one-tap button either way, and a break ended by accident is not
  /// something the driver can put back — the minutes are already on the
  /// timesheet.
  Future<void> _endBreak(ShiftController shifts) async {
    final taken = formatDuration(
      shifts.currentBreak?.duration ?? Duration.zero,
    );

    final confirmed = await showAppSheet<bool>(
      context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: 'Back to work?',
              subtitle:
                  "You've been on a break for $taken. It stops counting the "
                  'moment you tap, and the time already taken stays on your '
                  'timesheet.',
              icon: Icons.play_arrow,
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: () => Navigator.of(sheetContext).pop(true),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text('Back to work'),
            ),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(false),
              child: const Text('Stay on break'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final finished = await shifts.endBreak();
    await AppHaptics.trackingStarted();
    if (!mounted) return;
    _say(
      finished == null
          ? 'Could not end the break.'
          : 'Back on the clock · ${formatDuration(finished.duration)} break.',
    );
  }

  void _say(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  /// Best-effort. Uses the cached fix rather than requesting a fresh one — a
  /// weather card is not worth waking the GPS for, and it must never prompt
  /// for permission on the home screen.
  Future<void> _loadWeather({bool force = false}) async {
    if (!mounted || _loadingWeather) return;
    final settings = context.read<SettingsController>().settings;
    if (!settings.showWeather) {
      setState(() {
        _weather = null;
        _weatherFetchedAt = null;
      });
      return;
    }
    if (!force && !_weatherIsStale) return;

    setState(() => _loadingWeather = true);
    try {
      // Resolved up front: reading providers after an await is exactly the
      // case the lint is warning about.
      final location = context.read<LocationService>();
      final service = context.read<WeatherService>();

      if (await location.currentReadiness() != LocationReadiness.ready) return;
      final fix =
          await location.lastKnownPosition() ??
          await location.currentPosition();
      final weather = await service.current(
        latitude: fix.latitude,
        longitude: fix.longitude,
      );
      if (mounted && weather != null) {
        setState(() {
          _weather = weather;
          // Stamped only on success, so a failed fetch is retried on the next
          // resume rather than being treated as fifteen minutes of fresh data.
          _weatherFetchedAt = DateTime.now();
        });
      }
    } catch (_) {
      // No fix, or no network. The card simply does not appear.
    } finally {
      if (mounted) setState(() => _loadingWeather = false);
    }
  }

  Future<void> _loadTrips() async {
    final trips = await context.read<DeliveryRepository>().fetchTrips();
    if (mounted) setState(() => _trips = trips);
  }

  double get _distanceToday =>
      _trips.fold(0.0, (sum, trip) => sum + trip.distanceMeters);

  Duration get _drivingToday => _trips
      .where((trip) => !trip.isActive)
      .fold(Duration.zero, (sum, trip) => sum + trip.duration);

  /// The stop to do next: whatever is already in transit, otherwise the
  /// earliest pending slot.
  Delivery? _nextStop(DeliveryController controller) {
    final open = controller.openStops;
    if (open.isEmpty) return null;
    for (final stop in open) {
      if (stop.status == DeliveryStatus.inTransit) return stop;
    }
    final sorted = [...open]
      ..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));
    return sorted.first;
  }

  String _greeting(String name) {
    final hour = DateTime.now().hour;
    final part = hour < 12
        ? 'Good morning'
        : hour < 18
        ? 'Good afternoon'
        : 'Good evening';
    return name.isEmpty ? part : '$part, $name';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = context.watch<DeliveryController>();
    final settings = context.appSettings;
    final unit = settings.distanceUnit;
    final isTracking = context.select<TrackingController, bool>(
      (tracking) => tracking.isTracking,
    );

    final open = controller.openStops;
    final closed = controller.closedStops;
    final total = open.length + closed.length;
    final done = closed.length;
    final next = _nextStop(controller);

    // Built once here rather than inside itemBuilder, which rebuilt the whole
    // filtered list for every row it drew.
    final upcoming = [
      for (final stop in open)
        if (stop.id != next?.id) stop,
    ];

    return RefreshIndicator(
      onRefresh: () async {
        // An explicit pull always refetches, whatever the cache says.
        await Future.wait([
          controller.refresh(),
          _loadTrips(),
          _loadWeather(force: true),
        ]);
      },
      child: CustomScrollView(
        slivers: [
          const SliverStatusBarInset(),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _greeting(settings.driverName),
                    // Matches the page title above it: the greeting is the
                    // other half of the header, not a caption under it.
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      formatDate(DateTime.now()),
                      if (settings.vehicleLabel.isNotEmpty)
                        settings.vehicleLabel,
                    ].join(' · '),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms).moveY(begin: 8),
          ),

          SliverToBoxAdapter(
            child: _DriverTile(
              name: settings.driverName,
              vehicleLabel: settings.vehicleLabel,
              onOpenSettings: () => SettingsScreen.show(context),
            ).animate().fadeIn(delay: 20.ms, duration: 300.ms),
          ),

          if (settings.showWeather && (_weather != null || _loadingWeather))
            SliverToBoxAdapter(
              child: _WeatherCard(
                weather: _weather,
                settings: settings,
              ).animate().fadeIn(delay: 60.ms, duration: 320.ms),
            ),

          // Consumer rather than a watch up in this build method: the shift
          // clock ticks every second, and only this card needs to redraw for
          // it.
          SliverToBoxAdapter(
            child: Consumer<ShiftController>(
              builder: (context, shifts, _) => _ShiftCard(
                shifts: shifts,
                onToggle: _toggleShift,
                onToggleBreak: _toggleBreak,
              ),
            ).animate().fadeIn(delay: 40.ms, duration: 300.ms),
          ),

          SliverToBoxAdapter(
            child: _ProgressCard(
              done: done,
              total: total,
              parcels: controller.remainingParcels,
            ).animate().fadeIn(delay: 80.ms, duration: 320.ms).moveY(begin: 12),
          ),

          SliverToBoxAdapter(
            child:
                Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: Row(
                        children: [
                          _MiniStat(
                            icon: Icons.route_outlined,
                            label: 'Driven',
                            value: formatDistance(_distanceToday, unit: unit),
                          ),
                          _MiniStat(
                            icon: Icons.timer_outlined,
                            label: 'Driving',
                            value: formatDuration(_drivingToday),
                          ),
                          _MiniStat(
                            icon: Icons.inventory_2_outlined,
                            label: 'Parcels',
                            value: '${controller.remainingParcels}',
                          ),
                        ],
                      ),
                    )
                    .animate()
                    .fadeIn(delay: 160.ms, duration: 320.ms)
                    .moveY(begin: 12),
          ),

          SliverToBoxAdapter(
            child:
                (next == null
                        ? _AllDoneCard(onViewHistory: widget.onBrowseManifest)
                        : _NextStopCard(
                            delivery: next,
                            isTracking: isTracking,
                            onOpen: () async {
                              final started = await showDeliveryDetail(
                                context,
                                next.id,
                              );
                              await _loadTrips();
                              if (started ?? false) widget.onTrackingStarted();
                            },
                            onOpenLive: widget.onOpenLive,
                          ))
                    .animate()
                    .fadeIn(delay: 240.ms, duration: 320.ms)
                    .moveY(begin: 12),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'COMING UP',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),

          if (open.length <= 1)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Text(
                  'Nothing else queued.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: upcoming.length,
              itemBuilder: (context, index) {
                final stop = upcoming[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    child: Text(
                      // Position in the day's run, not position in this list.
                      // The next-stop card is whichever stop is in transit,
                      // which is often not the first one — numbering from 2
                      // here told the driver stop 1 was stop 2.
                      '${open.indexOf(stop) + 1}',
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                  title: Text(
                    stop.customerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${formatTime(stop.scheduledFor)} · ${stop.address}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: StatusChip(stop.status, dense: true),
                  onTap: () async {
                    await showDeliveryDetail(context, stop.id);
                    await _loadTrips();
                  },
                ).animate().fadeIn(
                  delay: (300 + index * 60).ms,
                  duration: 260.ms,
                );
              },
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.done,
    required this.total,
    required this.parcels,
  });

  final int done;
  final int total;
  final int parcels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = total == 0 ? 0.0 : done / total;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Card(
        elevation: 0,
        color: scheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              SizedBox(
                width: 76,
                height: 76,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Tween rather than a static value so the ring fills in
                    // when the screen appears, which makes progress legible
                    // at a glance.
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: progress),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) => SizedBox(
                        width: 76,
                        height: 76,
                        child: CircularProgressIndicator(
                          value: value,
                          strokeWidth: 8,
                          backgroundColor: scheme.onPrimaryContainer.withValues(
                            alpha: 0.15,
                          ),
                          valueColor: AlwaysStoppedAnimation(
                            scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                    Text(
                      total == 0 ? '—' : '${(progress * 100).round()}%',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$done of $total done',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      parcels == 0
                          ? 'Van empty.'
                          : '$parcels ${parcels == 1 ? 'parcel' : 'parcels'} '
                                'still on board',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onPrimaryContainer.withValues(
                          alpha: 0.85,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The way into Settings, and the only one — the gear icon that used to sit in
/// every app bar is gone. A row that names the driver and the van earns its
/// place on the screen in a way a bare icon does not, and it doubles as the
/// prompt to fill those two fields in when they are still empty.
class _DriverTile extends StatelessWidget {
  const _DriverTile({
    required this.name,
    required this.vehicleLabel,
    required this.onOpenSettings,
  });

  final String name;
  final String vehicleLabel;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final identified = [
      if (name.isNotEmpty) name,
      if (vehicleLabel.isNotEmpty) vehicleLabel,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Card(
        elevation: 0,
        color: scheme.surfaceContainerHighest,
        child: InkWell(
          onTap: () {
            AppHaptics.select();
            onOpenSettings();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(
                    Icons.person_outline,
                    size: 20,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        identified.isEmpty ? 'Set up your details' : identified,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        identified.isEmpty
                            ? 'Your name, van, units and everything else'
                            : 'Settings and preferences',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Clock on and off. Shown above everything else because it is the first and
/// last thing a driver does, and because "am I on the clock?" should never
/// need looking for.
class _ShiftCard extends StatelessWidget {
  const _ShiftCard({
    required this.shifts,
    required this.onToggle,
    required this.onToggleBreak,
  });

  final ShiftController shifts;
  final VoidCallback onToggle;
  final VoidCallback onToggleBreak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = shifts.isOnShift;
    final shift = shifts.current;
    final onBreak = shifts.isOnBreak;

    // A break is a third state, and it has to be unmistakable: a driver
    // glancing at this card needs to know whether the clock is running.
    final surface = !on
        ? scheme.surfaceContainerHighest
        : onBreak
        ? scheme.secondaryContainer
        : scheme.tertiaryContainer;
    final onSurface = !on
        ? scheme.onSurfaceVariant
        : onBreak
        ? scheme.onSecondaryContainer
        : scheme.onTertiaryContainer;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Card(
        elevation: 0,
        color: surface,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    !on
                        ? Icons.play_circle_outline
                        : onBreak
                        ? Icons.free_breakfast_outlined
                        : Icons.timer_outlined,
                    color: onSurface,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          !on
                              ? 'Not on shift'
                              : onBreak
                              ? 'On a break'
                              : 'On shift',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: on ? onSurface : null,
                          ),
                        ),
                        Text(
                          switch ((on, shift)) {
                            (true, final Shift current) => [
                              // Worked time, not wall-clock: a break should be
                              // visible in the number, not only in the colour.
                              formatDuration(shifts.workedElapsed),
                              if (shifts.breakElapsed > Duration.zero)
                                '${formatDuration(shifts.breakElapsed)} break',
                              if (current.vehicleLabel case final String van)
                                van,
                              if (current.startedByTag) 'tag',
                            ].join(' · '),
                            _ => 'Tap your van tag, or start without one.',
                          },
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: on ? onSurface : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  shifts.isBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : FilledButton(
                          onPressed: onToggle,
                          style: FilledButton.styleFrom(
                            backgroundColor: on ? scheme.error : scheme.primary,
                            foregroundColor: on
                                ? scheme.onError
                                : scheme.onPrimary,
                          ),
                          child: Text(on ? 'Clock off' : 'Clock on'),
                        ),
                ],
              ),

              // Only while clocked on: there is nothing to take a break from
              // otherwise.
              if (on) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: shifts.isBusy ? null : onToggleBreak,
                    icon: Icon(
                      onBreak
                          ? Icons.play_arrow
                          : Icons.free_breakfast_outlined,
                      size: 18,
                    ),
                    label: Text(onBreak ? 'Back to work' : 'Take a break'),
                    style: TextButton.styleFrom(foregroundColor: onSurface),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Driving conditions. Deliberately compact — it is context, not the point of
/// the screen — but a warning promotes itself to a full line because ice or
/// fog changes how the round should be driven.
class _WeatherCard extends StatelessWidget {
  const _WeatherCard({required this.weather, required this.settings});

  final Weather? weather;

  /// Taken whole rather than as four resolved units: the card reads four of
  /// them and the settings object already knows how to resolve "match my
  /// units" for each.
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final current = weather;

    if (current == null) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: SizedBox(
          height: 52,
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    final warning = current.drivingWarning;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Card(
        elevation: 0,
        color: warning == null
            ? scheme.surfaceContainerHighest
            : scheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    current.icon,
                    size: 26,
                    color: warning == null
                        ? scheme.onSurfaceVariant
                        : scheme.onErrorContainer,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    formatTemperature(
                      current.temperatureC,
                      fahrenheit: settings.usesFahrenheit,
                    ),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: warning == null ? null : scheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      [
                        current.description,
                        '${formatWindSpeed(current.windKph, unit: settings.resolvedWindUnit)} wind',
                        'feels ${formatTemperature(current.feelsLikeC, fahrenheit: settings.usesFahrenheit)}',
                        // Only when there is actually something falling.
                        if (current.precipitationMm > 0)
                          formatPrecipitation(
                            current.precipitationMm,
                            unit: settings.resolvedPrecipitationUnit,
                          ),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: warning == null
                            ? scheme.onSurfaceVariant
                            : scheme.onErrorContainer,
                      ),
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
              if (warning != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: scheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        warning,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _NextStopCard extends StatelessWidget {
  const _NextStopCard({
    required this.delivery,
    required this.isTracking,
    required this.onOpen,
    required this.onOpenLive,
  });

  final Delivery delivery;
  final bool isTracking;
  final VoidCallback onOpen;
  final VoidCallback onOpenLive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final live = delivery.status == DeliveryStatus.inTransit && isTracking;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    live ? 'ON THE WAY' : 'UP NEXT',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  StatusChip(delivery.status, dense: true),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                delivery.customerName,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                delivery.address,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${delivery.reference} · ${formatTime(delivery.scheduledFor)} '
                '· ${delivery.parcelCount} '
                '${delivery.parcelCount == 1 ? 'parcel' : 'parcels'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: live ? onOpenLive : onOpen,
                icon: Icon(live ? Icons.radar : Icons.arrow_forward),
                label: Text(live ? 'Open live tracking' : 'Open stop'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AllDoneCard extends StatelessWidget {
  const _AllDoneCard({required this.onViewHistory});

  final VoidCallback onViewHistory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Card(
        elevation: 0,
        color: context.deliveredContainer,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(
                Icons.task_alt,
                size: 34,
                color: context.onDeliveredContainer,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Round complete',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.onDeliveredContainer,
                      ),
                    ),
                    Text(
                      'Every stop is closed out.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.onDeliveredContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
