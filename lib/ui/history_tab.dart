import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../data/delivery_repository.dart';
import '../models/delivery.dart';
import '../models/trip.dart';
import '../services/app_haptics.dart';
import '../state/delivery_controller.dart';
import '../state/settings_controller.dart';
import 'delivery_detail_sheet.dart';
import 'formatters.dart';
import 'widgets/outcome_colors.dart';
import 'widgets/page_top_inset.dart';
import 'widgets/status_chip.dart';

/// Closed-out stops and the distance recorded getting to them.
///
/// Laid out like the home tab rather than like a database table: a headline
/// card for how the day went, the same mini-stat row, then the stops grouped
/// by day. A driver comes here to answer "did that one go through?", so the
/// outcome is the loudest thing on every row.
class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

/// How far back the history list reaches.
enum _Period {
  any('Any time'),
  today('Today'),
  week('This week'),
  month('This month');

  const _Period(this.label);

  final String label;

  /// Midnight on the earliest day this period includes, or null for all of it.
  DateTime? startFrom(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      _Period.any => null,
      _Period.today => today,
      // The working week, starting Monday — the same week the timesheet pays
      // by, so the two screens agree about what "this week" means.
      _Period.week => today.subtract(Duration(days: today.weekday - 1)),
      _Period.month => DateTime(now.year, now.month),
    };
  }
}

class _HistoryTabState extends State<HistoryTab> {
  List<Trip> _trips = const [];

  final _searchController = TextEditingController();
  String _query = '';
  _Period _period = _Period.any;

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Same fields the manifest searches, so one habit works on both screens.
  bool _matchesQuery(Delivery stop) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    return stop.reference.toLowerCase().contains(query) ||
        stop.customerName.toLowerCase().contains(query) ||
        stop.address.toLowerCase().contains(query) ||
        (stop.recipientName?.toLowerCase().contains(query) ?? false) ||
        (stop.barcode?.toLowerCase().contains(query) ?? false);
  }

  bool _matchesPeriod(Delivery stop) {
    final from = _period.startFrom(DateTime.now());
    if (from == null) return true;
    final at = stop.completedAt;
    // A stop with no completion time cannot be placed in a period, so it only
    // shows when no period is asked for.
    return at != null && !at.isBefore(from);
  }

  Future<void> _loadTrips() async {
    final trips = await context.read<DeliveryRepository>().fetchTrips();
    if (mounted) setState(() => _trips = trips);
  }

  double get _totalDistance =>
      _trips.fold(0.0, (sum, trip) => sum + trip.distanceMeters);

  Duration get _totalDriving => _trips
      .where((trip) => !trip.isActive)
      .fold(Duration.zero, (sum, trip) => sum + trip.duration);

  /// Built once per load rather than searched per row: the list is O(closed)
  /// and the old lookup made it O(closed × trips).
  Map<String, Trip> get _tripsByDelivery => {
    for (final trip in _trips) trip.deliveryId: trip,
  };

  /// Midnight on the day [when] falls in — the key the rows group under.
  static DateTime _dayOf(DateTime when) =>
      DateTime(when.year, when.month, when.day);

  /// "Today", "Yesterday", or the date. A driver reading this at four in the
  /// afternoon should not have to work out what today's date is.
  static String _dayLabel(DateTime day) {
    final today = _dayOf(DateTime.now());
    final difference = today.difference(day).inDays;
    return switch (difference) {
      0 => 'Today',
      1 => 'Yesterday',
      _ => formatDate(day),
    };
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DeliveryController>();
    final closed = controller.closedStops;
    final delivered = closed
        .where((stop) => stop.status == DeliveryStatus.delivered)
        .length;
    final failed = closed.length - delivered;
    final trips = _tripsByDelivery;

    final filtering = _query.trim().isNotEmpty || _period != _Period.any;
    final matching = [
      for (final stop in closed)
        if (_matchesQuery(stop) && _matchesPeriod(stop)) stop,
    ];

    // Newest first, and stops with no completion time sink to the bottom
    // rather than claiming the epoch.
    final sorted = [...matching]
      ..sort((a, b) {
        final left = a.completedAt;
        final right = b.completedAt;
        if (left == null || right == null) {
          return left == null ? (right == null ? 0 : 1) : -1;
        }
        return right.compareTo(left);
      });

    final days = <DateTime, List<Delivery>>{};
    for (final stop in sorted) {
      final at = stop.completedAt;
      if (at == null) continue;
      days.putIfAbsent(_dayOf(at), () => []).add(stop);
    }
    final undated = [
      for (final stop in sorted)
        if (stop.completedAt == null) stop,
    ];

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([controller.refresh(), _loadTrips()]);
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
                    'History',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    closed.isEmpty
                        ? 'Nothing closed out yet.'
                        : filtering
                        ? '${matching.length} of ${closed.length} '
                              '${closed.length == 1 ? 'stop' : 'stops'}'
                        : '${closed.length} '
                              '${closed.length == 1 ? 'stop' : 'stops'} closed '
                              'out',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms).moveY(begin: 8),
          ),

          // Only once there is enough here to need finding. A search bar over
          // three stops is furniture.
          if (closed.length > 3) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: SearchBar(
                  controller: _searchController,
                  hintText: 'Search reference, customer, street or signer',
                  leading: const Icon(Icons.search),
                  trailing: [
                    if (_query.trim().isNotEmpty)
                      IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear search',
                      ),
                  ],
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    for (final period in _Period.values) ...[
                      ChoiceChip(
                        label: Text(period.label),
                        selected: _period == period,
                        onSelected: (_) {
                          AppHaptics.select();
                          setState(() => _period = period);
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ),
          ],

          if (closed.isNotEmpty && !filtering) ...[
            SliverToBoxAdapter(
              child: _OutcomeCard(delivered: delivered, failed: failed)
                  .animate()
                  .fadeIn(delay: 60.ms, duration: 320.ms)
                  .moveY(begin: 12),
            ),

            SliverToBoxAdapter(
              child:
                  Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        child: Row(
                          children: [
                            _MiniStat(
                              icon: Icons.route_outlined,
                              label: 'Driven',
                              value: formatDistance(
                                _totalDistance,
                                unit: context.distanceUnit,
                              ),
                            ),
                            _MiniStat(
                              icon: Icons.timer_outlined,
                              label: 'Driving',
                              value: formatDuration(_totalDriving),
                            ),
                            _MiniStat(
                              icon: Icons.local_shipping_outlined,
                              label: 'Trips',
                              value: '${_trips.length}',
                            ),
                          ],
                        ),
                      )
                      .animate()
                      .fadeIn(delay: 120.ms, duration: 320.ms)
                      .moveY(begin: 12),
            ),
          ],

          if (sorted.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 64),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      filtering ? Icons.search_off : Icons.history,
                      size: 52,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      filtering ? 'No match' : 'Nothing here yet',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      filtering
                          ? 'Nothing closed out matches that. Try a wider '
                                'period, or clear the search.'
                          : 'Every stop you close out lands here, with the '
                                'route you drove to get to it.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (filtering) ...[
                      const SizedBox(height: 14),
                      TextButton.icon(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _query = '';
                            _period = _Period.any;
                          });
                        },
                        icon: const Icon(Icons.clear_all),
                        label: const Text('Clear filters'),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            for (final entry in [
              ...days.entries.map((day) => (_dayLabel(day.key), day.value)),
              if (undated.isNotEmpty) ('No date recorded', undated),
            ]) ...[
              SliverToBoxAdapter(
                child: _DayHeader(label: entry.$1, stops: entry.$2.length),
              ),
              SliverList.builder(
                itemCount: entry.$2.length,
                itemBuilder: (context, index) {
                  final delivery = entry.$2[index];
                  return _HistoryCard(
                    delivery: delivery,
                    trip: trips[delivery.id],
                    onTap: () async {
                      await showDeliveryDetail(context, delivery.id);
                      await _loadTrips();
                    },
                  );
                },
              ),
            ],

          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }
}

