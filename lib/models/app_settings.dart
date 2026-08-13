import 'package:flutter/material.dart';

/// Distance and speed units. Drivers in the US and UK read miles; the rest of
/// the world reads kilometres, and getting it wrong makes every readout in the
/// app useless to them.
///
/// Named as the two systems rather than as their distance unit: "Metric" and
/// "Imperial" is what a driver is looking for when they go hunting for this,
/// and the units themselves read better as the line underneath.
enum DistanceUnit {
  metric('Metric', 'Kilometres and km/h'),
  imperial('Imperial', 'Miles and mph');

  const DistanceUnit(this.label, this.detail);

  final String label;
  final String detail;

  /// The short form, for somewhere there is no room for a sentence.
  String get shortLabel => switch (this) {
    DistanceUnit.metric => 'km',
    DistanceUnit.imperial => 'mi',
  };
}

/// Temperature on the weather card.
///
/// [matchUnits] keeps it tied to [DistanceUnit] — the common case, since a
/// driver reading miles is usually reading Fahrenheit. The explicit values
/// exist because that pairing is not universal: the UK reads miles and
/// Celsius.
enum TemperatureUnit {
  matchUnits('Match my units', 'Celsius with km, Fahrenheit with miles'),
  celsius('Celsius', 'Always °C'),
  fahrenheit('Fahrenheit', 'Always °F');

  const TemperatureUnit(this.label, this.detail);

  final String label;
  final String detail;
}

/// Wind speed on the weather card.
///
/// Its own setting rather than following [DistanceUnit]: a driver reading
/// kilometres may still think of wind in mph, and anyone near the coast reads
/// it in knots. [matchUnits] keeps the old behaviour for anyone who does not
/// care.
enum WindUnit {
  matchUnits('Match my units', 'km/h with km, mph with miles'),
  kmh('Kilometres per hour', 'km/h'),
  mph('Miles per hour', 'mph'),
  metresPerSecond('Metres per second', 'm/s'),
  knots('Knots', 'kn');

  const WindUnit(this.label, this.detail);

  final String label;
  final String detail;
}

/// Rain and snow on the weather card.
enum PrecipitationUnit {
  matchUnits('Match my units', 'mm with km, inches with miles'),
  millimetres('Millimetres', 'mm'),
  inches('Inches', 'in');

  const PrecipitationUnit(this.label, this.detail);

  final String label;
  final String detail;
}

/// What the timesheet counts money in.
///
/// A symbol, not an exchange rate: nothing is converted anywhere, this only
/// decides what is printed in front of the figure.
enum Currency {
  pound('Pound', '£'),
  dollar('Dollar', r'$'),
  euro('Euro', '€'),
  zloty('Złoty', 'zł'),
  krona('Krona', 'kr');

  const Currency(this.label, this.symbol);

  final String label;
  final String symbol;

  String format(double amount) {
    final figure = amount.toStringAsFixed(2);
    // A trailing symbol reads right for the currencies that are written that
    // way; putting "zł" in front of the number looks wrong to anyone who uses
    // it.
    return switch (this) {
      Currency.zloty || Currency.krona => '$figure $symbol',
      _ => '$symbol$figure',
    };
  }
}

/// How a date reads across the app. The pattern is fed straight to `intl`.
enum DateStyle {
  dayMonth('Wed 12 Aug', 'EEE d MMM'),
  dayMonthYear('12 Aug 2026', 'd MMM yyyy'),
  numericDmy('12/08/2026', 'dd/MM/yyyy'),
  numericMdy('08/12/2026', 'MM/dd/yyyy'),
  iso('2026-08-12', 'yyyy-MM-dd');

  const DateStyle(this.label, this.pattern);

  /// Doubles as the example shown in the picker — the label *is* the format.
  final String label;

  final String pattern;
}

enum ClockStyle {
  twentyFour('24-hour', 'HH:mm', '17:45'),
  twelveHour('12-hour', 'h:mm a', '5:45 PM');

