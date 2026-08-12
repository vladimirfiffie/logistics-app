import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/delivery_repository.dart';
import '../models/shift.dart';
import '../models/shift_break.dart';
import '../state/shift_controller.dart';
import 'formatters.dart';

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
    if (!mounted) return;
    setState(() {
      _shifts = shifts;
      _breaks = breaks;
      _loading = false;
    });
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
                shifts: entry.value.length,
              ),
              for (final shift in entry.value)
                _ShiftRow(
                  shift: shift,
                  breaks: _breaks[shift.id] ?? const [],
                  breakTime: _breakTime(shift),
                  worked: _worked(shift),
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
    required this.shifts,
  });

  final DateTime weekStart;
  final Duration worked;
  final Duration breaks;
  final int shifts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Card(
        elevation: 0,
        color: scheme.primaryContainer,
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
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatDuration(worked),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    Text(
                      '$shifts ${shifts == 1 ? 'shift' : 'shifts'}'
                      '${breaks == Duration.zero ? '' : ' · ${formatDuration(breaks)} on breaks'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onPrimaryContainer.withValues(
                          alpha: 0.85,
                        ),
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

class _ShiftRow extends StatelessWidget {
  const _ShiftRow({
    required this.shift,
    required this.breaks,
    required this.breakTime,
    required this.worked,
  });

  final Shift shift;
  final List<ShiftBreak> breaks;
  final Duration breakTime;
  final Duration worked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ended = shift.endedAt;

    return ListTile(
      leading: Icon(
        shift.isActive ? Icons.play_circle : Icons.check_circle_outline,
        color: shift.isActive ? scheme.primary : scheme.onSurfaceVariant,
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
