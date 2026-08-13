import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../data/delivery_repository.dart';
import '../data/seed_data.dart';
import '../models/app_settings.dart';
import '../models/delivery.dart';
import '../services/app_haptics.dart';
import '../services/location_service.dart';
import '../services/route_planner.dart';
import '../state/delivery_controller.dart';
import '../state/settings_controller.dart';
import 'barcode_scan_sheet.dart';
import 'delivery_detail_sheet.dart';
import 'formatters.dart';
import 'widgets/app_sheet.dart';
import 'widgets/delivery_card.dart';
import 'widgets/page_top_inset.dart';

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

  /// Null until the first build reads the driver's default. Held here rather
  /// than in settings so changing it for one round is not a permanent change.
  StopSort? _sort;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _refreshFix();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Matches reference, customer or address. Six stops need no search; fifty
  /// do, and the stop generator exists precisely to get to fifty.
  List<Delivery> _filtered(List<Delivery> stops) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return stops;
    return [
      for (final stop in stops)
        if (stop.reference.toLowerCase().contains(query) ||
            stop.customerName.toLowerCase().contains(query) ||
            stop.address.toLowerCase().contains(query))
          stop,
    ];
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

  StopSort _sortMode(BuildContext context) =>
      _sort ?? context.read<SettingsController>().settings.defaultSort;

  List<Delivery> _sorted(List<Delivery> stops) {
    final fix = _fix;
    final sort = _sortMode(context);
    final list = [...stops];

    // Resolved once here rather than per comparison: `_distanceTo` reaches
    // through a provider, and a sort calls its comparator O(n log n) times.
    final location = context.read<LocationService>();

    switch (sort) {
      // Both distance modes fall back to time when there is no fix to measure
      // from, which is also why their chips are disabled in that state.
      case StopSort.distance when fix != null:
        final byId = {
          for (final stop in list)
            stop.id: location.distanceBetween(
              fix.latitude,
              fix.longitude,
              stop.latitude,
              stop.longitude,
            ),
        };
        list.sort((a, b) => byId[a.id]!.compareTo(byId[b.id]!));
      case StopSort.route when fix != null:
        return planRoute(
          list,
          fromLatitude: fix.latitude,
          fromLongitude: fix.longitude,
          distanceBetween: location.distanceBetween,
        );
      case StopSort.name:
        list.sort(
          (a, b) => a.customerName.toLowerCase().compareTo(
            b.customerName.toLowerCase(),
          ),
        );
      case _:
        list.sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));
    }
    return list;
  }

  /// How much shorter the suggested route is than working down the time slots.
  /// Shown so the driver can judge whether to bother, rather than being told
  /// to trust it.
  double? get _routeSaving {
    final fix = _fix;
    if (fix == null || _sortMode(context) != StopSort.route) return null;

    final open = context.read<DeliveryController>().openStops;
    final stops = _filtered(open);
    if (stops.length < 3) return null;

    final location = context.read<LocationService>();
    final byTime = [...stops]
      ..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));

    double measure(List<Delivery> order) => routeLength(
      order,
      fromLatitude: fix.latitude,
      fromLongitude: fix.longitude,
      distanceBetween: location.distanceBetween,
    );

    final saving = measure(byTime) - measure(_sorted(stops));
    return saving <= 0 ? null : saving;
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

  /// Scan a parcel, land on its stop.
  ///
  /// The way a driver actually finds work: they are holding a box, not
  /// looking at a list. A label that is not on the manifest says so plainly
  /// rather than opening the nearest-looking stop, and a stop already closed
  /// out opens anyway — "that one went this morning" is exactly the question
  /// being asked when someone scans a parcel they did not expect to still
  /// have.
  Future<void> _scanForStop() async {
    final code = await BarcodeScanSheet.findStop(context);
    if (code == null || !mounted) return;

    final deliveries = context.read<DeliveryController>();
    final messenger = ScaffoldMessenger.of(context);
    final found = await deliveries.findByBarcode(code);

    if (!mounted) return;
    if (found == null) {
      await AppHaptics.error();
      messenger.showSnackBar(
        SnackBar(
          content: Text('No stop on this manifest carries the label $code.'),
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    if (!found.status.isOpen) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${found.reference} is already closed out '
            '(${found.status.label.toLowerCase()}).',
          ),
        ),
      );
    }
    await _open(found);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DeliveryController>();
    final open = controller.openStops;
    final stops = _sorted(_filtered(open));
    final sort = _sortMode(context);
    final saving = _routeSaving;
    final searching = _query.trim().isNotEmpty;

    return Scaffold(
      // The list is the whole page, so "add stops" belongs on a button over it
      // rather than as a third icon competing for the app bar.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addStops,
        icon: const Icon(Icons.add_road),
        label: const Text('Add stops'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([controller.refresh(), _refreshFix()]);
        },
        child: CustomScrollView(
          slivers: [
            const SliverStatusBarInset(),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SearchBar(
                  controller: _searchController,
                  hintText: 'Search reference, customer or street',
                  leading: const Icon(Icons.search),
                  trailing: [
                    if (searching)
                      IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear search',
                      ),
                    // Next to the search field on purpose: scanning a label
                    // and typing a reference are the same job done two ways,
                    // and one hand is usually holding a parcel.
                    IconButton(
                      onPressed: _scanForStop,
                      icon: const Icon(Icons.qr_code_scanner),
                      tooltip: 'Scan a parcel label',
                    ),
                  ],
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: _SortChips(
                selected: sort,
                fixEnabled: _fix != null,
                onChanged: (mode) {
                  AppHaptics.select();
                  setState(() => _sort = mode);
                },
              ),
            ),

            if (saving != null)
              SliverToBoxAdapter(
                child: _RouteSavingBanner(
                  saving: saving,
                  unit: context.distanceUnit,
                ),
              ),

            if (!searching)
              SliverToBoxAdapter(
                child: _RunSummary(
                  stopsRemaining: stops.length,
                  parcelsRemaining: controller.remainingParcels,
                  completed: controller.closedStops.length,
                  hasFix: _fix != null,
                ),
              )
            else
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    '${stops.length} of ${open.length} '
                    '${open.length == 1 ? 'stop' : 'stops'} match "$_query"',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
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
            else if (stops.isEmpty && searching)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _Message(
                  icon: Icons.search_off,
                  title: 'No match',
                  detail:
                      'Nothing on the run matches "$_query". Closed stops are '
                      'in History.',
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

            // Clears the extended FAB at the end of the list.
            const SliverToBoxAdapter(child: SizedBox(height: 88)),
          ],
        ),
      ),
    );
  }
}

