import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/delivery_repository.dart';
import '../models/delivery.dart';
import '../models/trip.dart';
import '../state/delivery_controller.dart';
import 'delivery_detail_screen.dart';
import 'formatters.dart';
import 'widgets/status_chip.dart';

/// Closed-out stops and the distance recorded getting to them.
class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  List<Trip> _trips = const [];

  @override
  void initState() {
    super.initState();
    _loadTrips();
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

  Trip? _tripFor(String deliveryId) {
    for (final trip in _trips) {
      if (trip.deliveryId == deliveryId) return trip;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DeliveryController>();
    final closed = controller.closedStops;
    final delivered = closed
        .where((d) => d.status == DeliveryStatus.delivered)
        .length;

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([controller.refresh(), _loadTrips()]);
      },
      child: CustomScrollView(
        slivers: [
          SliverAppBar.large(title: const Text('History')),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      _Total(
                        label: 'Delivered',
                        value: '$delivered',
                        of: '${closed.length}',
                      ),
                      _Total(
                        label: 'Distance',
                        value: formatDistance(_totalDistance),
                      ),
                      _Total(
                        label: 'Driving',
                        value: formatDuration(_totalDriving),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          if (closed.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.history,
                      size: 48,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    const Text('Nothing closed out yet.'),
                  ],
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: closed.length,
              itemBuilder: (context, index) {
                final delivery = closed[index];
                return _HistoryTile(
                  delivery: delivery,
                  trip: _tripFor(delivery.id),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            DeliveryDetailScreen(deliveryId: delivery.id),
                      ),
                    );
                    await _loadTrips();
                  },
                );
              },
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.value, this.of});

  final String label;
  final String value;

  /// Optional denominator, rendered small next to [value].
  final String? of;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (of != null)
                Text(
                  ' / $of',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
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
    final completedAt = delivery.completedAt;

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: delivery.status == DeliveryStatus.delivered
            ? theme.colorScheme.tertiaryContainer
            : theme.colorScheme.errorContainer,
        child: Icon(
          delivery.status == DeliveryStatus.delivered
              ? Icons.check
              : Icons.priority_high,
          size: 20,
          color: delivery.status == DeliveryStatus.delivered
              ? theme.colorScheme.onTertiaryContainer
              : theme.colorScheme.onErrorContainer,
        ),
      ),
      title: Text(
        delivery.customerName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          delivery.reference,
          if (completedAt != null) formatTime(completedAt),
          if (trip != null) formatDistance(trip!.distanceMeters),
          if (delivery.failureReason case final String reason) reason,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: StatusChip(delivery.status, dense: true),
    );
  }
}