  const ClockStyle(this.label, this.pattern, this.example);

  final String label;
  final String pattern;
  final String example;
}

enum ThemeChoice {
  system('Follow system', 'Auto', Icons.brightness_auto_outlined),
  light('Light', 'Light', Icons.light_mode_outlined),
  dark('Dark', 'Dark', Icons.dark_mode_outlined);

  const ThemeChoice(this.label, this.shortLabel, this.icon);

  final String label;

  /// For a segmented control, where three full labels will not fit across a
  /// phone.
  final String shortLabel;

  final IconData icon;

  ThemeMode get mode => switch (this) {
    ThemeChoice.system => ThemeMode.system,
    ThemeChoice.light => ThemeMode.light,
    ThemeChoice.dark => ThemeMode.dark,
  };
}

/// How hard to push the GPS while a trip is recording.
///
/// This is the one setting with a real cost attached: [precise] gives the
/// tightest trail and the fastest speed readings, and flattens the battery on
/// a long round.
enum TrackingAccuracy {
  precise(
    'Precise',
    'Best trail and speed. Heaviest on battery.',
    distanceFilterMeters: 5,
    intervalSeconds: 3,
  ),
  balanced(
    'Balanced',
    'Accurate enough for a delivery round. Recommended.',
    distanceFilterMeters: 10,
    intervalSeconds: 5,
  ),
  saver(
    'Battery saver',
    'Coarser trail, noticeably longer battery life.',
    distanceFilterMeters: 40,
    intervalSeconds: 20,
  );

  const TrackingAccuracy(
    this.label,
    this.detail, {
    required this.distanceFilterMeters,
    required this.intervalSeconds,
  });

  final String label;
  final String detail;

  /// Metres the driver must move before a new fix is emitted.
  final int distanceFilterMeters;

  /// Android's requested interval between fixes.
  final int intervalSeconds;

  Duration get interval => Duration(seconds: intervalSeconds);
}

/// Accent colours. Named for the trade rather than the hex value — a driver
/// picking a theme is not thinking in Material seed colours.
enum AccentColor {
  fleet('Fleet blue', Color(0xFF1565C0)),
  hiVis('Hi-vis', Color(0xFFF57F17)),
  depot('Depot green', Color(0xFF2E7D32)),
  cargo('Cargo red', Color(0xFFC62828)),
  night('Night violet', Color(0xFF5E35B1)),
  steel('Steel', Color(0xFF455A64));

  const AccentColor(this.label, this.seed);

  final String label;
  final Color seed;
}

/// Default order for the manifest. Lives here rather than in the tab so the
/// driver's choice survives a restart.
enum StopSort {
  time('Time', 'The slots as dispatched.', Icons.schedule),
  distance('Distance', 'Nearest to you first.', Icons.near_me_outlined),
  route(
    'Best route',
    'Shortest way round, without jumping a time slot. A suggestion, not a '
        'plan.',
    Icons.alt_route,
  ),
  name('A–Z', 'By customer name.', Icons.sort_by_alpha);

  const StopSort(this.label, this.detail, this.icon);

  final String label;
  final String detail;
  final IconData icon;

  /// Distance and route both measure from the driver, so both need a fix.
  bool get needsFix => this == StopSort.distance || this == StopSort.route;
}

/// Whether closing out a stop asks for a signature.
enum SignatureMode {
  off('Never', 'No signature pad on the completion sheet.'),
  optional('Optional', 'A button to open the pad when you want one.'),
  required('Required', 'A stop cannot be closed without one.');

  const SignatureMode(this.label, this.detail);

  final String label;
  final String detail;
}

/// How the live map behaves by default when a trip starts.
enum MapFollowMode {
  follow('Follow me', 'Keep the map centred on your position.'),
  free('Free', 'Leave the map where you put it.');

  const MapFollowMode(this.label, this.detail);

  final String label;
  final String detail;
}

