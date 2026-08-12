import 'package:flutter/foundation.dart';

import '../data/delivery_repository.dart';
import '../models/delivery.dart';

/// Owns the driver's manifest: the list of stops and their statuses.
class DeliveryController extends ChangeNotifier {
  DeliveryController(this._repository);

  final DeliveryRepository _repository;

  List<Delivery> _deliveries = const [];
  bool _isLoading = false;
  Object? _error;

  List<Delivery> get deliveries => _deliveries;
  bool get isLoading => _isLoading;
  Object? get error => _error;

  /// Stops still to be done, earliest slot first.
  List<Delivery> get openStops =>
      _deliveries.where((d) => d.status.isOpen).toList();

  /// Closed stops, most recently finished first.
  List<Delivery> get closedStops {
    final closed = _deliveries.where((d) => !d.status.isOpen).toList();
    closed.sort((a, b) {
      final aTime = a.completedAt ?? a.scheduledFor;
      final bTime = b.completedAt ?? b.scheduledFor;
      return bTime.compareTo(aTime);
    });
    return closed;
  }

  int get remainingParcels =>
      openStops.fold(0, (sum, stop) => sum + stop.parcelCount);

  Delivery? byId(String id) {
    for (final delivery in _deliveries) {
      if (delivery.id == id) return delivery;
    }
    return null;
  }

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _deliveries = await _repository.fetchDeliveries();
    } catch (error) {
      _error = error;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Re-reads from storage without flipping the loading flag, so the list does
  /// not flash a spinner after an in-place change.
  Future<void> refresh() async {
    try {
      _deliveries = await _repository.fetchDeliveries();
      _error = null;
    } catch (error) {
      _error = error;
    }
    notifyListeners();
  }

  Future<void> markDelivered(
    Delivery delivery, {
    String? recipientName,
    String? proofPhotoPath,
  }) async {
    await _save(
      delivery.copyWith(
        status: DeliveryStatus.delivered,
        completedAt: DateTime.now(),
        recipientName: recipientName,
        proofPhotoPath: proofPhotoPath,
      ),
    );
  }

  Future<void> markFailed(Delivery delivery, {required String reason}) async {
    await _save(
      delivery.copyWith(
        status: DeliveryStatus.failed,
        completedAt: DateTime.now(),
        failureReason: reason,
      ),
    );
  }

  Future<void> _save(Delivery delivery) async {
    await _repository.saveDelivery(delivery);
    await refresh();
  }
}
