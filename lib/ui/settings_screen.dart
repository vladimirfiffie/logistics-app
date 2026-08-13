import 'dart:io';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/delivery_repository.dart';
import '../data/seed_data.dart';
import '../models/app_settings.dart';
import '../release_notes.dart';
import '../services/app_haptics.dart';
import '../services/app_preferences.dart';
import '../services/export_service.dart';
import '../services/location_service.dart';
import '../services/nfc_service.dart';
import '../services/notification_service.dart';
import '../state/delivery_controller.dart';
import '../state/settings_controller.dart';
import '../state/shift_controller.dart';
import '../state/tracking_controller.dart';
import 'formatters.dart';
import 'nfc_scan_sheet.dart';
import 'onboarding_screen.dart';
import 'timesheet_screen.dart';
import 'whats_new_sheet.dart';
import 'widgets/app_sheet.dart';

/// The way into everything the driver can change.
///
/// An index rather than the whole thing: settings had grown to roughly sixty
/// rows on one scroll, where finding the signature option meant thumbing past
/// the theme, the units and the van tag. Each category is now its own screen,
/// and each row on this list says what is currently set inside it — so the
/// common case, checking a value, does not need the sub-screen at all.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const _SectionHeader('Your round'),
          _CategoryTile(
            icon: Icons.badge_outlined,
            title: 'Driver and van',
            summary: [
              if (settings.driverName.isNotEmpty) settings.driverName,
              if (settings.vehicleLabel.isNotEmpty) settings.vehicleLabel,
            ].join(' · '),
            fallback: 'Your name, your van and its NFC tag',
            page: (_) => const DriverSettingsPage(),
          ),
          _CategoryTile(
            icon: Icons.schedule,
            title: 'Shift and breaks',
            summary:
                'Timesheet · '
                '${settings.breakReminderMinutes == 0 ? 'no break reminder' : 'reminder after ${_hours(settings.breakReminderMinutes)}'}',
            page: (_) => const ShiftSettingsPage(),
          ),
          _CategoryTile(
            icon: Icons.list_alt_outlined,
            title: 'Manifest',
            summary:
                'Opens in ${settings.defaultSort.label.toLowerCase()} '
                'order',
            page: (_) => const ManifestSettingsPage(),
          ),
          _CategoryTile(
            icon: Icons.gps_fixed,
            title: 'Tracking',
            summary:
                '${settings.accuracy.label} GPS · '
                '${settings.followMode.label.toLowerCase()} map',
            page: (_) => const TrackingSettingsPage(),
          ),
          _CategoryTile(
            icon: Icons.draw_outlined,
            title: 'Proof of delivery',
            summary: [
              'Signature ${settings.signatureMode.label.toLowerCase()}',
              if (settings.requireProofPhoto) 'photo required',
              if (settings.confirmWithSlide) 'slide to complete',
            ].join(' · '),
            page: (_) => const ProofSettingsPage(),
          ),

          const _SectionHeader('The app'),
          _CategoryTile(
            icon: settings.theme.icon,
            title: 'Appearance',
            summary: [
              settings.theme.label,
              settings.accent.label,
              if (settings.amoled) 'AMOLED',
            ].join(' · '),
            page: (_) => const AppearanceSettingsPage(),
          ),
          _CategoryTile(
            icon: Icons.straighten,
            title: 'Units and formats',
            summary:
                '${settings.distanceUnit.label} · '
                '${settings.usesFahrenheit ? '°F' : '°C'} · '
                '${settings.clockStyle.label}',
            page: (_) => const UnitsSettingsPage(),
          ),
          _CategoryTile(
            icon: Icons.notifications_none,
            title: 'Alerts and feedback',
            summary: [
              settings.arrivalAlerts
                  ? 'Arrival alerts at ${settings.arrivalRadiusMeters}m'
                  : 'No arrival alerts',
              if (settings.hapticsEnabled) 'haptics',
            ].join(' · '),
            page: (_) => const AlertsSettingsPage(),
          ),
          _CategoryTile(
            icon: Icons.wb_cloudy_outlined,
            title: 'Weather',
            summary: settings.showWeather
                ? 'Driving conditions on the home screen'
                : 'Off — nothing leaves the device',
            page: (_) => const WeatherSettingsPage(),
          ),

          const _SectionHeader('Phone and data'),
          _CategoryTile(
            icon: Icons.my_location,
            title: 'Permissions',
            summary: 'Location, and what tracking needs to keep running',
            page: (_) => const PermissionsSettingsPage(),
          ),
          _CategoryTile(
            icon: Icons.save_alt,
            title: 'Data',
            summary: 'Export as CSV or GPX, clear history, start a fresh day',
            page: (_) => const DataSettingsPage(),
          ),
          _CategoryTile(
            icon: Icons.info_outline,
            title: 'About',
            summary: 'Version ${currentRelease.version}',
            page: (_) => const AboutSettingsPage(),
          ),
        ],
      ),
    );
  }
}

String _hours(int minutes) {
  if (minutes % 60 == 0) return '${minutes ~/ 60}h';
  return '${minutes ~/ 60}h ${minutes % 60}m';
}

