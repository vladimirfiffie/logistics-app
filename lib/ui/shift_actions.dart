import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/shift.dart';
import '../services/app_haptics.dart';
import '../state/settings_controller.dart';
import '../state/shift_controller.dart';
import 'formatters.dart';
import 'nfc_scan_sheet.dart';
import 'widgets/app_sheet.dart';

/// Clocking on lives here rather than on the home tab because it is not only
/// reached from there: starting a stop while clocked off offers it too, and
/// the two must behave identically — same tag prompt, same failure message.
///
/// Returns the shift that started, or null if the driver backed out or it
/// failed. A failure has already been said out loud by the time this returns.
Future<Shift?> clockOn(BuildContext context) async {
  final shifts = context.read<ShiftController>();
  final settings = context.read<SettingsController>().settings;
  final messenger = ScaffoldMessenger.of(context);

  var vehicle = settings.vehicleLabel.isEmpty ? null : settings.vehicleLabel;
  var startedByTag = false;

  // The tag is offered as a shortcut and never required — the sheet always
  // carries a "start without a tag" button, so a phone with no NFC or a van
  // with no sticker is not a dead end. Drivers who will never use a tag can
  // turn the prompt off entirely in Settings.
  if (settings.nfcClockOn) {
    final result = await NfcScanSheet.show(
      context,
      title: 'Start your shift',
      subtitle: 'Tap the tag in your van, or start without one.',
      manualLabel: 'Start without a tag',
    );
    if (result == null) return null;
    if (result case NfcSheetTag(:final tag)) {
      vehicle = tag.label;
      startedByTag = true;
    }
  }

  final started = await shifts.start(
    vehicleLabel: vehicle,
    startedByTag: startedByTag,
  );

  // A failed clock-on used to be completely silent: the button did nothing
  // and the card stayed on "Not on shift".
  if (started == null) {
    await AppHaptics.error();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Could not clock on. ${shifts.error ?? ''}'.trim()),
      ),
    );
    return null;
  }

  await AppHaptics.trackingStarted();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        'Clocked on at ${formatTime(started.startedAt)}'
        '${vehicle == null ? '' : ' · $vehicle'}.',
      ),
    ),
  );
  return started;
}

/// Checked before a stop starts recording. Returns true if the caller should
/// go ahead.
///
/// Starting a stop used to begin recording whether or not the driver had
/// clocked on, which quietly produced a day of trips against no shift — the
/// distance was recorded and the hours were not. It still lets them through,
/// because a driver at a door does not want an argument with their phone, but
/// it says what is about to happen and offers the one tap that fixes it.
Future<bool> ensureOnShift(BuildContext context) async {
  final shifts = context.read<ShiftController>();
  if (shifts.isOnShift) return true;

  final choice = await showAppSheet<_ClockOnChoice>(
    context,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHeader(
            title: "You're not clocked on",
            subtitle:
                'The route and the time are recorded against the stop either '
                'way, but none of it lands on your timesheet until your shift '
                'is running.',
            icon: Icons.punch_clock_outlined,
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: () =>
                Navigator.of(sheetContext).pop(_ClockOnChoice.clockOn),
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('Clock on and start'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.tonal(
            onPressed: () =>
                Navigator.of(sheetContext).pop(_ClockOnChoice.anyway),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: const Text('Start without clocking on'),
          ),
          TextButton(
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );

  if (choice == null || !context.mounted) return false;
  if (choice == _ClockOnChoice.anyway) return true;

  // Clocking on can still be abandoned at the tag sheet, or fail outright.
  // Either way the driver has been told, and the stop stays where it was.
  return await clockOn(context) != null;
}

enum _ClockOnChoice { clockOn, anyway }
