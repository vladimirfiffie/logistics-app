import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications.
///
/// Separate from the tracking foreground-service notification, which
/// geolocator owns — this is for things the driver should be told while they
/// are looking at something else, chiefly that they have arrived.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const _arrivalChannelId = 'arrival';
  static const _summaryChannelId = 'summary';
  static const _shiftChannelId = 'shift';

  /// Distinct ids so an arrival alert never replaces the day's summary.
  static const _arrivalId = 1001;
  static const _summaryId = 1002;
  static const _shiftId = 1003;

  bool _ready = false;

  Future<void> initialise() async {
    if (_ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _ready = true;
    } catch (error) {
      debugPrint('notifications unavailable: $error');
    }
  }

  /// Android 13+ gates notifications behind a runtime grant. Returns false if
  /// it was refused or the platform could not be asked.
  Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return false;
    try {
      return await android.requestNotificationsPermission() ?? false;
    } catch (error) {
      debugPrint('notification permission request failed: $error');
      return false;
    }
  }

  Future<bool> hasPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return false;
    try {
      return await android.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// "You have arrived" — fired once per trip when the driver comes inside
  /// the arrival radius. High importance because the whole point is to reach
  /// someone whose phone is on a mount showing a different app.
  Future<void> showArrival({
    required String reference,
    required String customerName,
    required String address,
  }) => _show(
    id: _arrivalId,
    channelId: _arrivalChannelId,
    channelName: 'Arrival alerts',
    channelDescription: 'Tells you when you reach a delivery stop.',
    title: 'Arriving at $customerName',
    body: '$reference · $address',
    importance: Importance.high,
    priority: Priority.high,
  );

  /// End-of-round summary.
  Future<void> showRoundComplete({
    required int stops,
    required String distance,
  }) => _show(
    id: _summaryId,
    channelId: _summaryChannelId,
    channelName: 'Round summary',
    channelDescription: 'A recap when every stop is closed out.',
    title: 'Round complete',
    body: '$stops ${stops == 1 ? 'stop' : 'stops'} closed · $distance driven',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  /// Ongoing "you are on the clock" notification.
  ///
  /// Silent and low importance: it is a status line, not an alert. Ongoing so
  /// it cannot be swiped away by accident — the whole point is that it is
  /// still there when the driver checks two hours later, behind whatever nav
  /// app is on screen.
  Future<void> showOnShift({
    required DateTime since,
    String? vehicleLabel,
    bool onBreak = false,
  }) {
    final started =
        '${since.hour.toString().padLeft(2, '0')}:'
        '${since.minute.toString().padLeft(2, '0')}';
    return _show(
      id: _shiftId,
      channelId: _shiftChannelId,
      channelName: 'On shift',
      channelDescription: 'Shows for as long as you are clocked on.',
      title: onBreak ? 'On a break' : 'On shift',
      body: [
        'Clocked on at $started',
        if (vehicleLabel != null && vehicleLabel.isNotEmpty) vehicleLabel,
      ].join(' · '),
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
    );
  }

  /// "You have been going a while." Fires once when the configured stretch is
  /// up; the shift notification carries on regardless.
  Future<void> showBreakDue({required Duration worked}) => _show(
    id: _shiftId + 1,
    channelId: _shiftChannelId,
    channelName: 'On shift',
    channelDescription: 'Shows for as long as you are clocked on.',
    title: 'Time for a break',
    body: "You've been on shift for ${worked.inHours}h without one.",
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  Future<void> cancelArrival() => _cancel(_arrivalId);

  Future<void> cancelOnShift() async {
    await _cancel(_shiftId);
    await _cancel(_shiftId + 1);
  }

  Future<void> _show({
    required int id,
    required String channelId,
    required String channelName,
    required String channelDescription,
    required String title,
    required String body,
    required Importance importance,
    required Priority priority,
    bool ongoing = false,
    bool autoCancel = true,
  }) async {
    await initialise();
    if (!_ready) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDescription,
            importance: importance,
            priority: priority,
            // Tapping an alert should clear it, not leave the driver swiping
            // away stale notifications at the end of a round. Ongoing status
            // notifications opt out — they are cancelled by the code that
            // posted them.
            autoCancel: autoCancel,
            ongoing: ongoing,
            silent: ongoing,
          ),
        ),
      );
    } catch (error) {
      // A missing channel or a revoked permission must never interrupt a
      // delivery.
      debugPrint('could not post notification: $error');
    }
  }

  Future<void> _cancel(int id) async {
    try {
      await _plugin.cancel(id: id);
    } catch (_) {
      // Nothing to cancel, or the plugin is unavailable.
    }
  }
}
