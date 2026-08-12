import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../data/delivery_repository.dart';
import '../models/app_settings.dart';
import '../models/delivery.dart';
import '../models/shift.dart';
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

class _HomeTabState extends State<HomeTab> {
  List<Trip> _trips = const [];
  Weather? _weather;
  bool _loadingWeather = false;

  @override
  void initState() {
    super.initState();
    _loadTrips();
    _loadWeather();
  }

  /// Clocking on offers the tag as a shortcut and never requires it — the
  /// sheet always carries a "start without a tag" button, so a phone with no
  /// NFC or a van with no sticker is not a dead end.
  Future<void> _toggleShift() async {
    final shifts = context.read<ShiftController>();
    final settings = context.read<SettingsController>().settings;

    if (shifts.isOnShift) {
      await shifts.end();
      await AppHaptics.trackingStopped();
      return;
    }

    final result = await NfcScanSheet.show(
      context,
      title: 'Start your shift',
      subtitle: 'Tap the tag in your van, or start without one.',
      manualLabel: 'Start without a tag',
    );
    if (result == null || !mounted) return;

    final vehicle = switch (result) {
      NfcSheetTag(:final tag) => tag.label,
      NfcSheetManual() =>
        settings.vehicleLabel.isEmpty ? null : settings.vehicleLabel,
    };

    final started = await shifts.start(
      vehicleLabel: vehicle,
      startedByTag: result is NfcSheetTag,
    );
    if (started != null) await AppHaptics.trackingStarted();
  }

  /// Best-effort. Uses the cached fix rather than requesting a fresh one — a
  /// weather card is not worth waking the GPS for, and it must never prompt
  /// for permission on the home screen.
  Future<void> _loadWeather() async {
    if (!mounted) return;
    final settings = context.read<SettingsController>().settings;
    if (!settings.showWeather) {
      setState(() => _weather = null);
      return;
    }

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
      if (mounted) setState(() => _weather = weather);
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

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([controller.refresh(), _loadTrips(), _loadWeather()]);
      },
      child: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('Home'),
            actions: [
              IconButton(
                onPressed: () => SettingsScreen.show(context),
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
              ),
              const SizedBox(width: 4),
            ],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _greeting(settings.driverName),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    [
                      formatDate(DateTime.now()),
                      if (settings.vehicleLabel.isNotEmpty)
                        settings.vehicleLabel,
                    ].join(' · '),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms).moveY(begin: 8),
          ),

          if (settings.showWeather && (_weather != null || _loadingWeather))
            SliverToBoxAdapter(
              child: _WeatherCard(
                weather: _weather,
                unit: unit,
                isLoading: _loadingWeather,
              ).animate().fadeIn(delay: 60.ms, duration: 320.ms),
            ),

          SliverToBoxAdapter(
            child: _ShiftCard(
              shifts: context.watch<ShiftController>(),
              onToggle: _toggleShift,
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
              // Skips the stop already shown in the next-stop card above.
              itemCount: open.length - 1,
              itemBuilder: (context, index) {
                final upcoming = open
                    .where((stop) => stop.id != next?.id)
                    .toList();
                if (index >= upcoming.length) return null;
                final stop = upcoming[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    child: Text(
                      '${index + 2}',
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

/// Clock on and off. Shown above everything else because it is the first and
/// last thing a driver does, and because "am I on the clock?" should never
/// need looking for.
class _ShiftCard extends StatelessWidget {
  const _ShiftCard({required this.shifts, required this.onToggle});

  final ShiftController shifts;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = shifts.isOnShift;
    final shift = shifts.current;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Card(
        elevation: 0,
        color: on ? scheme.tertiaryContainer : scheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                on ? Icons.timer_outlined : Icons.play_circle_outline,
                color: on
                    ? scheme.onTertiaryContainer
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      on ? 'On shift' : 'Not on shift',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: on ? scheme.onTertiaryContainer : null,
                      ),
                    ),
                    Text(
                      switch ((on, shift)) {
                        (true, final Shift current) => [
                          formatDuration(current.duration),
                          if (current.vehicleLabel case final String van) van,
                          if (current.startedByTag) 'tag',
                        ].join(' · '),
                        _ => 'Tap your van tag, or start without one.',
                      },
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: on
                            ? scheme.onTertiaryContainer
                            : scheme.onSurfaceVariant,
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
                        foregroundColor: on ? scheme.onError : scheme.onPrimary,
                      ),
                      child: Text(on ? 'Clock off' : 'Clock on'),
                    ),
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
  const _WeatherCard({
    required this.weather,
    required this.unit,
    required this.isLoading,
  });

  final Weather? weather;
  final DistanceUnit unit;
  final bool isLoading;

  String _temperature(double celsius) {
    if (unit == DistanceUnit.imperial) {
      return '${(celsius * 9 / 5 + 32).round()}°F';
    }
    return '${celsius.round()}°C';
  }

  String _wind(double kph) {
    if (unit == DistanceUnit.imperial) {
      return '${(kph / 1.609344).round()} mph wind';
    }
    return '${kph.round()} km/h wind';
  }

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
                    _temperature(current.temperatureC),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: warning == null ? null : scheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${current.description} · '
                      '${_wind(current.windKph)}',
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
        color: theme.colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(
                Icons.task_alt,
                size: 34,
                color: theme.colorScheme.onTertiaryContainer,
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
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                    Text(
                      'Every stop is closed out.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
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