/// Everything the driver can change. Immutable; [copyWith] produces the next
/// value and the controller persists it.
@immutable
class AppSettings {
  const AppSettings({
    this.theme = ThemeChoice.system,
    this.accent = AccentColor.fleet,
    this.amoled = false,
    this.distanceUnit = DistanceUnit.metric,
    this.hapticsEnabled = true,
    this.keepScreenOn = false,
    this.accuracy = TrackingAccuracy.balanced,
    this.confirmWithSlide = true,
    this.driverName = '',
    this.vehicleLabel = '',
    this.followMode = MapFollowMode.follow,
    this.celebrateDeliveries = true,
    this.requireProofPhoto = false,
    this.arrivalAlerts = true,
    this.arrivalRadiusMeters = 150,
    this.showWeather = true,
    this.temperatureUnit = TemperatureUnit.matchUnits,
    this.windUnit = WindUnit.matchUnits,
    this.precipitationUnit = PrecipitationUnit.matchUnits,
    this.dateStyle = DateStyle.dayMonth,
    this.clockStyle = ClockStyle.twentyFour,
    this.nfcClockOn = true,
    this.defaultSort = StopSort.time,
    this.signatureMode = SignatureMode.optional,
    this.autoTrackNextStop = false,
    this.onShiftNotification = true,
    this.breakReminderMinutes = 0,
    this.currency = Currency.pound,
    this.hourlyRate = 0,
    this.mileageRate = 0,
  });

  final ThemeChoice theme;
  final AccentColor accent;

  /// Pure-black surfaces in dark mode. On an OLED screen the pixels are
  /// genuinely off, which is a real battery saving on a phone that spends all
  /// day on a windscreen mount.
  final bool amoled;

  final DistanceUnit distanceUnit;
  final bool hapticsEnabled;

  /// Hold the screen awake while a trip records. Off by default — it is a
  /// battery decision, and most drivers pocket the phone.
  final bool keepScreenOn;

  final TrackingAccuracy accuracy;

  /// Require a slide rather than a tap to complete a delivery. On by default:
  /// a tap is easy to trigger by accident in a moving van, and closing out
  /// the wrong stop is annoying to undo.
  final bool confirmWithSlide;

  /// Shown on the home tab. Empty means "no greeting by name".
  final String driverName;

  /// Van or round identifier, e.g. "LT21 KXR" or "Round 4". Shown on the home
  /// tab so the driver can tell at a glance they opened the right thing.
  final String vehicleLabel;

  /// Whether the live map starts out following the driver.
  final MapFollowMode followMode;

  /// Show the success animation after a delivery. On by default, but it is a
  /// couple of seconds a driver doing eighty drops a day may not want.
  final bool celebrateDeliveries;

  /// Block completing a stop until a photo has been taken. Off by default —
  /// it is a depot policy, not a universal one.
  final bool requireProofPhoto;

  /// Notify when the driver comes within [arrivalRadiusMeters] of the stop.
  /// Worth having on: the phone is usually showing a nav app, not this one.
  final bool arrivalAlerts;

  /// Fires once per trip. 150m is roughly "the right street" rather than "the
  /// right door" — tight enough to be useful, loose enough that a GPS wobble
  /// in a built-up area does not miss it entirely.
  final int arrivalRadiusMeters;

  /// Driving conditions on the home tab.
  ///
  /// The only feature that sends anything off the device: fetching it means
  /// giving Open-Meteo the driver's approximate position. Rounded to three
  /// decimals (about 100m) and switchable for exactly that reason.
  final bool showWeather;

  /// Temperature on the weather card. Separate from [distanceUnit] because
  /// the two do not always pair the way you would expect.
  final TemperatureUnit temperatureUnit;

  /// Wind speed on the weather card.
  final WindUnit windUnit;

  /// Rain and snow on the weather card.
  final PrecipitationUnit precipitationUnit;

  /// How dates read everywhere in the app.
  final DateStyle dateStyle;