/// One row on the index. [summary] is what is set inside, so the list answers
/// most questions without being opened.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.icon,
    required this.title,
    required this.summary,
    required this.page,
    this.fallback,
  });

  final IconData icon;
  final String title;
  final String summary;

  /// Used when [summary] comes out empty, e.g. nothing filled in yet.
  final String? fallback;

  final WidgetBuilder page;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = summary.trim().isEmpty ? (fallback ?? '') : summary.trim();

    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        AppHaptics.select();
        Navigator.of(context).push(MaterialPageRoute(builder: page));
      },
    );
  }
}

/// Shared shell for a category screen: a title, a back button, and a list.
class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: children,
      ),
    );
  }
}

// ── Appearance ────────────────────────────────────────────────────────────

class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;

    return _SettingsPage(
      title: 'Appearance',
      children: [
        _ChoiceTile<ThemeChoice>(
          icon: settings.theme.icon,
          title: 'Theme',
          value: settings.theme,
          valueLabel: settings.theme.label,
          options: ThemeChoice.values,
          labelOf: (choice) => choice.label,
          onChanged: controller.setTheme,
        ),
        _ChoiceTile<AccentColor>(
          icon: Icons.palette_outlined,
          title: 'Accent colour',
          value: settings.accent,
          valueLabel: settings.accent.label,
          options: AccentColor.values,
          labelOf: (accent) => accent.label,
          onChanged: controller.setAccent,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.contrast),
          title: const Text('AMOLED black'),
          subtitle: const Text(
            'True black in dark mode. Saves power on an OLED screen.',
          ),
          value: settings.amoled,
          onChanged: (value) {
            AppHaptics.select();
            controller.setAmoled(value);
          },
        ),
      ],
    );
  }
}

// ── Units and formats ─────────────────────────────────────────────────────

/// Grouped rather than scattered: someone who reads miles usually wants to fix
/// every readout in one visit.
class UnitsSettingsPage extends StatelessWidget {
  const UnitsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;

    return _SettingsPage(
      title: 'Units and formats',
      children: [
        const _SubsectionHeader('Distance'),
        _ChoiceTile<DistanceUnit>(
          icon: Icons.straighten,
          title: 'Distance and speed',
          value: settings.distanceUnit,
          valueLabel:
              '${settings.distanceUnit.label} · '
              '${settings.distanceUnit.detail.toLowerCase()}',
          options: DistanceUnit.values,
          labelOf: (unit) => unit.label,
          detailOf: (unit) => unit.detail,
          onChanged: controller.setDistanceUnit,
        ),

        const _SubsectionHeader('Weather'),
        _ChoiceTile<TemperatureUnit>(
          icon: Icons.thermostat_outlined,
          title: 'Temperature',
          value: settings.temperatureUnit,
          valueLabel: settings.temperatureUnit == TemperatureUnit.matchUnits
              ? '${settings.temperatureUnit.label} · '
                    '${settings.usesFahrenheit ? '°F' : '°C'}'
              : settings.temperatureUnit.label,
          options: TemperatureUnit.values,
          labelOf: (unit) => unit.label,
          detailOf: (unit) => unit.detail,
          onChanged: controller.setTemperatureUnit,
        ),
        _ChoiceTile<WindUnit>(
          icon: Icons.air,
          title: 'Wind speed',
          value: settings.windUnit,
          valueLabel: settings.windUnit == WindUnit.matchUnits
              ? '${settings.windUnit.label} · '
                    '${settings.resolvedWindUnit.detail}'
              : settings.windUnit.label,
          options: WindUnit.values,
          labelOf: (unit) => unit.label,
          detailOf: (unit) => unit.detail,
          onChanged: controller.setWindUnit,
        ),
        _ChoiceTile<PrecipitationUnit>(
          icon: Icons.water_drop_outlined,
          title: 'Rain and snow',
          value: settings.precipitationUnit,
          valueLabel: settings.precipitationUnit == PrecipitationUnit.matchUnits
              ? '${settings.precipitationUnit.label} · '
                    '${settings.resolvedPrecipitationUnit.detail}'
              : settings.precipitationUnit.label,
          options: PrecipitationUnit.values,
          labelOf: (unit) => unit.label,
          detailOf: (unit) => unit.detail,
          onChanged: controller.setPrecipitationUnit,
        ),

        const _SubsectionHeader('Date and time'),
        _ChoiceTile<DateStyle>(
          icon: Icons.calendar_today_outlined,
          title: 'Date format',
          value: settings.dateStyle,
          // Every label is an example of itself, so the current value shown
          // here is already a preview.
          valueLabel: formatDate(DateTime.now()),
          options: DateStyle.values,
          labelOf: (style) => style.label,
          onChanged: controller.setDateStyle,
        ),
        _ChoiceTile<ClockStyle>(
          icon: Icons.schedule,
          title: 'Time format',
          value: settings.clockStyle,
          valueLabel:
              '${settings.clockStyle.label} · ${formatTime(DateTime.now())}',
          options: ClockStyle.values,
          labelOf: (style) => style.label,
          detailOf: (style) => style.example,
          onChanged: controller.setClockStyle,
        ),
      ],
    );
  }
}

