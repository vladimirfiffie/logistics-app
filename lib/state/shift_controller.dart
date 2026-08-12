import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/delivery_repository.dart';
import '../models/app_settings.dart';
import '../models/shift.dart';
import '../models/shift_break.dart';
import '../services/notification_service.dart';

/// Clocking on and off.
///
/// Deliberately dumb about *how* a shift was started — tag or button — so the
/// NFC layer stays entirely optional. The controller records which it was and
/// otherwise treats them identically.
class ShiftController extends ChangeNotifier {
  ShiftController(
    this._repository, {
    AppSettings Function()? settings,
    NotificationService? notifications,
  }) : _settings = settings ?? _defaultSettings,
       _notifications = notifications ?? NotificationService();

  static AppSettings _defaultSettings() => const AppSettings();

  final DeliveryRepository _repository;

  /// Read lazily so a change made mid-shift takes effect without rewiring.
  final AppSettings Function() _settings;

  final NotificationService _notifications;

  /// Break reminders fire once per shift, not once per tick.
  bool _remindedAboutBreak = false;

  Shift? _current;
  List<Shift> _history = const [];
  bool _isBusy = false;
  Object? _error;

  ShiftBreak? _currentBreak;
  List<ShiftBreak> _breaks = const [];

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

  ShiftBreak? get currentBreak => _currentBreak;
  List<ShiftBreak> get breaks => _breaks;

  bool get isOnShift => _current?.isActive ?? false;

  bool get isOnBreak => _currentBreak?.isActive ?? false;

  Duration get elapsed => _current?.duration ?? Duration.zero;

  /// Time spent on breaks during the shift in progress.
  Duration get breakElapsed =>
      _breaks.fold(Duration.zero, (sum, taken) => sum + taken.duration);

  /// The shift clock minus its breaks — what the driver is actually paid for.
  /// Clamped at zero: clock skew must not produce a negative day.
  Duration get workedElapsed {
    final net = elapsed - breakElapsed;
    return net.isNegative ? Duration.zero : net;
  }

  /// Total time clocked on across every finished shift.
  Duration get totalWorked => _history
      .where((shift) => !shift.isActive)
      .fold(Duration.zero, (sum, shift) => sum + shift.duration);

  Future<void> load() async {
    try {
      _current = await _repository.activeShift();
      _history = await _repository.fetchShifts();
      await _loadBreaks();
      _error = null;
    } catch (error) {
      _error = error;
    }
    _syncTicker();
    unawaited(_syncNotification());
    notifyListeners();
  }

  Future<void> _loadBreaks() async {
    final shift = _current;
    if (shift == null) {
      _currentBreak = null;
      _breaks = const [];
      return;
    }
    _breaks = await _repository.breaksForShift(shift.id);
    _currentBreak = await _repository.activeBreak(shift.id);
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
      _currentBreak = null;
      _breaks = const [];
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
      _remindedAboutBreak = false;
      _syncTicker();
      unawaited(_syncNotification());
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
      _currentBreak = null;
      _breaks = const [];
      _history = await _repository.fetchShifts();
      return finished;
    } catch (error) {
      _error = error;
      return null;
    } finally {
      _isBusy = false;
      _syncTicker();
      unawaited(_syncNotification());
      notifyListeners();
    }
  }

  /// Starts a break. Returns null if there is no shift to take one from, or
  /// one is already running.
  Future<ShiftBreak?> startBreak({BreakKind kind = BreakKind.rest}) async {
    final shift = _current;
    if (shift == null || !shift.isActive || isOnBreak) return null;

    _isBusy = true;
    _error = null;
    notifyListeners();
    try {
      final taken = await _repository.startBreak(shift.id, kind: kind);
      _currentBreak = taken;
      _breaks = await _repository.breaksForShift(shift.id);
      return taken;
    } catch (error) {
      _error = error;
      return null;
    } finally {
      _isBusy = false;
      unawaited(_syncNotification());
      notifyListeners();
    }
  }

  Future<ShiftBreak?> endBreak() async {
    final running = _currentBreak;
    final shift = _current;
    if (running == null || !running.isActive || shift == null) return null;

    _isBusy = true;
    _error = null;
    notifyListeners();
    try {
      final finished = await _repository.endBreak(running.id);
      _currentBreak = null;
      _breaks = await _repository.breaksForShift(shift.id);
      return finished;
    } catch (error) {
      _error = error;
      return null;
    } finally {
      _isBusy = false;
      // A finished break resets the reminder, so a long second stretch is
      // flagged again rather than only once a day.
      _remindedAboutBreak = false;
      unawaited(_syncNotification());
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
      await _loadBreaks();
      _error = null;
      return open;
    } catch (_) {
      return null;
    }
  }

  /// Runs the clock only while one is actually needed.
  void _syncTicker() {
    if (isOnShift) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        _maybeRemindAboutBreak();
        notifyListeners();
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  /// Keeps the ongoing notification in step with the shift.
  ///
  /// Posted on state changes rather than on the one-second tick: re-posting a
  /// notification every second would be wasteful and would make the shade
  /// flicker. The body says when the shift started rather than how long it has
  /// run, so it stays true without being rewritten.
  Future<void> _syncNotification() async {
    final shift = _current;
    if (shift == null || !shift.isActive || !_settings().onShiftNotification) {
      await _notifications.cancelOnShift();
      return;
    }
    await _notifications.showOnShift(
      since: shift.startedAt,
      vehicleLabel: shift.vehicleLabel,
      onBreak: isOnBreak,
    );
  }

  void _maybeRemindAboutBreak() {
    if (_remindedAboutBreak || isOnBreak) return;
    final after = _settings().breakReminderMinutes;
    if (after <= 0) return;
    if (workedElapsed.inMinutes < after) return;

    // Set before the await so a burst of ticks cannot queue several.
    _remindedAboutBreak = true;
    _notifications.showBreakDue(worked: workedElapsed);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }

  /// Called when the driver turns the notification off in Settings, so it
  /// disappears immediately rather than at the next shift change.
  Future<void> refreshNotification() => _syncNotification();
}
