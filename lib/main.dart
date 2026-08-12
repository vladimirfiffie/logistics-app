import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/local_delivery_repository.dart';
import 'services/app_haptics.dart';
import 'state/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The one place storage is chosen. Swapping in an API-backed
  // DeliveryRepository later is a change to this line and nothing else.
  final database = await AppDatabase.open();

  // Loaded before the first frame so the app opens in the driver's chosen
  // theme rather than flashing light and snapping to dark.
  final settings = SettingsController();
  await settings.load();

  // Pre-warms the haptic generators. Deliberately not awaited — it is a
  // latency optimisation, and startup should not block on it.
  unawaited(AppHaptics.warmUp());

  runApp(
    LogisticsApp(
      repository: LocalDeliveryRepository(database),
      settingsController: settings,
    ),
  );
}