// ── Driver and van ────────────────────────────────────────────────────────

class DriverSettingsPage extends StatelessWidget {
  const DriverSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;

    return _SettingsPage(
      title: 'Driver and van',
      children: [
        _TextTile(
          icon: Icons.badge_outlined,
          title: 'Your name',
          value: settings.driverName,
          hint: 'Used to greet you on the home screen',
          onChanged: controller.setDriverName,
        ),
        _TextTile(
          icon: Icons.local_shipping_outlined,
          title: 'Van or round',
          value: settings.vehicleLabel,
          hint: 'e.g. LT21 KXR, or Round 4',
          onChanged: controller.setVehicleLabel,
        ),
        const _SubsectionHeader('Van tag (NFC)'),
        _NfcSection(
          vehicleLabel: settings.vehicleLabel,
          clockOnWithTag: settings.nfcClockOn,
          onClockOnWithTagChanged: controller.setNfcClockOn,
        ),
      ],
    );
  }
}

// ── Shift and breaks ──────────────────────────────────────────────────────

class ShiftSettingsPage extends StatelessWidget {
  const ShiftSettingsPage({super.key});

  /// The on-shift notification needs the same grant arrival alerts do, and
  /// posts immediately rather than waiting for the next clock-on.
  Future<void> _setOnShiftNotification(
    BuildContext context,
    SettingsController controller,
    bool value,
  ) async {
    AppHaptics.select();
    final shifts = context.read<ShiftController>();
    final messenger = ScaffoldMessenger.of(context);

    if (!value) {
      await controller.setOnShiftNotification(false);
      await shifts.refreshNotification();
      return;
    }

    final notifications = NotificationService();
    final granted =
        await notifications.hasPermission() ||
        await notifications.requestPermission();

    await controller.setOnShiftNotification(granted);
    await shifts.refreshNotification();
    if (granted) return;

    messenger.showSnackBar(
      const SnackBar(content: Text('Notifications are blocked for this app.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;

    return _SettingsPage(
      title: 'Shift and breaks',
      children: [
        const TimesheetTile(),
        _ChoiceTile<Currency>(
          icon: Icons.payments_outlined,
          title: 'Currency',
          value: settings.currency,
          valueLabel:
              '${settings.currency.label} · ${settings.currency.symbol}',
          options: Currency.values,
          labelOf: (currency) => currency.label,
          detailOf: (currency) => currency.format(12.5),
          onChanged: controller.setCurrency,
        ),
        _RateTile(
          icon: Icons.schedule,
          title: 'Hourly rate',
          hint: 'What an hour worked is worth',
          value: settings.hourlyRate,
          currency: settings.currency,
          suffix: 'per hour',
          onChanged: controller.setHourlyRate,
        ),
        _RateTile(
          icon: Icons.route_outlined,
          title: 'Mileage rate',
          hint: settings.distanceUnit == DistanceUnit.imperial
              ? 'What you claim per mile — 0.45 is the current HMRC rate'
              : 'What you claim per kilometre',
          value: settings.mileageRate,
          currency: settings.currency,
          suffix: settings.distanceUnit == DistanceUnit.imperial
              ? 'per mile'
              : 'per km',
          onChanged: controller.setMileageRate,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.notifications_none),
          title: const Text('Show a notification while on shift'),
          subtitle: const Text(
            'A silent, ongoing reminder that you are still clocked on.',
          ),
          value: settings.onShiftNotification,
          onChanged: (value) =>
              _setOnShiftNotification(context, controller, value),
        ),
        _ChoiceTile<int>(
          icon: Icons.free_breakfast_outlined,
          title: 'Break reminder',
          value: settings.breakReminderMinutes,
          valueLabel: settings.breakReminderMinutes == 0
              ? 'Off'
              : 'After ${_hours(settings.breakReminderMinutes)}',
          options: const [0, 120, 180, 240, 300, 360],
          labelOf: (minutes) =>
              minutes == 0 ? 'Off' : 'After ${_hours(minutes)}',
          detailOf: (minutes) => minutes == 0
              ? 'Never remind me.'
              : 'Once per stretch, not once a day.',
          onChanged: controller.setBreakReminderMinutes,
        ),
      ],
    );
  }
}

// ── Manifest ──────────────────────────────────────────────────────────────

class ManifestSettingsPage extends StatelessWidget {
  const ManifestSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;

    return _SettingsPage(
      title: 'Manifest',
      children: [
        _ChoiceTile<StopSort>(
          icon: settings.defaultSort.icon,
          title: 'Default order',
          value: settings.defaultSort,
          valueLabel: settings.defaultSort.label,
          options: StopSort.values,
          labelOf: (sort) => sort.label,
          detailOf: (sort) => sort.detail,
          onChanged: controller.setDefaultSort,
        ),
      ],
    );
  }
}

// ── Tracking ──────────────────────────────────────────────────────────────

class TrackingSettingsPage extends StatelessWidget {
  const TrackingSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;
    final isTracking = context.select<TrackingController, bool>(
      (tracking) => tracking.isTracking,
    );

