import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/delivery_repository.dart';
import 'models/app_settings.dart';
import 'services/location_service.dart';
import 'services/weather_service.dart';
import 'state/delivery_controller.dart';
import 'state/settings_controller.dart';
import 'state/tracking_controller.dart';
import 'ui/startup_gate.dart';

/// Root widget. Everything below reaches storage and GPS through the two
/// providers declared here, which is what keeps the widget tree testable.
class LogisticsApp extends StatelessWidget {
  const LogisticsApp({
    super.key,
    required this.repository,
    required this.settingsController,
    this.locationService = const LocationService(),
  });

  final DeliveryRepository repository;

  /// Created and loaded before `runApp` so the first frame is already in the
  /// right theme, rather than flashing light and snapping to dark.
  final SettingsController settingsController;

  final LocationService locationService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<DeliveryRepository>.value(value: repository),
        Provider<LocationService>.value(value: locationService),
        Provider<WeatherService>(
          create: (_) => WeatherService(),
          dispose: (_, service) => service.dispose(),
        ),
        ChangeNotifierProvider<SettingsController>.value(
          value: settingsController,
        ),
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
            settings: () => settingsController.settings,
            onManifestChanged: () =>
                context.read<DeliveryController>().refresh(),
          ),
        ),
      ],
      // Rebuilds the whole app when the theme choice changes, which is the
      // one setting that cannot be read locally where it is used.
      child: Consumer<SettingsController>(
        builder: (context, controller, _) {
          final settings = controller.settings;
          return MaterialApp(
            title: 'Logistics',
            debugShowCheckedModeBanner: false,
            theme: _theme(Brightness.light, settings),
            darkTheme: _theme(Brightness.dark, settings),
            themeMode: settings.theme.mode,
            home: const StartupGate(),
          );
        },
      ),
    );
  }

  ThemeData _theme(Brightness brightness, AppSettings settings) {
    var scheme = ColorScheme.fromSeed(
      seedColor: settings.accent.seed,
      brightness: brightness,
    );

    // AMOLED only means anything in the dark. Overriding the surface ramp to
    // true black turns those pixels off entirely on an OLED panel, which is a
    // real saving on a phone that sits lit on a windscreen mount all day.
    // The container steps stay slightly raised so cards and sheets remain
    // distinguishable from the page behind them.
    final blackOut = settings.amoled && brightness == Brightness.dark;
    if (blackOut) {
      scheme = scheme.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF0A0A0A),
        surfaceContainer: const Color(0xFF121212),
        surfaceContainerHigh: const Color(0xFF1A1A1A),
        surfaceContainerHighest: const Color(0xFF222222),
      );
    }

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: blackOut ? Colors.black : null,
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