  /// 24- or 12-hour clock. Delivery slots are the most-read text in the app,
  /// so reading them in the wrong convention is a genuine nuisance.
  final ClockStyle clockStyle;

  /// Offer the van tag when clocking on. Switched off, the button clocks on
  /// straight away — the right behaviour on a phone with no NFC, or for a
  /// driver who never stuck a tag in the van.
  final bool nfcClockOn;

  /// Which order the manifest opens in.
  final StopSort defaultSort;

  /// Whether the completion sheet offers, demands, or hides the signature pad.
  final SignatureMode signatureMode;

  /// Start recording the next stop the moment one is closed out. Off by
  /// default: it starts the GPS without being asked, which should be the
  /// driver's decision rather than a surprise.
  final bool autoTrackNextStop;

  /// A persistent notification for as long as the driver is clocked on. The
  /// app is usually behind a nav app, and "am I still on the clock?" is worth
  /// answering from the shade.
  final bool onShiftNotification;

  /// Remind the driver to take a break after this many minutes on shift.
  /// Zero switches it off.
  final int breakReminderMinutes;

  /// What the timesheet prints its figures in.
  final Currency currency;

  /// Paid per hour worked, breaks already subtracted. Zero means "do not show
  /// me money", which is the default — plenty of drivers are salaried, and a
  /// wrong number on a timesheet is worse than no number.
  final double hourlyRate;

  /// Claimed per mile or per kilometre driven, following [distanceUnit]. The
  /// UK's HMRC rate is 45p a mile at the time of writing; the US IRS rate is
  /// per mile too. Zero switches the mileage line off.
  final double mileageRate;

  /// Whether the timesheet has anything to say about money.
  bool get showsEarnings => hourlyRate > 0 || mileageRate > 0;

  /// Which unit the weather card should actually render, with
  /// [TemperatureUnit.matchUnits] resolved against [distanceUnit].
  bool get usesFahrenheit => switch (temperatureUnit) {
    TemperatureUnit.celsius => false,
    TemperatureUnit.fahrenheit => true,
    TemperatureUnit.matchUnits => distanceUnit == DistanceUnit.imperial,
  };

  /// [windUnit] with `matchUnits` resolved, so nothing downstream has to know
  /// about the distance setting.
  WindUnit get resolvedWindUnit => switch (windUnit) {
    WindUnit.matchUnits =>
      distanceUnit == DistanceUnit.imperial ? WindUnit.mph : WindUnit.kmh,
    final WindUnit chosen => chosen,
  };

  PrecipitationUnit get resolvedPrecipitationUnit =>
      switch (precipitationUnit) {
        PrecipitationUnit.matchUnits =>
          distanceUnit == DistanceUnit.imperial
              ? PrecipitationUnit.inches
              : PrecipitationUnit.millimetres,
        final PrecipitationUnit chosen => chosen,
      };

