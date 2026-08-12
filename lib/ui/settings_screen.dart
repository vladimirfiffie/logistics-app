import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../data/delivery_repository.dart';
import '../data/seed_data.dart';
import '../models/app_settings.dart';
import '../models/van_tag.dart';
import '../release_notes.dart';
import '../services/app_haptics.dart';
import '../services/app_preferences.dart';
import '../services/location_service.dart';
import '../services/nfc_service.dart';
import '../services/notification_service.dart';
import '../state/delivery_controller.dart';
import '../state/settings_controller.dart';
import '../state/tracking_controller.dart';
import 'onboarding_screen.dart';
import 'whats_new_sheet.dart';
import 'widgets/app_sheet.dart';

/// Everything the driver can change, plus the permission state that decides
/// whether tracking can work at all.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  LocationReadiness? _readiness;
  bool _backgroundGranted = false;

  @override
  void initState() {
    super.initState();
    _refreshPermissions();
  }

  Future<void> _refreshPermissions() async {
    final location = context.read<LocationService>();
    // checkPermission rather than ensureReady: opening Settings should report
    // the current state, not fire a permission prompt at someone who came
    // here to change the theme.
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
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;
    final isTracking = context.select<TrackingController, bool>(
      (tracking) => tracking.isTracking,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const _SectionHeader('Appearance'),
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
          _ChoiceTile<DistanceUnit>(
            icon: Icons.straighten,
            title: 'Units',
            value: settings.distanceUnit,
            valueLabel: settings.distanceUnit.label,
            options: DistanceUnit.values,
            labelOf: (unit) => unit.label,
            detailOf: (unit) => unit.detail,
            onChanged: controller.setDistanceUnit,
          ),

          const _SectionHeader('Driver'),
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

          _TagTile(vehicleLabel: settings.vehicleLabel),

          const _SectionHeader('Tracking'),
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
            secondary: const Icon(Icons.screen_lock_portrait_outlined),
            title: const Text('Keep screen on while tracking'),
            subtitle: const Text('Handy on a windscreen mount. Costs battery.'),
            value: settings.keepScreenOn,
            onChanged: (value) {
              AppHaptics.select();
              controller.setKeepScreenOn(value);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.swipe_right_outlined),
            title: const Text('Slide to complete a delivery'),
            subtitle: const Text(
              'Stops a stray tap closing out the wrong stop.',
            ),
            value: settings.confirmWithSlide,
            onChanged: (value) {
              AppHaptics.select();
              controller.setConfirmWithSlide(value);
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

          const _SectionHeader('Notifications'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Arrival alerts'),
            subtitle: Text(
              'Tell me when I get within '
              '${settings.arrivalRadiusMeters}m of a stop.',
            ),
            value: settings.arrivalAlerts,
            onChanged: (value) async {
              AppHaptics.select();
              await controller.setArrivalAlerts(value);
              if (value) await NotificationService().requestPermission();
            },
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

          const _SectionHeader('Feedback'),
          SwitchListTile(
            secondary: const Icon(Icons.vibration),
            title: const Text('Haptics'),
            subtitle: const Text('Buzz on start, delivery and errors.'),
            value: settings.hapticsEnabled,
            onChanged: (value) async {
              await controller.setHapticsEnabled(value);
              // Fire after enabling so the driver feels what they just
              // switched on.
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

          const _SectionHeader('Weather'),
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

          const _SectionHeader('Permissions'),
          _PermissionTile(
            readiness: _readiness,
            backgroundGranted: _backgroundGranted,
            onRefresh: _refreshPermissions,
          ),

          const _SectionHeader('Data'),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('Clear history'),
            subtitle: const Text(
              'Removes closed stops and their recorded routes. Open stops '
              'are kept.',
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

          const _SectionHeader('About'),
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
            onTap: _replayOnboarding,
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
            onTap: () => _confirmReset(controller),
          ),
        ],
      ),
    );
  }

  /// Both data actions are destructive and irreversible, so both go through
  /// an explicit confirmation naming exactly what goes.
  Future<void> _clearHistory() async {
    final repository = context.read<DeliveryRepository>();
    final deliveries = context.read<DeliveryController>();

    final confirmed = await _confirmDestructive(
      title: 'Clear history?',
      detail:
          'Closed stops, their recorded routes and their proof photos are '
          'deleted from this device. Stops still to do are untouched.',
      action: 'Clear',
    );
    if (!confirmed) return;

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

    final confirmed = await _confirmDestructive(
      title: 'Start a fresh day?',
      detail:
          'Every stop, route and photo currently on this device is deleted, '
          'and a new manifest is generated around your position.',
      action: 'Start fresh',
    );
    if (!confirmed) return;

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

  /// Shows the walkthrough again on demand.
  ///
  /// Nothing is deleted — it is a re-read, not a factory reset, so the flag is
  /// cleared and immediately set again around the replay. If the driver backs
  /// out halfway, the next launch does not ambush them with it.
  Future<void> _replayOnboarding() async {
    const preferences = AppPreferences();
    await preferences.setOnboardingComplete(false);
    if (!mounted) return;

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
    if (mounted) await _refreshPermissions();
  }

  Future<bool> _confirmDestructive({
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

  Future<void> _confirmReset(SettingsController controller) async {
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Settings reset')));
      }
    }
  }
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

/// Writes a van tag. Entirely optional — everything works without one, so the
/// tile explains what it buys rather than presenting it as setup to complete.
class _TagTile extends StatefulWidget {
  const _TagTile({required this.vehicleLabel});

  final String vehicleLabel;

  @override
  State<_TagTile> createState() => _TagTileState();
}

class _TagTileState extends State<_TagTile> {
  NfcReadiness? _readiness;
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final readiness = await context.read<NfcService>().readiness();
    if (mounted) setState(() => _readiness = readiness);
  }

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

    final nfc = context.read<NfcService>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _writing = true);

    final problem = await nfc.writeVanTag(VanTag(label: label));

    if (!mounted) return;
    setState(() => _writing = false);
    if (problem == null) {
      await AppHaptics.delivered();
    } else {
      await AppHaptics.error();
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          problem ?? 'Tag written. Stick it somewhere you can reach.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final readiness = _readiness;
    final usable = readiness == NfcReadiness.ready;

    return ListTile(
      leading: _writing
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.nfc),
      title: const Text('Van tag'),
      subtitle: Text(switch (readiness) {
        null => 'Checking NFC…',
        NfcReadiness.ready when _writing =>
          'Hold the tag against the back of your phone.',
        NfcReadiness.ready =>
          'Optional. Write a sticker for the van, then tap it to clock on.',
        final NfcReadiness other =>
          '${other.message} Clock on by tapping '
              'the button instead.',
      }),
      isThreeLine: true,
      trailing: usable && !_writing
          ? TextButton(onPressed: _write, child: const Text('Write'))
          : null,
      onTap: usable && !_writing ? _write : null,
      enabled: usable,
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
                : 'Not granted. Tracking still runs via the notification, '
                      'but Android may throttle it once the screen is off '
                      'for a while.',
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
