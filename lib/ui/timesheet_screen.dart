import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/delivery_repository.dart';
import '../models/app_settings.dart';
import '../models/shift.dart';
import '../models/shift_break.dart';
import '../models/trip.dart';
import '../state/settings_controller.dart';
import '../state/shift_controller.dart';
import 'formatters.dart';
import 'widgets/outcome_colors.dart';

/// Every shift the driver has worked, grouped by week.
///
/// The data has been recorded since shifts existed and was never shown
/// anywhere. It is also the one screen in the app a driver might need to
/// settle an argument about hours, so it shows the breaks and the net figure
/// rather than only the clock-on and clock-off times.
class TimesheetScreen extends StatefulWidget {
  const TimesheetScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const TimesheetScreen()));
  }

  @override
  State<TimesheetScreen> createState() => _TimesheetScreenState();
}

class _TimesheetScreenState extends State<TimesheetScreen> {
  List<Shift> _shifts = const [];
  Map<String, List<ShiftBreak>> _breaks = const {};
  List<Trip> _trips = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = context.read<DeliveryRepository>();
    final shifts = await repository.fetchShifts();
    // One query for every shift on screen rather than one per row.
    final breaks = await repository.breaksForShifts([
      for (final shift in shifts) shift.id,
    ]);
    // Trips carry the distance a mileage claim is made of. Read once and
    // matched to shifts by when they ran, since a trip belongs to a stop
    // rather than to a shift.
    final trips = await repository.fetchTrips();
    if (!mounted) return;
    setState(() {
      _shifts = shifts;
      _breaks = breaks;
      _trips = trips;
      _loading = false;
    });
  }

  /// Metres driven during [shift]. A trip counts towards the shift it started
  /// in, which is the same rule a driver would apply reading their own day.
  double _distance(Shift shift) {
    final from = shift.startedAt;
    final to = shift.endedAt ?? DateTime.now();
    var total = 0.0;
    for (final trip in _trips) {
      if (trip.startedAt.isBefore(from)) continue;
      if (trip.startedAt.isAfter(to)) continue;
      total += trip.distanceMeters;
    }
    return total;
  }

  Duration _breakTime(Shift shift) => (_breaks[shift.id] ?? const []).fold(
    Duration.zero,
    (sum, taken) => sum + taken.duration,
  );

  /// Paid time: the shift minus its breaks, never below zero.
  Duration _worked(Shift shift) {
    final net = shift.duration - _breakTime(shift);
    return net.isNegative ? Duration.zero : net;
  }

  /// Monday of the week [when] falls in, at midnight — the key rows group by.
  DateTime _weekStart(DateTime when) {
    final day = DateTime(when.year, when.month, when.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Timesheet')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_shifts.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Timesheet')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.schedule,
                  size: 56,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text('No shifts yet', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'Clock on from the home screen and your hours are recorded '
                  'here.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Shifts arrive newest first, so the weeks come out newest first too.
    final weeks = <DateTime, List<Shift>>{};
    for (final shift in _shifts) {
      weeks.putIfAbsent(_weekStart(shift.startedAt), () => []).add(shift);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Timesheet')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            for (final entry in weeks.entries) ...[
              _WeekHeader(
                weekStart: entry.key,
                worked: entry.value.fold(
                  Duration.zero,
                  (sum, shift) => sum + _worked(shift),
                ),
                breaks: entry.value.fold(
                  Duration.zero,
                  (sum, shift) => sum + _breakTime(shift),
                ),
                distanceMeters: entry.value.fold(
                  0.0,
                  (sum, shift) => sum + _distance(shift),
                ),
                shifts: entry.value.length,
              ),
              for (final shift in entry.value)
                _ShiftRow(
                  shift: shift,
                  breaks: _breaks[shift.id] ?? const [],
                  breakTime: _breakTime(shift),
                  worked: _worked(shift),
                  distanceMeters: _distance(shift),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({
    required this.weekStart,
    required this.worked,
    required this.breaks,
    required this.distanceMeters,
    required this.shifts,
  });

  final DateTime weekStart;
  final Duration worked;
  final Duration breaks;
  final double distanceMeters;
  final int shifts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.appSettings;

    // The same green a delivered stop is drawn in: a week of hours banked is
    // work done, and it should not be a different colour from a drop done.
    final onCard = context.onDeliveredContainer;

    // Hours pay and a mileage claim are different kinds of money — one is
    // earnings, the other is expenses — so they are shown as two lines and
    // only totalled when both are set.
    final hoursPay = settings.hourlyRate <= 0
        ? null
        : settings.hourlyRate * (worked.inSeconds / 3600);
    final mileage = settings.mileageRate <= 0
        ? null
        : settings.mileageRate *
              (settings.distanceUnit == DistanceUnit.imperial
                  ? distanceMeters / 1609.344
                  : distanceMeters / 1000);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Card(
        elevation: 0,
        color: context.deliveredContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Week of ${formatDate(weekStart)}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: onCard,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatDuration(worked),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: onCard,
                      ),
                    ),
                    Text(
                      [
                        '$shifts ${shifts == 1 ? 'shift' : 'shifts'}',
                        if (breaks != Duration.zero)
                          '${formatDuration(breaks)} on breaks',
                        if (distanceMeters > 0)
                          formatDistance(
                            distanceMeters,
                            unit: settings.distanceUnit,
                          ),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: onCard.withValues(alpha: 0.85),
                      ),
                    ),

                    if (hoursPay != null || mileage != null) ...[
                      const SizedBox(height: 10),
                      Divider(height: 1, color: onCard.withValues(alpha: 0.2)),
                      const SizedBox(height: 8),
                      if (hoursPay != null)
                        _MoneyLine(
                          label: 'Hours',
                          amount: settings.currency.format(hoursPay),
                          color: onCard,
                        ),
                      if (mileage != null)
                        _MoneyLine(
                          label: 'Mileage claim',
                          amount: settings.currency.format(mileage),
                          color: onCard,
                        ),
                      if (hoursPay != null && mileage != null)
                        _MoneyLine(
                          label: 'Total',
                          amount: settings.currency.format(hoursPay + mileage),
                          color: onCard,
                          bold: true,
                        ),
                    ],
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

/// One figure on the week card. Deliberately plain: this is a number someone
/// will copy into an invoice, not a headline.
class _MoneyLine extends StatelessWidget {
  const _MoneyLine({
    required this.label,
    required this.amount,
    required this.color,
    this.bold = false,
  });

  final String label;
  final String amount;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: bold ? color : color.withValues(alpha: 0.9),
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 2),
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

class _ShiftRow extends StatelessWidget {
  const _ShiftRow({
    required this.shift,
    required this.breaks,
    required this.breakTime,
    required this.worked,
    required this.distanceMeters,
  });

  final Shift shift;
  final List<ShiftBreak> breaks;
  final Duration breakTime;
  final Duration worked;
  final double distanceMeters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ended = shift.endedAt;

    return ListTile(
      // A finished shift is closed-out work, so it gets the same green tick a
      // closed-out stop does.
      leading: Icon(
        shift.isActive ? Icons.play_circle : Icons.check_circle,
        color: shift.isActive ? scheme.primary : context.delivered,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              formatDate(shift.startedAt),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            shift.isActive ? 'Running' : formatDuration(worked),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: shift.isActive ? scheme.primary : null,
            ),
          ),
        ],
      ),
      subtitle: Text(
        [
          '${formatTime(shift.startedAt)}–'
              '${ended == null ? 'now' : formatTime(ended)}',
          if (shift.vehicleLabel case final String van) van,
          if (shift.startedByTag) 'tag',
          if (distanceMeters > 0)
            formatDistance(distanceMeters, unit: context.distanceUnit),
          if (breaks.isNotEmpty)
            '${breaks.length} ${breaks.length == 1 ? 'break' : 'breaks'} '
                '(${formatDuration(breakTime)})',
        ].join(' · '),
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Row for the settings screen, so the timesheet is reachable and shows its
/// headline number without being opened.
class TimesheetTile extends StatelessWidget {
  const TimesheetTile({super.key});

  @override
  Widget build(BuildContext context) {
    final shifts = context.watch<ShiftController>();
    final finished = shifts.history.where((shift) => !shift.isActive).length;

    return ListTile(
      leading: const Icon(Icons.schedule),
      title: const Text('Timesheet'),
      subtitle: Text(
        finished == 0
            ? 'Your hours appear here once you have clocked off.'
            : '$finished ${finished == 1 ? 'shift' : 'shifts'} · '
                  '${formatDuration(shifts.totalWorked)} worked',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => TimesheetScreen.show(context),
    );
  }
}