    return _SettingsPage(
      title: 'Tracking',
      children: [
        _ChoiceTile<TrackingAccuracy>(
          icon: Icons.gps_fixed,
          title: 'GPS accuracy',
          value: settings.accuracy,
          valueLabel: settings.accuracy.label,
          options: TrackingAccuracy.values,
          labelOf: (accuracy) => accuracy.label,
          detailOf: (accuracy) => accuracy.detail,
          onChanged: controller.setAccuracy,
          // Changing the fix rate mid-trip would mean tearing down and
          // restarting the position stream, losing the notification and
          // possibly a fix or two. Not worth it — it can wait for the next
          // stop.
          enabled: !isTracking,
          disabledNote: 'Finish the current trip to change this.',
        ),
        SwitchListTile(
          secondary: const Icon(Icons.play_circle_outline),
          title: const Text('Start the next stop automatically'),
          subtitle: const Text(
            'Closing out a stop begins recording the next one without asking.',
          ),
          isThreeLine: true,
          value: settings.autoTrackNextStop,
          onChanged: (value) {
            AppHaptics.select();
            controller.setAutoTrackNextStop(value);
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.screen_lock_portrait_outlined),
          title: const Text('Keep screen on while tracking'),
          subtitle: const Text('Handy on a windscreen mount. Costs battery.'),
          value: settings.keepScreenOn,
          onChanged: (value) {
            AppHaptics.select();
            controller.setKeepScreenOn(value);
          },
        ),
        _ChoiceTile<MapFollowMode>(
          icon: Icons.map_outlined,
          title: 'Map behaviour',
          value: settings.followMode,
          valueLabel: settings.followMode.label,
          options: MapFollowMode.values,
          labelOf: (mode) => mode.label,
          detailOf: (mode) => mode.detail,
          onChanged: controller.setFollowMode,
        ),
      ],
    );
  }
}

// ── Proof of delivery ─────────────────────────────────────────────────────

class ProofSettingsPage extends StatelessWidget {
  const ProofSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;

    return _SettingsPage(
      title: 'Proof of delivery',
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.swipe_right_outlined),
          title: const Text('Slide to complete a delivery'),
          subtitle: const Text('Stops a stray tap closing out the wrong stop.'),
          value: settings.confirmWithSlide,
          onChanged: (value) {
            AppHaptics.select();
            controller.setConfirmWithSlide(value);
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.photo_camera_outlined),
          title: const Text('Require a proof photo'),
          subtitle: const Text('Will not let a stop be closed without one.'),
          value: settings.requireProofPhoto,
          onChanged: (value) {
            AppHaptics.select();
            controller.setRequireProofPhoto(value);
          },
        ),
        _ChoiceTile<SignatureMode>(
          icon: Icons.draw_outlined,
          title: 'Signature',
          value: settings.signatureMode,
          valueLabel: settings.signatureMode.label,
          options: SignatureMode.values,
          labelOf: (mode) => mode.label,
          detailOf: (mode) => mode.detail,
          onChanged: controller.setSignatureMode,
        ),
      ],
    );
  }
}

// ── Alerts and feedback ───────────────────────────────────────────────────

class AlertsSettingsPage extends StatelessWidget {
  const AlertsSettingsPage({super.key});

  /// Turning arrival alerts on is meaningless without the notification
  /// permission, and Android 13+ can refuse it. Asking and then ignoring the
  /// answer left the switch reading "on" while no alert could ever arrive, so
  /// a refusal puts the switch back and says why.
  Future<void> _setArrivalAlerts(
    BuildContext context,
    SettingsController controller,
    bool value,
  ) async {
    AppHaptics.select();
    final messenger = ScaffoldMessenger.of(context);

    if (!value) {
      await controller.setArrivalAlerts(false);
      return;
    }

    final notifications = NotificationService();
    final granted =
        await notifications.hasPermission() ||
        await notifications.requestPermission();

    await controller.setArrivalAlerts(granted);
    if (granted) return;

    messenger.showSnackBar(
      SnackBar(
        content: const Text(
          'Notifications are blocked, so arrival alerts cannot be delivered.',
        ),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: () => context.read<LocationService>().openSettings(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;

    return _SettingsPage(
      title: 'Alerts and feedback',
      children: [
        const _SubsectionHeader('Arrival'),
        SwitchListTile(
          secondary: const Icon(Icons.notifications_active_outlined),
          title: const Text('Arrival alerts'),
          subtitle: Text(
            'Tell me when I get within '
            '${settings.arrivalRadiusMeters}m of a stop.',
          ),
          value: settings.arrivalAlerts,
          onChanged: (value) => _setArrivalAlerts(context, controller, value),
        ),
        if (settings.arrivalAlerts)
          _ChoiceTile<int>(
            icon: Icons.adjust,
            title: 'Arrival radius',
            value: settings.arrivalRadiusMeters,
            valueLabel: '${settings.arrivalRadiusMeters} m',
            options: const [50, 100, 150, 300, 500],
            labelOf: (meters) => '$meters m',
            detailOf: (meters) => switch (meters) {
              50 => 'At the door. Can be missed in a built-up area.',
              100 => 'Tight.',
              150 => 'The right street. Recommended.',
              300 => 'A little early — useful on fast roads.',
              _ => 'Well ahead of the stop.',
            },
            onChanged: controller.setArrivalRadius,
          ),

        const _SubsectionHeader('Feedback'),
        SwitchListTile(
          secondary: const Icon(Icons.vibration),
          title: const Text('Haptics'),
          subtitle: const Text('Buzz on start, delivery and errors.'),
          value: settings.hapticsEnabled,
          onChanged: (value) async {
            await controller.setHapticsEnabled(value);
            // Fire after enabling so the driver feels what they just switched
            // on.
            if (value) await AppHaptics.delivered();
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.celebration_outlined),
          title: const Text('Celebrate deliveries'),
          subtitle: const Text('Show the summary after closing a stop.'),
          value: settings.celebrateDeliveries,
          onChanged: (value) {
            AppHaptics.select();
            controller.setCelebrateDeliveries(value);
          },
        ),
      ],
    );
  }
}

// ── Weather ───────────────────────────────────────────────────────────────

class WeatherSettingsPage extends StatelessWidget {
  const WeatherSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;

    return _SettingsPage(
      title: 'Weather',
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.wb_cloudy_outlined),
          title: const Text('Show driving conditions'),
          subtitle: const Text(
            'The only feature that leaves the device: it sends your rough '
            'position to Open-Meteo to fetch the forecast.',
          ),
          isThreeLine: true,
          value: settings.showWeather,
          onChanged: (value) {
            AppHaptics.select();
            controller.setShowWeather(value);
          },
        ),
        if (settings.showWeather)
          ListTile(
            leading: const Icon(Icons.straighten),
            title: const Text('Weather units'),
            subtitle: Text(
              'Temperature, wind and rain · '
              '${settings.usesFahrenheit ? '°F' : '°C'}, '
              '${settings.resolvedWindUnit.detail}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const UnitsSettingsPage()),
            ),
          ),
      ],
    );
  }
}

