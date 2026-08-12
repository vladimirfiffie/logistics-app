import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/delivery_repository.dart';
import 'services/location_service.dart';
import 'state/delivery_controller.dart';
import 'state/tracking_controller.dart';
import 'ui/startup_gate.dart';

/// Root widget. Everything below reaches storage and GPS through the two
/// providers declared here, which is what keeps the widget tree testable.
class LogisticsApp extends StatelessWidget {
  const LogisticsApp({
    super.key,
    required this.repository,
    this.locationService = const LocationService(),
  });

  final DeliveryRepository repository;
  final LocationService locationService;

  static const _seedColor = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<DeliveryRepository>.value(value: repository),
        Provider<LocationService>.value(value: locationService),
        ChangeNotifierProvider<DeliveryController>(
          create: (_) => DeliveryController(repository),
        ),
        // Declared after DeliveryController so it can reach it: starting or
        // ending a trip changes a stop's status, and the manifest has to
        // re-read it.
        ChangeNotifierProvider<TrackingController>(
          create: (context) => TrackingController(
            repository: repository,
            locationService: locationService,
            onManifestChanged: () =>
                context.read<DeliveryController>().refresh(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Logistics',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: const StartupGate(),
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }
}
