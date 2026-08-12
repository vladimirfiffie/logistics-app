import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/app_settings.dart';
import '../models/delivery.dart';
import '../models/trip.dart';
import 'formatters.dart';
import 'widgets/outcome_mark.dart';
import 'widgets/app_sheet.dart';

/// The moment a stop is closed out, either way.
///
/// Worth the two seconds: a delivery round is a long grind of near-identical
/// actions, and a clear, unmistakable "that one is done" is the difference
/// between confidence and double-checking. A stop that could *not* be
/// delivered gets the same confirmation for the same reason — silently
/// returning to the list leaves the driver wondering whether it registered.
class DeliveryOutcomeSheet extends StatelessWidget {
  const DeliveryOutcomeSheet({
    super.key,
    required this.delivery,
    required this.trip,
    required this.unit,
    required this.remainingStops,
    this.nextStop,
    this.failureReason,
  });

  final Delivery delivery;
  final Trip? trip;
  final DistanceUnit unit;
  final int remainingStops;
  final Delivery? nextStop;

  /// Set when the stop could not be delivered. Switches the whole sheet from
  /// celebration to acknowledgement.
  final String? failureReason;

  bool get _failed => failureReason != null;

  /// Resolves to true when the driver asked to start the next stop straight
  /// away, false or null otherwise.
  static Future<bool?> show(
    BuildContext context, {
    required Delivery delivery,
    required Trip? trip,
    required DistanceUnit unit,
    required int remainingStops,
    Delivery? nextStop,
    String? failureReason,
  }) {
    return showAppSheet<bool>(
      context,
      maxHeightFactor: 0.75,
      builder: (_) => DeliveryOutcomeSheet(
        delivery: delivery,
        trip: trip,
        unit: unit,
        remainingStops: remainingStops,
        nextStop: nextStop,
        failureReason: failureReason,
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
          // The mark draws its own stroke, so it is not wrapped in the
          // fade/scale the rest of the sheet uses.
          Center(child: OutcomeMark(failed: _failed)),
          const SizedBox(height: 18),
          Text(
            _failed ? 'Not delivered' : 'Delivered',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: OutcomeMark.colorFor(
                failed: _failed,
                brightness: theme.brightness,
              ),
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

          if (failureReason case final String reason) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Recorded as: $reason',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ).animate().fadeIn(delay: 260.ms, duration: 240.ms),
          ],

          const SizedBox(height: 22),
          Row(
            children: [
              _Stat(
                label: _failed ? 'Drove' : 'Driven',
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
              _failed
                  ? 'That was the last stop on the round.'
                  : "That's the whole round done.",
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ).animate().fadeIn(delay: 380.ms, duration: 260.ms),
          ],

          const SizedBox(height: 22),
          if (nextStop != null) ...[
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start the next stop'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ).animate().fadeIn(delay: 440.ms, duration: 220.ms),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not yet'),
            ).animate().fadeIn(delay: 480.ms, duration: 220.ms),
          ] else
            FilledButton(
              onPressed: () => Navigator.of(context).pop(false),
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
