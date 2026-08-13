import 'package:flutter/material.dart';

import '../../models/delivery.dart';
import '../formatters.dart';
import '../../state/settings_controller.dart';
import 'status_chip.dart';

/// One stop in the manifest list.
class DeliveryCard extends StatelessWidget {
  const DeliveryCard({
    super.key,
    required this.delivery,
    required this.onTap,
    this.distanceMeters,
  });

  final Delivery delivery;
  final VoidCallback onTap;

  /// Straight-line distance from the driver, when a fix is available.
  final double? distanceMeters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isActive = delivery.status == DeliveryStatus.inTransit;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: isActive ? 2 : 0,
      color: isActive ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isActive ? scheme.primary : scheme.outlineVariant,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    delivery.reference,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  // A stop that has already been tried once needs to say so
                  // before the driver knocks: they are often the awkward ones.
                  if (delivery.isRetry) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Attempt ${delivery.attempt}',
                        style: TextStyle(
                          color: scheme.onErrorContainer,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  StatusChip(delivery.status, dense: true),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                delivery.customerName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                delivery.address,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  _Meta(
                    icon: Icons.schedule,
                    text: formatTime(delivery.scheduledFor),
                  ),
                  _Meta(
                    icon: Icons.inventory_2_outlined,
                    // Once any have been scanned off, the count that matters
                    // is how many are accounted for.
                    text: delivery.parcelsScanned == 0
                        ? '${delivery.parcelCount} '
                              '${delivery.parcelCount == 1 ? 'parcel' : 'parcels'}'
                        : '${delivery.parcelsScanned}/'
                              '${delivery.parcelCount} scanned',
                    highlight:
                        delivery.parcelsScanned > 0 &&
                        delivery.allParcelsScanned,
                  ),
                  if (distanceMeters != null)
                    _Meta(
                      icon: Icons.near_me_outlined,
                      text: formatDistance(
                        distanceMeters!,
                        unit: context.distanceUnit,
                      ),
                      highlight: true,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, this.highlight = false});

  final IconData icon;
  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = highlight
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: highlight ? FontWeight.w600 : null,
          ),
        ),
      ],
    );
  }
}