// ── Permissions ───────────────────────────────────────────────────────────

class PermissionsSettingsPage extends StatefulWidget {
  const PermissionsSettingsPage({super.key});

  @override
  State<PermissionsSettingsPage> createState() =>
      _PermissionsSettingsPageState();
}

class _PermissionsSettingsPageState extends State<PermissionsSettingsPage> {
  LocationReadiness? _readiness;
  bool _backgroundGranted = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final location = context.read<LocationService>();
    // checkPermission rather than ensureReady: opening this screen should
    // report the current state, not fire a permission prompt at someone who
    // came to look.
    final readiness = await location.currentReadiness();
    final background = await location.hasBackgroundPermission();
    if (mounted) {
      setState(() {
        _readiness = readiness;
        _backgroundGranted = background;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsPage(
      title: 'Permissions',
      children: [
        _PermissionTile(
          readiness: _readiness,
          backgroundGranted: _backgroundGranted,
          onRefresh: _refresh,
        ),
      ],
    );
  }
}

// ── Data ──────────────────────────────────────────────────────────────────

class DataSettingsPage extends StatefulWidget {
  const DataSettingsPage({super.key});

  @override
  State<DataSettingsPage> createState() => _DataSettingsPageState();
}

class _DataSettingsPageState extends State<DataSettingsPage> {
  bool _exporting = false;

  Future<void> _exportCsv() => _export(
    (service) => service.exportStopsCsv(),
    describe: 'Stops exported',
  );

  Future<void> _exportGpx() => _export(
    (service) => service.exportTrailsGpx(),
    describe: 'Routes exported',
  );

  /// Writes the file and tells the driver where it went.
  ///
  /// The path is the whole point — an export nobody can find is not an export
  /// — so it is shown in full rather than as "done".
  Future<void> _export(
    Future<File> Function(ExportService) run, {
    required String describe,
  }) async {
    final service = ExportService(context.read<DeliveryRepository>());
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);

    try {
      final file = await run(service);
      if (!mounted) return;
      await AppHaptics.delivered();
      messenger.showSnackBar(
        SnackBar(
          content: Text('$describe to ${p.basename(file.path)}'),
          action: SnackBarAction(
            label: 'Share',
            onPressed: () => SharePlus.instance.share(
              ShareParams(
                files: [XFile(file.path)],
                text: 'Delivery export from Logistics',
              ),
            ),
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      await AppHaptics.error();
      messenger.showSnackBar(
        SnackBar(content: Text('Could not export: $error')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Both data actions are destructive and irreversible, so both go through an
  /// explicit confirmation naming exactly what goes.
  Future<void> _clearHistory() async {
    final repository = context.read<DeliveryRepository>();
    final deliveries = context.read<DeliveryController>();

    final confirmed = await confirmDestructive(
      context,
      title: 'Clear history?',
      detail:
          'Closed stops, their recorded routes and their proof photos are '
          'deleted from this device. Stops still to do are untouched.',
      action: 'Clear',
    );
    if (!confirmed || !mounted) return;

    final removed = await repository.deleteClosedDeliveries();
    await deliveries.refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          removed == 0
              ? 'Nothing to clear.'
              : 'Cleared $removed closed '
                    '${removed == 1 ? 'stop' : 'stops'}.',
        ),
      ),
    );
  }

  Future<void> _startFreshDay() async {
    final repository = context.read<DeliveryRepository>();
    final deliveries = context.read<DeliveryController>();
    final location = context.read<LocationService>();

    final confirmed = await confirmDestructive(
      context,
      title: 'Start a fresh day?',
      detail:
          'Every stop, route and photo currently on this device is deleted, '
          'and a new manifest is generated around your position.',
      action: 'Start fresh',
    );
    if (!confirmed || !mounted) return;

    await repository.deleteEverything();

    LatLng? origin;
    try {
      if (await location.currentReadiness() == LocationReadiness.ready) {
        final fix = await location.lastKnownPosition();
        if (fix != null) origin = LatLng(fix.latitude, fix.longitude);
      }
    } catch (_) {
      // Seeds against the fallback origin instead.
    }

    await SeedData.ensureSeeded(repository, origin: origin);
    await deliveries.load();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('New day seeded.')));
  }

  @override
  Widget build(BuildContext context) {
    final isTracking = context.select<TrackingController, bool>(
      (tracking) => tracking.isTracking,
    );

    return _SettingsPage(
      title: 'Data',
      children: [
        const _SubsectionHeader('Export'),
        ListTile(
          leading: const Icon(Icons.table_view_outlined),
          title: const Text('Export stops as CSV'),
          subtitle: const Text(
            'One row per stop with the distance recorded getting to it. Opens '
            'in any spreadsheet.',
          ),
          isThreeLine: true,
          trailing: _exporting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right),
          onTap: _exporting ? null : _exportCsv,
        ),
        ListTile(
          leading: const Icon(Icons.timeline_outlined),
          title: const Text('Export routes as GPX'),
          subtitle: const Text(
            'Your recorded trails, one track per trip. Reads in any mapping '
            'tool.',
          ),
          isThreeLine: true,
          trailing: _exporting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right),
          onTap: _exporting ? null : _exportGpx,
        ),

        const _SubsectionHeader('Delete'),
        ListTile(
          leading: const Icon(Icons.cleaning_services_outlined),
          title: const Text('Clear history'),
          subtitle: const Text(
            'Removes closed stops, their recorded routes and their photos. '
            'Open stops are kept.',
          ),
          isThreeLine: true,
          onTap: _clearHistory,
        ),
        ListTile(
          leading: const Icon(Icons.restart_alt_outlined),
          title: const Text('Start a fresh day'),
          subtitle: const Text(
            'Wipes everything and seeds a new manifest around you.',
          ),
          onTap: isTracking ? null : _startFreshDay,
          enabled: !isTracking,
        ),
      ],
    );
  }
}

// ── About ─────────────────────────────────────────────────────────────────

class AboutSettingsPage extends StatelessWidget {
  const AboutSettingsPage({super.key});

