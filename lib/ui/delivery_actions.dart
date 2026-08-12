import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/delivery_repository.dart';
import '../models/delivery.dart';
import '../services/app_haptics.dart';
import '../state/delivery_controller.dart';
import '../state/settings_controller.dart';
import '../state/tracking_controller.dart';
import 'complete_delivery_sheet.dart';
import 'delivery_outcome_sheet.dart';
import 'failure_reason_sheet.dart';

/// Closing out a stop is reachable from the detail sheet, the live tracking
/// view and the home tab, and all of them have to end the trip before writing
/// the outcome. Keeping it in one place stops those paths drifting apart.
///
/// Returns true if the stop was closed, false if the driver backed out.
Future<bool> completeDelivery(BuildContext context, Delivery delivery) async {
  final settings = context.read<SettingsController>().settings;

  // The sheet enforces the photo requirement itself, so the driver is told
  // before filling the form in rather than rejected after tapping the button.
  final proof = await CompleteDeliverySheet.show(
    context,
    delivery,
    requirePhoto: settings.requireProofPhoto,
  );
  if (proof == null || !context.mounted) return false;

  final deliveries = context.read<DeliveryController>();
  final repository = context.read<DeliveryRepository>();

  await _endTripFor(context, delivery);
  await deliveries.markDelivered(
    delivery,
    recipientName: proof.recipientName,
    proofPhotoPath: proof.photoPath,
  );
  await AppHaptics.delivered();

  if (!settings.celebrateDeliveries || !context.mounted) return true;

  // Read back the trip so the celebration shows the finished odometer rather
  // than the running one.
  final trip = await repository.tripForDelivery(delivery.id);
  if (!context.mounted) return true;

  final remaining = deliveries.openStops;
  await DeliveryOutcomeSheet.show(
    context,
    delivery: delivery,
    trip: trip,
    unit: settings.distanceUnit,
    remainingStops: remaining.length,
    nextStop: remaining.isEmpty ? null : remaining.first,
  );
  return true;
}

/// Records a stop that could not be completed. Returns true if a reason was
/// captured.
Future<bool> failDelivery(BuildContext context, Delivery delivery) async {
  final reason = await FailureReasonSheet.show(context);
  if (reason == null || !context.mounted) return false;

  final settings = context.read<SettingsController>().settings;
  final deliveries = context.read<DeliveryController>();
  final repository = context.read<DeliveryRepository>();

  await _endTripFor(context, delivery);
  await deliveries.markFailed(delivery, reason: reason);
  await AppHaptics.deliveryFailed();

  if (!settings.celebrateDeliveries || !context.mounted) return true;

  // The same confirmation as a successful stop. Silently dropping back to the
  // list after recording a failure leaves the driver unsure it registered.
  final trip = await repository.tripForDelivery(delivery.id);
  if (!context.mounted) return true;

  final remaining = deliveries.openStops;
  await DeliveryOutcomeSheet.show(
    context,
    delivery: delivery,
    trip: trip,
    unit: settings.distanceUnit,
    remainingStops: remaining.length,
    nextStop: remaining.isEmpty ? null : remaining.first,
    failureReason: reason,
  );
  return true;
}

/// Stops the recorder if this stop is the one being tracked, then drops the
/// finished trip out of the live view.
Future<void> _endTripFor(BuildContext context, Delivery delivery) async {
  final tracking = context.read<TrackingController>();
  if (tracking.isTracking && tracking.trip?.deliveryId == delivery.id) {
    await tracking.stop();
  }
  tracking.clear();
}
