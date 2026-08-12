import 'dart:async';

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

  /// Drives the running clock on the shift card.
  ///
  /// [Shift.duration] is measured against `DateTime.now()`, so without a tick
  /// of its own the card freezes at whatever it read when something else
  /// happened to rebuild it — which, on a quiet round, is "0s" for the rest of
  /// the day.
  Timer? _ticker;

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
    _syncTicker();
    notifyListeners();
  }

  /// Clocks on. Returns the shift, or null if the write failed — in which case
  /// [error] says why.
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
      // Most likely cause: a shift is open in the database that this
      // controller does not know about, because `load()` failed or never ran.
      // Adopting it beats leaving the driver tapping a button that silently
      // does nothing.
      final adopted = await _adoptOpenShift();
      if (adopted != null) return adopted;
      _error = error;
      return null;
    } finally {
      _isBusy = false;
      _syncTicker();
      notifyListeners();
    }
  }

  Future<Shift?> end() async {
    final active = _current;
    if (active == null || !active.isActive) return null;

    _isBusy = true;
    _error = null;
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
      _syncTicker();
      notifyListeners();
    }
  }

  /// Picks up a shift already open in storage. Returns null if there is none.
  Future<Shift?> _adoptOpenShift() async {
    try {
      final open = await _repository.activeShift();
      if (open == null) return null;
      _current = open;
      _history = await _repository.fetchShifts();
      _error = null;
      return open;
    } catch (_) {
      return null;
    }
  }

  /// Runs the clock only while one is actually needed.
  void _syncTicker() {
    if (isOnShift) {
      _ticker ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => notifyListeners(),
      );
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }
}