  /// Shows the walkthrough again on demand.
  ///
  /// Nothing is deleted — it is a re-read, not a factory reset, so the flag is
  /// cleared and immediately set again around the replay. If the driver backs
  /// out halfway, the next launch does not ambush them with it.
  Future<void> _replayOnboarding(BuildContext context) async {
    const preferences = AppPreferences();
    await preferences.setOnboardingComplete(false);
    if (!context.mounted) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (routeContext) => OnboardingScreen(
          onEnable: () async {
            await context.read<LocationService>().ensureReady();
            if (routeContext.mounted) Navigator.of(routeContext).pop();
          },
          onSkip: () => Navigator.of(routeContext).pop(),
        ),
      ),
    );

    await preferences.setOnboardingComplete(true);
  }

  Future<void> _confirmReset(
    BuildContext context,
    SettingsController controller,
  ) async {
    final confirmed = await showAppSheet<bool>(
      context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHeader(
              title: 'Reset settings?',
              subtitle:
                  'Theme, units, haptics and tracking options go back to '
                  'their defaults. Your deliveries and history are left '
                  'alone.',
              icon: Icons.restart_alt,
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: () => Navigator.of(sheetContext).pop(true),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text('Reset'),
            ),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );

    if (confirmed ?? false) {
      await controller.resetToDefaults();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Settings reset')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();

    return _SettingsPage(
      title: 'About',
      children: [
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Version'),
          subtitle: Text(currentRelease.version),
        ),
        ListTile(
          leading: const Icon(Icons.auto_awesome_outlined),
          title: const Text("What's new"),
          subtitle: Text(currentRelease.headline),
          onTap: () => WhatsNewSheet.show(context, currentRelease),
        ),
        ListTile(
          leading: const Icon(Icons.restart_alt),
          title: const Text('Replay the introduction'),
          subtitle: const Text('Go through the first-run walkthrough again.'),
          onTap: () => _replayOnboarding(context),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Open source licences'),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'Logistics',
            applicationVersion: currentRelease.version,
          ),
        ),
        const Divider(height: 32),
        ListTile(
          leading: Icon(
            Icons.restart_alt,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(
            'Reset settings',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          subtitle: const Text('Deliveries and history are not touched.'),
          onTap: () => _confirmReset(context, controller),
        ),
      ],
    );
  }
}