/// How the day actually went, in the two numbers that matter. Green for the
/// drops that landed, and the failures only get their own half of the card
/// when there are any — a row of zeroes is not worth the space.
class _OutcomeCard extends StatelessWidget {
  const _OutcomeCard({required this.delivered, required this.failed});

  final int delivered;
  final int failed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = delivered + failed;
    final rate = total == 0 ? 0.0 : delivered / total;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Card(
        elevation: 0,
        color: context.deliveredContainer,
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
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: rate),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) => SizedBox(
                        width: 76,
                        height: 76,
                        child: CircularProgressIndicator(
                          value: value,
                          strokeWidth: 8,
                          backgroundColor: context.onDeliveredContainer
                              .withValues(alpha: 0.15),
                          valueColor: AlwaysStoppedAnimation(
                            context.onDeliveredContainer,
                          ),
                        ),
                      ),
                    ),
                    Icon(
                      Icons.check,
                      color: context.onDeliveredContainer,
                      size: 26,
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
                      '$delivered delivered',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.onDeliveredContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      failed == 0
                          ? 'Everything closed out went through.'
                          : '$failed could not be left',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: failed == 0
                            ? context.onDeliveredContainer.withValues(
                                alpha: 0.85,
                              )
                            : scheme.error,
                        fontWeight: failed == 0
                            ? FontWeight.w400
                            : FontWeight.w600,
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

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label, required this.stops});

  final String label;
  final int stops;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          Text(
            '$stops ${stops == 1 ? 'stop' : 'stops'}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One closed stop, as a card rather than a list row so it sits in the same
/// language as the manifest.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.delivery,
    required this.trip,
    required this.onTap,
  });

  final Delivery delivery;
  final Trip? trip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final delivered = delivery.status == DeliveryStatus.delivered;
    final completedAt = delivery.completedAt;
    final recorded = trip;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: delivered
                      ? context.deliveredContainer
                      : scheme.errorContainer,
                  child: Icon(
                    delivered ? Icons.check : Icons.priority_high,
                    size: 20,
                    color: delivered
                        ? context.onDeliveredContainer
                        : scheme.onErrorContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              delivery.customerName,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusChip(delivery.status, dense: true),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        delivery.address,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _Fact(icon: Icons.tag, text: delivery.reference),
                          if (completedAt != null)
                            _Fact(
                              icon: Icons.check_circle_outline,
                              text: formatTime(completedAt),
                            ),
                          if (recorded != null)
                            _Fact(
                              icon: Icons.route_outlined,
                              text: formatDistance(
                                recorded.distanceMeters,
                                unit: context.distanceUnit,
                              ),
                            ),
                          if (delivery.parcelsScanned > 0)
                            _Fact(
                              icon: Icons.qr_code_scanner,
                              text:
                                  '${delivery.parcelsScanned}/'
                                  '${delivery.parcelCount}',
                            ),
                        ],
                      ),
                      if (delivery.recipientName case final String name)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Received by $name',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (delivery.failureReason case final String reason)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            // The reason and what was done about it read as
                            // one sentence: "Nobody home · carded, retry
                            // tomorrow" is the whole story of that stop.
                            [
                              reason,
                              if (delivery.failureAction
                                  case final FailureAction action)
                                action.label.toLowerCase(),
                            ].join(' · '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One icon-and-value pair on a history card.
class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The same three-across stat row the home tab uses, so the two screens read
/// as the same app.
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
