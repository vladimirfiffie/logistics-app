import 'package:flutter/foundation.dart';

import '../data/delivery_repository.dart';
import '../models/shift.dart';

/// Clocking on and off.
///
/// Deliberately dumb about *how* a shift was started — tag or button — so the
/// NFC layer stays entirely optional. The controller records which it was and
/// otherwise treats them identically.
class ShiftController extends ChangeNotifier {
  ShiftController(this._repository);

  final DeliveryRepository _repository;

  Shift? _current;
  List<Shift> _history = const [];
  bool _isBusy = false;
  Object? _error;

  Shift? get current => _current;
  List<Shift> get history => _history;
  bool get isBusy => _isBusy;
  Object? get error => _error;

  bool get isOnShift => _current?.isActive ?? false;

  Duration get elapsed => _current?.duration ?? Duration.zero;

  /// Total time clocked on across every finished shift.
  Duration get totalWorked => _history
      .where((shift) => !shift.isActive)
      .fold(Duration.zero, (sum, shift) => sum + shift.duration);

  Future<void> load() async {
    try {
      _current = await _repository.activeShift();
      _history = await _repository.fetchShifts();
      _error = null;
    } catch (error) {
      _error = error;
    }
    notifyListeners();
  }

  /// Clocks on. Returns the shift, or null if one was already running or the
  /// write failed.
  Future<Shift?> start({
    String? vehicleLabel,
    bool startedByTag = false,
  }) async {
    if (isOnShift) return null;
    _isBusy = true;
    _error = null;
    notifyListeners();

    try {
      final shift = await _repository.startShift(
        vehicleLabel: vehicleLabel,
        startedByTag: startedByTag,
      );
      _current = shift;
      _history = await _repository.fetchShifts();
      return shift;
    } catch (error) {
      _error = error;
      return null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<Shift?> end() async {
    final active = _current;
    if (active == null || !active.isActive) return null;

    _isBusy = true;
    notifyListeners();
    try {
      final finished = await _repository.endShift(active.id);
      _current = null;
      _history = await _repository.fetchShifts();
      return finished;
    } catch (error) {
      _error = error;
      return null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }
}
