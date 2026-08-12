import 'package:flutter/material.dart';

import '../../models/delivery.dart';
import 'outcome_colors.dart';

/// Colour-coded status pill. Colours are derived from the theme so the chip
/// stays legible in both light and dark mode — except delivered, which is the
/// fixed green from [OutcomeColors] so a closed-out stop reads the same under
/// every accent.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.dense = false});

  final DeliveryStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground, icon) = switch (status) {
      DeliveryStatus.pending => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        Icons.schedule,
      ),
      DeliveryStatus.inTransit => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.local_shipping,
      ),
      DeliveryStatus.delivered => (
        context.deliveredContainer,
        context.onDeliveredContainer,
        Icons.check_circle,
      ),
      DeliveryStatus.failed => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.error_outline,
      ),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: dense ? 13 : 15, color: foreground),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TextStyle(
              color: foreground,
              fontSize: dense ? 11 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
