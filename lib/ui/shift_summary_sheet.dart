import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/app_settings.dart';
import '../models/shift.dart';
import 'formatters.dart';
import 'widgets/app_sheet.dart';
import 'widgets/outcome_colors.dart';
import 'widgets/outcome_mark.dart';

/// What the driver's day came to.
typedef ShiftSummary = ({
  Shift shift,
  Duration worked,
  Duration breaks,
  int stopsClosed,
  int delivered,
  double distanceMeters,
});

/// Shown when the shift ends.
///
/// Clocking off used to be a snackbar — the one moment in the day where a
/// driver has finished something and the app said "Clocked off · 8h 12m" in
/// grey text for four seconds. The day's numbers are already recorded, and
/// the end of a shift is the moment they are worth reading: hours, breaks,
/// what got delivered, how far it took, and what it is worth if rates have
/// been set.
class ShiftSummarySheet extends StatelessWidget {
  const ShiftSummarySheet({
    super.key,
    required this.summary,
    required this.settings,
  });

  final ShiftSummary summary;
  final AppSettings settings;

  static Future<void> show(
    BuildContext context, {
    required ShiftSummary summary,
    required AppSettings settings,
  }) {
    return showAppSheet<void>(
      context,
      maxHeightFactor: 0.9,
      builder: (_) => ShiftSummarySheet(summary: summary, settings: settings),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final hoursPay = settings.hourlyRate <= 0
        ? null
        : settings.hourlyRate * (summary.worked.inSeconds / 3600);
    final mileage = settings.mileageRate <= 0
        ? null
        : settings.mileageRate *
              (settings.distanceUnit == DistanceUnit.imperial
                  ? summary.distanceMeters / 1609.344
                  : summary.distanceMeters / 1000);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The same drawn tick a delivered stop gets. Finishing a shift is
            // the same kind of moment, and it should land the same way.
            const Center(child: OutcomeMark(failed: false, size: 72)),
            const SizedBox(height: 14),

            Text(
              "That's the day",
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ).animate().fadeIn(delay: 120.ms, duration: 300.ms),

            const SizedBox(height: 4),
            Text(
              '${formatDate(summary.shift.startedAt)} · '
              '${formatTime(summary.shift.startedAt)}–'
              '${formatTime(summary.shift.endedAt ?? DateTime.now())}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ).animate().fadeIn(delay: 180.ms, duration: 300.ms),

            const SizedBox(height: 22),

            // The headline figure: paid time, breaks already taken out.
            Container(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: context.deliveredContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        formatDuration(summary.worked),
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: context.onDeliveredContainer,
                        ),
                      ),
                      Text(
                        summary.breaks == Duration.zero
                            ? 'worked, no breaks taken'
                            : 'worked · ${formatDuration(summary.breaks)} on '
                                  'breaks',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.onDeliveredContainer.withValues(
                            alpha: 0.85,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                .animate()
                .fadeIn(delay: 240.ms, duration: 340.ms)
                .moveY(begin: 14),

            const SizedBox(height: 16),

            Row(
                  children: [
                    _Figure(
                      icon: Icons.check_circle_outline,
                      label: 'Delivered',
                      value: '${summary.delivered}',
                      detail: summary.stopsClosed == summary.delivered
                          ? null
                          : 'of ${summary.stopsClosed} closed',
                    ),
                    _Figure(
                      icon: Icons.route_outlined,
                      label: 'Driven',
                      value: formatDistance(
                        summary.distanceMeters,
                        unit: settings.distanceUnit,
                      ),
                    ),
                    if (summary.shift.vehicleLabel case final String van)
                      _Figure(
                        icon: Icons.local_shipping_outlined,
                        label: 'Van',
                        value: van,
                      ),
                  ],
                )
                .animate()
                .fadeIn(delay: 320.ms, duration: 340.ms)
                .moveY(begin: 14),

            if (hoursPay != null || mileage != null) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    if (hoursPay != null)
                      _Money(
                        label: 'Hours',
                        amount: settings.currency.format(hoursPay),
                      ),
                    if (mileage != null)
                      _Money(
                        label: 'Mileage claim',
                        amount: settings.currency.format(mileage),
                      ),
                    if (hoursPay != null && mileage != null) ...[
                      const Divider(height: 16),
                      _Money(
                        label: 'Total',
                        amount: settings.currency.format(hoursPay + mileage),
                        bold: true,
                      ),
                    ],
                  ],
                ),
              ).animate().fadeIn(delay: 400.ms, duration: 340.ms),
            ],

            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 5),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            detail ?? label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _Money extends StatelessWidget {
  const _Money({required this.label, required this.amount, this.bold = false});

  final String label;
  final String amount;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: style),
          const Spacer(),
          Text(amount, style: style),
        ],
      ),
    );
  }
}