/// Shared destructive confirmation: names what is about to go, and puts the
/// action on an error-coloured button.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String detail,
  required String action,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final confirmed = await showAppSheet<bool>(
    context,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: title,
            subtitle: detail,
            icon: Icons.warning_amber_rounded,
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: () => Navigator.of(sheetContext).pop(true),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            child: Text(action),
          ),
          TextButton(
            onPressed: () => Navigator.of(sheetContext).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );
  return confirmed ?? false;
}

/// A settings row backed by a short free-text value.
class _TextTile extends StatelessWidget {
  const _TextTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.hint,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String value;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(
        value.isEmpty ? 'Not set' : value,
        style: value.isEmpty
            ? theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              )
            : null,
      ),
      trailing: const Icon(Icons.edit_outlined, size: 18),
      onTap: () => _edit(context),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final controller = TextEditingController(text: value);
    final result = await showAppSheet<String>(
      context,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          24 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(title: title, icon: icon),
            const SizedBox(height: 18),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (text) => Navigator.of(sheetContext).pop(text),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => Navigator.of(sheetContext).pop(controller.text),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result != null) onChanged(result);
  }
}

/// A rate in money, edited in a sheet with a numeric keypad.
///
/// Zero is a first-class value, not an empty field: it means "do not show me
/// money", which is the right default for a salaried driver and for anyone who
/// has not decided yet.
class _RateTile extends StatelessWidget {
  const _RateTile({
    required this.icon,
    required this.title,
    required this.hint,
    required this.value,
    required this.currency,
    required this.suffix,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String hint;
  final double value;
  final Currency currency;

  /// "per hour", "per mile" — what the figure is measured against.
  final String suffix;

  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unset = value <= 0;

    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(
        unset
            ? 'Not set — no figure on the timesheet'
            : '${currency.format(value)} $suffix',
        style: unset
            ? theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              )
            : null,
      ),
      trailing: const Icon(Icons.edit_outlined, size: 18),
      onTap: () => _edit(context),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final controller = TextEditingController(
      text: value <= 0 ? '' : value.toStringAsFixed(2),
    );

    final result = await showAppSheet<String>(
      context,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          24 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(title: title, subtitle: hint, icon: icon),
            const SizedBox(height: 18),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                prefixText: '${currency.symbol} ',
                suffixText: suffix,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (text) => Navigator.of(sheetContext).pop(text),
            ),
            const SizedBox(height: 10),
            Text(
              'Leave it empty to keep money off the timesheet altogether.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => Navigator.of(sheetContext).pop(controller.text),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null) return;

    // A comma is what half the world types for a decimal point, and rejecting
    // it silently would look like the field is broken.
    final cleaned = result.trim().replaceAll(',', '.');
    onChanged(cleaned.isEmpty ? 0 : (double.tryParse(cleaned) ?? 0));
  }
}

/// The van tag, end to end: whether the hardware can do it, whether the driver
/// wants to be asked for a tag when clocking on, writing one, and checking
/// that a written tag actually reads back.
///
/// Entirely optional — everything in the app works without a tag — so the
/// section explains what it buys rather than presenting it as setup to
/// complete, and it stays legible on a phone with no NFC at all.
class _NfcSection extends StatefulWidget {
  const _NfcSection({
    required this.vehicleLabel,
    required this.clockOnWithTag,
    required this.onClockOnWithTagChanged,
  });

  final String vehicleLabel;
  final bool clockOnWithTag;
  final ValueChanged<bool> onClockOnWithTagChanged;

  @override
  State<_NfcSection> createState() => _NfcSectionState();
}

class _NfcSectionState extends State<_NfcSection> {
  NfcReadiness? _readiness;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final readiness = await context.read<NfcService>().readiness();
    if (mounted) setState(() => _readiness = readiness);
  }

