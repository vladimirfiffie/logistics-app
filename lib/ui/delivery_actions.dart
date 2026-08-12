import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/delivery.dart';
import '../state/delivery_controller.dart';
import '../state/tracking_controller.dart';
import 'complete_delivery_sheet.dart';
import 'failure_reason_dialog.dart';

/// Closing out a stop is reachable from both the detail screen and the live
/// tracking view, and both have to end the trip before writing the outcome.
/// Keeping it in one place stops the two paths drifting apart.
///
/// Returns true if the stop was closed, false if the driver backed out.
Future<bool> completeDelivery(BuildContext context, Delivery delivery) async {
  final proof = await CompleteDeliverySheet.show(context, delivery);
  if (proof == null || !context.mounted) return false;

  final deliveries = context.read<DeliveryController>();
  await _endTripFor(context, delivery);
  await deliveries.markDelivered(
    delivery,
    recipientName: proof.recipientName,
    proofPhotoPath: proof.photoPath,
  );
  return true;
}

/// Records a stop that could not be completed. Returns true if a reason was
/// captured.
Future<bool> failDelivery(BuildContext context, Delivery delivery) async {
  final reason = await FailureReasonDialog.show(context);
  if (reason == null || !context.mounted) return false;

  final deliveries = context.read<DeliveryController>();
  await _endTripFor(context, delivery);
  await deliveries.markFailed(delivery, reason: reason);
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
