import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../data/delivery_repository.dart';
import '../data/seed_data.dart';
import '../models/delivery.dart';
import '../services/app_haptics.dart';
import '../services/location_service.dart';
import '../state/delivery_controller.dart';
import 'delivery_detail_sheet.dart';
import 'settings_screen.dart';
import 'widgets/app_sheet.dart';
import 'widgets/delivery_card.dart';

enum _SortMode {
  time('By time', Icons.schedule),
  distance('By distance', Icons.near_me_outlined);

  const _SortMode(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// The driver's run for the day: every stop still to be done.
class ManifestTab extends StatefulWidget {
  const ManifestTab({super.key, required this.onTrackingStarted});

  /// Fired when a stop on this list starts recording, so the shell can jump to
  /// the live view.
  final VoidCallback onTrackingStarted;

  @override
  State<ManifestTab> createState() => _ManifestTabState();
}

class _ManifestTabState extends State<ManifestTab> {
  Position? _fix;
  _SortMode _sort = _SortMode.time;

  @override
  void initState() {
    super.initState();
    _refreshFix();
  }

  /// Distances on the cards are a convenience, not the tracking feature — so
  /// we take the cached fix if there is one and never block the list on it.
  Future<void> _refreshFix() async {
    final location = context.read<LocationService>();
    try {
      final cached = await location.lastKnownPosition();
      if (mounted && cached != null) setState(() => _fix = cached);
      if (await location.ensureReady() != LocationReadiness.ready) return;
      final fresh = await location.currentPosition();
      if (mounted) setState(() => _fix = fresh);
    } catch (_) {
      // No fix available; the cards simply omit the distance column.
    }
  }

  double? _distanceTo(Delivery delivery) {
    final fix = _fix;
    if (fix == null) return null;
    return context.read<LocationService>().distanceBetween(
      fix.latitude,
      fix.longitude,
      delivery.latitude,
      delivery.longitude,
    );
  }

  List<Delivery> _sorted(List<Delivery> stops) {
    final list = [...stops];
    if (_sort == _SortMode.distance && _fix != null) {
      list.sort((a, b) => (_distanceTo(a) ?? 0).compareTo(_distanceTo(b) ?? 0));
    } else {
      list.sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));
    }
    return list;
  }

  /// Generates extra work to test against.
  ///
  /// Stands in for a dispatch backend: without one there is no way to get a
  /// bigger round than the six stops the first run seeds.
  Future<void> _addStops() async {
    final count = await showAppSheet<int>(
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
                title: 'Add stops',
                subtitle:
                    'Generates extra deliveries around you. There is no '
                    'dispatch backend yet, so this is how you get a bigger '
                    'round to work with.',
                icon: Icons.add_road,
              ),
            ),
            for (final option in const [5, 10, 25])
              ListTile(
                leading: const Icon(Icons.local_shipping_outlined),
                title: Text('Add $option stops'),
                onTap: () => Navigator.of(sheetContext).pop(option),
              ),
          ],
        ),
      ),
    );

    if (count == null || !mounted) return;

    final repository = context.read<DeliveryRepository>();
    final deliveries = context.read<DeliveryController>();
    final fix = _fix;

    final created = await SeedData.addStops(
      repository,
      count: count,
      origin: fix == null ? null : LatLng(fix.latitude, fix.longitude),
    );
    await deliveries.refresh();
    await AppHaptics.delivered();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Added ${created.length} stops '
          '(${created.first.reference}–${created.last.reference}).',
        ),
      ),
    );
  }

  Future<void> _open(Delivery delivery) async {
    final startedTracking = await showDeliveryDetail(context, delivery.id);
    if (startedTracking ?? false) widget.onTrackingStarted();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DeliveryController>();
    final stops = _sorted(controller.openStops);

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([controller.refresh(), _refreshFix()]);
      },
      child: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text("Today's run"),
            actions: [
              IconButton(
                onPressed: _addStops,
                icon: const Icon(Icons.add_road),
                tooltip: 'Add more stops',
              ),
              IconButton(
                onPressed: () => SettingsScreen.show(context),
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
              ),
              PopupMenuButton<_SortMode>(
                initialValue: _sort,
                icon: const Icon(Icons.sort),
                tooltip: 'Sort stops',
                onSelected: (mode) {
                  AppHaptics.select();
                  setState(() => _sort = mode);
                },
                itemBuilder: (_) => [
                  for (final mode in _SortMode.values)
                    PopupMenuItem(
                      value: mode,
                      enabled: mode != _SortMode.distance || _fix != null,
                      child: Row(
                        children: [
                          Icon(mode.icon, size: 18),
                          const SizedBox(width: 10),
                          Text(mode.label),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),

          SliverToBoxAdapter(
            child: _RunSummary(
              stopsRemaining: stops.length,
              parcelsRemaining: controller.remainingParcels,
              completed: controller.closedStops.length,
              hasFix: _fix != null,
            ),
          ),

          if (controller.isLoading && stops.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (controller.error case final Object error)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _Message(
                icon: Icons.error_outline,
                title: 'Could not load the manifest',
                detail: '$error',
              ),
            )
          else if (stops.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _Message(
                icon: Icons.task_alt,
                title: 'Run complete',
                detail: 'Every stop on the manifest has been closed out.',
              ),
            )
          else
            SliverList.builder(
              itemCount: stops.length,
              itemBuilder: (context, index) {
                final delivery = stops[index];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: DeliveryCard(
                    delivery: delivery,
                    distanceMeters: _distanceTo(delivery),
                    onTap: () => _open(delivery),
                  ),
                );
              },
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _RunSummary extends StatelessWidget {
  const _RunSummary({
    required this.stopsRemaining,
    required this.parcelsRemaining,
    required this.completed,
    required this.hasFix,
  });

  final int stopsRemaining;
  final int parcelsRemaining;
  final int completed;
  final bool hasFix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = stopsRemaining + completed;
    final progress = total == 0 ? 0.0 : completed / total;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$completed of $total stops done',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Icon(
                hasFix ? Icons.gps_fixed : Icons.gps_off,
                size: 15,
                color: hasFix
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(
                hasFix ? 'GPS locked' : 'No fix',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: hasFix
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(value: progress, minHeight: 7),
          ),
          const SizedBox(height: 8),
          Text(
            '$parcelsRemaining ${parcelsRemaining == 1 ? 'parcel' : 'parcels'} '
            'still on the van',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 14),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