  /// Hands the tap straight to the tag sheet: the radar, the "hold it there"
  /// prompt, the written confirmation and the "this tag will never work"
  /// answer all live in one place, rather than as a row that spins and then
  /// fires a snackbar the driver has already stopped looking at.
  Future<void> _write() async {
    final label = widget.vehicleLabel.trim();
    if (label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Set "Van or round" above first — it goes on the tag.'),
        ),
      );
      return;
    }

    await NfcWriteSheet.show(context, label: label);
  }

  /// Reads a tag back without clocking anyone on, so a driver can confirm the
  /// sticker works before relying on it at six in the morning.
  Future<void> _test() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await NfcScanSheet.show(
      context,
      title: 'Test your tag',
      subtitle:
          'Reads the tag and tells you what is on it. Nothing is clocked on '
          'or changed.',
      manualLabel: 'Done',
    );
    if (result == null || !mounted) return;

    if (result case NfcSheetTag(:final tag)) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Reads as "${tag.label}". This tag will clock you on.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final readiness = _readiness;
    final usable = readiness == NfcReadiness.ready;

    return Column(
      children: [
        ListTile(
          leading: switch (readiness) {
            null => const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            NfcReadiness.ready => Icon(Icons.nfc, color: scheme.primary),
            _ => Icon(Icons.nfc_outlined, color: scheme.onSurfaceVariant),
          },
          title: const Text('NFC'),
          subtitle: Text(switch (readiness) {
            null => 'Checking this phone…',
            NfcReadiness.ready =>
              'Ready. A tag is optional — every button still works without '
                  'one.',
            NfcReadiness.disabled =>
              'Switched off in system settings. Turn NFC on there, then check '
                  'again.',
            NfcReadiness.unsupported =>
              'This phone has no NFC hardware. Clock on with the button '
                  'instead — nothing else is affected.',
          }),
          isThreeLine: readiness != null,
          trailing: readiness == NfcReadiness.disabled
              ? TextButton(onPressed: _check, child: const Text('Check again'))
              : null,
        ),

        SwitchListTile(
          secondary: const Icon(Icons.touch_app_outlined),
          title: const Text('Ask for a tag when clocking on'),
          subtitle: Text(
            widget.clockOnWithTag
                ? 'Clocking on opens the tag reader, with a button to start '
                      'without one.'
                : 'Clocking on starts your shift straight away.',
          ),
          isThreeLine: widget.clockOnWithTag,
          value: widget.clockOnWithTag,
          onChanged: (value) {
            AppHaptics.select();
            widget.onClockOnWithTagChanged(value);
          },
        ),

        ListTile(
          leading: const Icon(Icons.edit_note_outlined),
          title: const Text('Write a van tag'),
          subtitle: Text(
            widget.vehicleLabel.trim().isEmpty
                ? 'Set "Van or round" above first — that is what goes on the '
                      'tag.'
                : 'Writes "${widget.vehicleLabel}" onto a blank NDEF tag.',
          ),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
          onTap: usable ? _write : null,
          enabled: usable,
        ),

        ListTile(
          leading: const Icon(Icons.wifi_tethering),
          title: const Text('Test a tag'),
          subtitle: const Text(
            'Check a sticker reads correctly without clocking on.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: usable ? _test : null,
          enabled: usable,
        ),
      ],
    );
  }
}

/// A group inside a page, for the places where one screen would otherwise
/// carry a dozen unrelated rows.
class _SubsectionHeader extends StatelessWidget {
  const _SubsectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
      child: Text(
        title,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// A tile that opens a sheet of radio options.
class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.valueLabel,
    required this.options,
    required this.labelOf,
    required this.onChanged,
    this.detailOf,
    this.enabled = true,
    this.disabledNote,
  });

  final IconData icon;
  final String title;
  final T value;
  final String valueLabel;
  final List<T> options;
  final String Function(T) labelOf;
  final String Function(T)? detailOf;
  final ValueChanged<T> onChanged;
  final bool enabled;
  final String? disabledNote;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(
        enabled ? valueLabel : '$valueLabel · ${disabledNote ?? ''}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: enabled ? () => _pick(context) : null,
    );
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showAppSheet<T>(
      context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SheetHeader(title: title, icon: icon),
            ),
            RadioGroup<T>(
              groupValue: value,
              onChanged: (selected) => Navigator.of(sheetContext).pop(selected),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final option in options)
                    RadioListTile<T>(
                      value: option,
                      title: Text(labelOf(option)),
                      subtitle: detailOf == null
                          ? null
                          : Text(detailOf!(option)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (picked != null && picked != value) {
      await AppHaptics.select();
      onChanged(picked);
    }
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.readiness,
    required this.backgroundGranted,
    required this.onRefresh,
  });

  final LocationReadiness? readiness;
  final bool backgroundGranted;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = readiness;

    if (state == null) {
      return const ListTile(
        leading: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text('Checking location permission…'),
      );
    }

    final ready = state == LocationReadiness.ready;

    return Column(
      children: [
        ListTile(
          leading: Icon(
            ready ? Icons.check_circle : Icons.error_outline,
            color: ready ? scheme.primary : scheme.error,
          ),
          title: const Text('Location'),
          subtitle: Text(ready ? 'Granted' : state.message),
          trailing: state.isFixableInSettings
              ? TextButton(
                  onPressed: () async {
                    final location = context.read<LocationService>();
                    if (state == LocationReadiness.serviceDisabled) {
                      await location.openLocationSettings();
                    } else {
                      await location.openSettings();
                    }
                    await onRefresh();
                  },
                  child: const Text('Fix'),
                )
              : null,
        ),
        ListTile(
          leading: Icon(
            backgroundGranted ? Icons.check_circle : Icons.schedule,
            color: backgroundGranted ? scheme.primary : scheme.onSurfaceVariant,
          ),
          title: const Text('Background location'),
          subtitle: Text(
            backgroundGranted
                ? 'Granted — tracking survives a locked screen.'
                : 'Not granted. Tracking still runs via the notification, but '
                      'Android may throttle it once the screen is off for a '
                      'while.',
          ),
          isThreeLine: !backgroundGranted,
          trailing: backgroundGranted
              ? null
              : TextButton(
                  onPressed: () async {
                    await context
                        .read<LocationService>()
                        .requestBackgroundPermission();
                    await onRefresh();
                  },
                  child: const Text('Allow'),
                ),
        ),
      ],
    );
  }
}
