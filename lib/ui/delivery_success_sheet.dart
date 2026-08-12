import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/app_settings.dart';
import '../models/delivery.dart';
import '../models/trip.dart';
import 'formatters.dart';
import 'widgets/app_sheet.dart';

/// The moment a stop is closed out successfully.
///
/// Worth the two seconds: a delivery round is a long grind of near-identical
/// actions, and a clear, unmistakable "that one is done" is the difference
/// between confidence and double-checking. It auto-dismisses so it never
/// becomes another tap.
class DeliverySuccessSheet extends StatelessWidget {
  const DeliverySuccessSheet({
    super.key,
    required this.delivery,
    required this.trip,
    required this.unit,
    required this.remainingStops,
    this.nextStop,
  });

  final Delivery delivery;
  final Trip? trip;
  final DistanceUnit unit;
  final int remainingStops;
  final Delivery? nextStop;

  static Future<void> show(
    BuildContext context, {
    required Delivery delivery,
    required Trip? trip,
    required DistanceUnit unit,
    required int remainingStops,
    Delivery? nextStop,
  }) {
    return showAppSheet<void>(
      context,
      maxHeightFactor: 0.75,
      builder: (_) => DeliverySuccessSheet(
        delivery: delivery,
        trip: trip,
        unit: unit,
        remainingStops: remainingStops,
        nextStop: nextStop,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child:
                Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: scheme.tertiaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        size: 52,
                        color: scheme.onTertiaryContainer,
                      ),
                    )
                    .animate()
                    // Overshoot then settle — a linear grow reads as a loading
                    // spinner rather than a confirmation.
                    .scale(
                      duration: 420.ms,
                      curve: Curves.elasticOut,
                      begin: const Offset(0.4, 0.4),
                      end: const Offset(1, 1),
                    )
                    .fadeIn(duration: 180.ms),
          ),
          const SizedBox(height: 18),
          Text(
            'Delivered',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ).animate().fadeIn(delay: 160.ms, duration: 240.ms).moveY(begin: 8),
          const SizedBox(height: 4),
          Text(
            '${delivery.reference} · ${delivery.customerName}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ).animate().fadeIn(delay: 220.ms, duration: 240.ms),

          const SizedBox(height: 22),
          Row(
            children: [
              _Stat(
                label: 'Driven',
                value: trip == null
                    ? '—'
                    : formatDistance(trip!.distanceMeters, unit: unit),
                icon: Icons.route_outlined,
              ),
              _Stat(
                label: 'Took',
                value: trip == null ? '—' : formatDuration(trip!.duration),
                icon: Icons.timer_outlined,
              ),
              _Stat(
                label: 'Left',
                value: '$remainingStops',
                icon: Icons.local_shipping_outlined,
              ),
            ],
          ).animate().fadeIn(delay: 300.ms, duration: 260.ms).moveY(begin: 10),

          if (nextStop case final Delivery next) ...[
            const SizedBox(height: 20),
            Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.turn_sharp_right, color: scheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Next stop',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              next.customerName,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              next.address,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
                .animate()
                .fadeIn(delay: 380.ms, duration: 260.ms)
                .moveY(begin: 12),
          ] else ...[
            const SizedBox(height: 20),
            Text(
              "That's the whole round done.",
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ).animate().fadeIn(delay: 380.ms, duration: 260.ms),
          ],

          const SizedBox(height: 22),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: const Text('Carry on'),
          ).animate().fadeIn(delay: 460.ms, duration: 220.ms),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 6),
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
