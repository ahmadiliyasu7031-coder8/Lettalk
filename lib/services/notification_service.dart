import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../database/settings_repository.dart';

/// Covers every notification event listed in the brief:
///   - New message received -> sound + vibration + popup
///   - Message delivered -> silent
///   - Network improved -> informational, no sound
///   - Node discovered -> optional, user-toggleable (off by default)
class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  final _settingsRepo = SettingsRepository();

  Future<void> init() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);
    await _createChannels();
    _initialized = true;
  }

  Future<void> _createChannels() async {
    const loudChannel = AndroidNotificationChannel(
      'lettalk_messages',
      'Messages',
      description: 'New message alerts',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    const silentChannel = AndroidNotificationChannel(
      'lettalk_status',
      'Delivery & Network Status',
      description: 'Silent delivery confirmations and network updates',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    );
    // Required by flutter_background_service on Android 8+: the
    // persistent foreground-service notification needs its own channel,
    // created before the service starts.
    const relayServiceChannel = AndroidNotificationChannel(
      'lettalk_relay_service',
      'Background Relay',
      description: 'Keeps Lettalk relaying messages while the app is closed',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    );
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(loudChannel);
    await androidPlugin?.createNotificationChannel(silentChannel);
    await androidPlugin?.createNotificationChannel(relayServiceChannel);
  }

  Future<void> showMessageReceived({required String senderName}) async {
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      senderName,
      'New message',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'lettalk_messages',
          'Messages',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
      ),
    );
  }

  Future<void> showMessageDelivered({required String recipientName}) async {
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      'Delivered',
      'Your message to $recipientName was delivered',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'lettalk_status',
          'Delivery & Network Status',
          importance: Importance.low,
          priority: Priority.low,
          playSound: false,
          enableVibration: false,
          silent: true,
        ),
      ),
    );
  }

  Future<void> showNetworkImproved() async {
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      'Lettalk',
      'Network strength improved in your area',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'lettalk_status',
          'Delivery & Network Status',
          importance: Importance.low,
          priority: Priority.low,
          playSound: false,
        ),
      ),
    );
  }

  Future<void> showNodeDiscovered({required int totalNearby}) async {
    final enabled = await _settingsRepo.getNodeDiscoveredEnabled();
    if (!enabled) return;
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      'Lettalk',
      '$totalNearby Lettalk device(s) nearby',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'lettalk_status',
          'Delivery & Network Status',
          importance: Importance.low,
          priority: Priority.low,
          playSound: false,
        ),
      ),
    );
  }
}