/// Sort control, moved out of the app bar. Few enough options to show all of
/// them, which beats a menu that hides the current choice behind an icon.
class _SortChips extends StatelessWidget {
  const _SortChips({
    required this.selected,
    required this.fixEnabled,
    required this.onChanged,
  });

  final StopSort selected;
  final bool fixEnabled;
  final ValueChanged<StopSort> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Row(
        children: [
          for (final mode in StopSort.values) ...[
            ChoiceChip(
              label: Text(mode.label),
              avatar: Icon(mode.icon, size: 17),
              selected: selected == mode,
              // Distance and route both measure from the driver.
              onSelected: mode.needsFix && !fixEnabled
                  ? null
                  : (_) => onChanged(mode),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// Says what the suggested order buys, in the driver's own units. Without a
/// number, "best route" is just a claim.
class _RouteSavingBanner extends StatelessWidget {
  const _RouteSavingBanner({required this.saving, required this.unit});

  final double saving;
  final DistanceUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Card(
        elevation: 0,
        color: scheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                Icons.alt_route,
                size: 18,
                color: scheme.onTertiaryContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'About ${formatDistance(saving, unit: unit)} shorter than '
                  'working straight down the list. Your time slots are kept '
                  'in order — this only reorders stops booked for the same '
                  'window. Straight-line estimate; the roads still win.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onTertiaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
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
