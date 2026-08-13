import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logistics_app/models/app_settings.dart';
import 'package:logistics_app/models/delivery.dart';
import 'package:logistics_app/models/shift.dart';
import 'package:logistics_app/state/settings_controller.dart';
import 'package:logistics_app/ui/shift_summary_sheet.dart';
import 'package:logistics_app/ui/widgets/delivery_card.dart';
import 'package:logistics_app/ui/widgets/status_chip.dart';
import 'package:provider/provider.dart';

/// Pumps [child] inside enough of the app to make a widget that reads
/// settings behave the way it does in the running app.
///
/// Settled rather than pumped once: several of these screens animate in, and
/// asserting against a half-played fade tests the animation rather than the
/// content.
Future<void> _pump(WidgetTester tester, Widget child) async {
  final settings = SettingsController();
  await tester.pumpWidget(
    ChangeNotifierProvider<SettingsController>.value(
      value: settings,
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Delivery _stop({
  int parcels = 3,
  int scanned = 0,
  int attempt = 1,
  DeliveryStatus status = DeliveryStatus.pending,
}) => Delivery(
  id: 'd1',
  reference: 'LG-1040',
  customerName: 'Harlow & Sons Hardware',
  address: '14 Bridgewater Road',
  latitude: 51.52,
  longitude: -0.10,
  status: status,
  scheduledFor: DateTime(2026, 8, 12, 9),
  parcelCount: parcels,
  parcelsScanned: scanned,
  attempt: attempt,
);

void main() {
  group('DeliveryCard', () {
    testWidgets('shows the parcel count until something is scanned off', (
      tester,
    ) async {
      await _pump(tester, DeliveryCard(delivery: _stop(), onTap: () {}));

      expect(find.text('LG-1040'), findsOneWidget);
      expect(find.text('3 parcels'), findsOneWidget);
    });

    testWidgets('switches to the scanned count once labels are read', (
      tester,
    ) async {
      await _pump(
        tester,
        DeliveryCard(delivery: _stop(scanned: 2), onTap: () {}),
      );

      expect(find.text('2/3 scanned'), findsOneWidget);
      expect(find.text('3 parcels'), findsNothing);
    });

    testWidgets('marks a stop that has already been tried', (tester) async {
      await _pump(
        tester,
        DeliveryCard(delivery: _stop(attempt: 2), onTap: () {}),
      );

      expect(find.text('Attempt 2'), findsOneWidget);
    });
  });

  group('StatusChip', () {
    testWidgets('names every status it can be given', (tester) async {
      for (final status in DeliveryStatus.values) {
        await _pump(tester, StatusChip(status));
        expect(find.text(status.label), findsOneWidget);
      }
    });
  });

  group('ShiftSummarySheet', () {
    ShiftSummary summary({
      Duration worked = const Duration(hours: 7, minutes: 45),
      Duration breaks = const Duration(minutes: 30),
      double distance = 42000,
      int delivered = 18,
      int closed = 20,
    }) => (
      shift: Shift(
        id: 's1',
        startedAt: DateTime(2026, 8, 12, 8),
        endedAt: DateTime(2026, 8, 12, 16, 15),
        vehicleLabel: 'LT21 KXR',
      ),
      worked: worked,
      breaks: breaks,
      stopsClosed: closed,
      delivered: delivered,
      distanceMeters: distance,
    );

    testWidgets('reads out the day without any rates set', (tester) async {
      await _pump(
        tester,
        ShiftSummarySheet(summary: summary(), settings: const AppSettings()),
      );

      expect(find.text("That's the day"), findsOneWidget);
      expect(find.text('7h 45m'), findsOneWidget);
      expect(find.text('18'), findsOneWidget);
      expect(find.text('of 20 closed'), findsOneWidget);
      expect(find.text('LT21 KXR'), findsOneWidget);
      // No rates, so no money anywhere.
      expect(find.text('Hours'), findsNothing);
      expect(find.text('Total'), findsNothing);
    });

    testWidgets('adds up hours and mileage when rates are set', (tester) async {
      await _pump(
        tester,
        ShiftSummarySheet(
          summary: summary(
            worked: const Duration(hours: 8),
            distance: 32186.9, // 20 miles
          ),
          settings: const AppSettings(
            distanceUnit: DistanceUnit.imperial,
            hourlyRate: 12.5,
            mileageRate: 0.45,
          ),
        ),
      );

      // 8h at 12.50, 20 miles at 0.45, and the two added together.
      expect(find.text('£100.00'), findsOneWidget);
      expect(find.text('£9.00'), findsOneWidget);
      expect(find.text('£109.00'), findsOneWidget);
    });

    testWidgets('says so when no break was taken', (tester) async {
      await _pump(
        tester,
        ShiftSummarySheet(
          summary: summary(breaks: Duration.zero),
          settings: const AppSettings(),
        ),
      );

      expect(find.text('worked, no breaks taken'), findsOneWidget);
    });
  });
}
