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

  /// Distinct ids so an arrival alert never replaces the day's summary.
  static const _arrivalId = 1001;
  static const _summaryId = 1002;

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

  Future<void> cancelArrival() => _cancel(_arrivalId);

  Future<void> _show({
    required int id,
    required String channelId,
    required String channelName,
    required String channelDescription,
    required String title,
    required String body,
    required Importance importance,
    required Priority priority,
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
            // Auto-cancel: tapping it should clear it, not leave the driver
            // swiping away stale alerts at the end of a round.
            autoCancel: true,
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
