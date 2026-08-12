import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../release_notes.dart';
import '../services/app_haptics.dart';
import '../services/location_service.dart';
import '../state/settings_controller.dart';
import '../state/tracking_controller.dart';
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

          const _SectionHeader('Permissions'),
          _PermissionTile(
            readiness: _readiness,
            backgroundGranted: _backgroundGranted,
            onRefresh: _refreshPermissions,
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
