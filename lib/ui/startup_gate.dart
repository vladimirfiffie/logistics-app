import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../data/delivery_repository.dart';
import '../data/seed_data.dart';
import '../release_notes.dart';
import '../services/app_preferences.dart';
import '../services/location_service.dart';
import '../state/delivery_controller.dart';
import '../state/tracking_controller.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';
import 'whats_new_sheet.dart';

enum _Stage { checking, onboarding, ready }

/// Decides what the driver sees on launch.
///
/// Two things have to happen before the shell is useful: the manifest needs to
/// exist (first run seeds one), and any trip left recording by a previous
/// process needs picking back up.
class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  _Stage _stage = _Stage.checking;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final deliveries = context.read<DeliveryController>();
    await deliveries.load();
    if (!mounted) return;

    if (deliveries.deliveries.isEmpty) {
      setState(() => _stage = _Stage.onboarding);
      return;
    }

    await context.read<TrackingController>().restore();
    if (!mounted) return;
    setState(() => _stage = _Stage.ready);
    await _maybeShowWhatsNew(isFreshInstall: false);
  }

  /// Shows the changelog once per version, after the shell is on screen.
  ///
  /// The seen-version marker is written whether or not the sheet is shown, so
  /// a fresh install is not greeted with a changelog and the *next* update
  /// still gets one.
  Future<void> _maybeShowWhatsNew({required bool isFreshInstall}) async {
    const preferences = AppPreferences();
    final current = currentRelease;
    final lastSeen = await preferences.lastSeenVersion();

    final show = shouldShowWhatsNew(
      lastSeenVersion: lastSeen,
      currentVersion: current.version,
      isFreshInstall: isFreshInstall,
    );
    await preferences.setLastSeenVersion(current.version);

    if (show && mounted) {
      await WhatsNewSheet.show(context, current);
    }
  }

  /// Seeds the first manifest. With location granted, the stops are placed
  /// around wherever the driver actually is; otherwise they fall back to a
  /// fixed city centre.
  Future<void> _seedAndEnter({required bool withLocation}) async {
    setState(() => _isBusy = true);

    final repository = context.read<DeliveryRepository>();
    final location = context.read<LocationService>();
    final deliveries = context.read<DeliveryController>();
    final tracking = context.read<TrackingController>();

    LatLng? origin;
    if (withLocation) {
      try {
        if (await location.ensureReady() == LocationReadiness.ready) {
          final fix =
              await location.lastKnownPosition() ??
              await location.currentPosition();
          origin = LatLng(fix.latitude, fix.longitude);
        }
      } catch (_) {
        // No fix in time — seed against the fallback origin instead of
        // blocking the driver at a spinner.
      }
    }

    await SeedData.ensureSeeded(repository, origin: origin);
    await deliveries.load();
    await tracking.restore();

    if (mounted) {
      setState(() {
        _isBusy = false;
        _stage = _Stage.ready;
      });
      // Records the version without showing the sheet — see
      // shouldShowWhatsNew.
      await _maybeShowWhatsNew(isFreshInstall: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_stage) {
      _Stage.checking => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      _Stage.onboarding => OnboardingScreen(
        isBusy: _isBusy,
        onEnable: () => _seedAndEnter(withLocation: true),
        onSkip: () => _seedAndEnter(withLocation: false),
      ),
      _Stage.ready => const HomeScreen(),
    };
  }
}