  AppSettings copyWith({
    ThemeChoice? theme,
    AccentColor? accent,
    bool? amoled,
    DistanceUnit? distanceUnit,
    bool? hapticsEnabled,
    bool? keepScreenOn,
    TrackingAccuracy? accuracy,
    bool? confirmWithSlide,
    String? driverName,
    String? vehicleLabel,
    MapFollowMode? followMode,
    bool? celebrateDeliveries,
    bool? requireProofPhoto,
    bool? arrivalAlerts,
    int? arrivalRadiusMeters,
    bool? showWeather,
    TemperatureUnit? temperatureUnit,
    WindUnit? windUnit,
    PrecipitationUnit? precipitationUnit,
    DateStyle? dateStyle,
    ClockStyle? clockStyle,
    bool? nfcClockOn,
    StopSort? defaultSort,
    SignatureMode? signatureMode,
    bool? autoTrackNextStop,
    bool? onShiftNotification,
    int? breakReminderMinutes,
    Currency? currency,
    double? hourlyRate,
    double? mileageRate,
  }) => AppSettings(
    theme: theme ?? this.theme,
    accent: accent ?? this.accent,
    amoled: amoled ?? this.amoled,
    distanceUnit: distanceUnit ?? this.distanceUnit,
    hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
    keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    accuracy: accuracy ?? this.accuracy,
    confirmWithSlide: confirmWithSlide ?? this.confirmWithSlide,
    driverName: driverName ?? this.driverName,
    vehicleLabel: vehicleLabel ?? this.vehicleLabel,
    followMode: followMode ?? this.followMode,
    celebrateDeliveries: celebrateDeliveries ?? this.celebrateDeliveries,
    requireProofPhoto: requireProofPhoto ?? this.requireProofPhoto,
    arrivalAlerts: arrivalAlerts ?? this.arrivalAlerts,
    arrivalRadiusMeters: arrivalRadiusMeters ?? this.arrivalRadiusMeters,
    showWeather: showWeather ?? this.showWeather,
    temperatureUnit: temperatureUnit ?? this.temperatureUnit,
    windUnit: windUnit ?? this.windUnit,
    precipitationUnit: precipitationUnit ?? this.precipitationUnit,
    dateStyle: dateStyle ?? this.dateStyle,
    clockStyle: clockStyle ?? this.clockStyle,
    nfcClockOn: nfcClockOn ?? this.nfcClockOn,
    defaultSort: defaultSort ?? this.defaultSort,
    signatureMode: signatureMode ?? this.signatureMode,
    autoTrackNextStop: autoTrackNextStop ?? this.autoTrackNextStop,
    onShiftNotification: onShiftNotification ?? this.onShiftNotification,
    breakReminderMinutes: breakReminderMinutes ?? this.breakReminderMinutes,
    currency: currency ?? this.currency,
    hourlyRate: hourlyRate ?? this.hourlyRate,
    mileageRate: mileageRate ?? this.mileageRate,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.theme == theme &&
      other.accent == accent &&
      other.amoled == amoled &&
      other.distanceUnit == distanceUnit &&
      other.hapticsEnabled == hapticsEnabled &&
      other.keepScreenOn == keepScreenOn &&
      other.accuracy == accuracy &&
      other.confirmWithSlide == confirmWithSlide &&
      other.driverName == driverName &&
      other.vehicleLabel == vehicleLabel &&
      other.followMode == followMode &&
      other.celebrateDeliveries == celebrateDeliveries &&
      other.requireProofPhoto == requireProofPhoto &&
      other.arrivalAlerts == arrivalAlerts &&
      other.arrivalRadiusMeters == arrivalRadiusMeters &&
      other.showWeather == showWeather &&
      other.temperatureUnit == temperatureUnit &&
      other.windUnit == windUnit &&
      other.precipitationUnit == precipitationUnit &&
      other.dateStyle == dateStyle &&
      other.clockStyle == clockStyle &&
      other.nfcClockOn == nfcClockOn &&
      other.defaultSort == defaultSort &&
      other.signatureMode == signatureMode &&
      other.autoTrackNextStop == autoTrackNextStop &&
      other.onShiftNotification == onShiftNotification &&
      other.breakReminderMinutes == breakReminderMinutes &&
      other.currency == currency &&
      other.hourlyRate == hourlyRate &&
      other.mileageRate == mileageRate;

  @override
  int get hashCode => Object.hashAll([
    theme,
    accent,
    amoled,
    distanceUnit,
    hapticsEnabled,
    keepScreenOn,
    accuracy,
    confirmWithSlide,
    driverName,
    vehicleLabel,
    followMode,
    celebrateDeliveries,
    requireProofPhoto,
    arrivalAlerts,
    arrivalRadiusMeters,
    showWeather,
    temperatureUnit,
    windUnit,
    precipitationUnit,
    dateStyle,
    clockStyle,
    nfcClockOn,
    defaultSort,
    signatureMode,
    autoTrackNextStop,
    onShiftNotification,
    breakReminderMinutes,
    currency,
    hourlyRate,
    mileageRate,
  ]);
}
