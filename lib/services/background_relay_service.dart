import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../database/network_snapshot_repository.dart';
import '../database/settings_repository.dart';
import 'ble_logger.dart';
import 'ble_manager.dart';
import 'notification_service.dart';
import 'uranium_protocol.dart';

/// Boots the single BLE Manager (advertising + continuous scanning +
/// auto-connect + auto-reconnect + Uranium sync all live there now —
/// see ble_manager.dart) and keeps a lightweight periodic loop on top
/// of it purely for two things the Manager itself doesn't own:
///   1. Recording "Network Strength" snapshots for the UI graph.
///   2. Purging expired messages/outbox drafts.
///
/// Runs as an Android foreground service (required since Android 8+ kills
/// background work aggressively otherwise) with a persistent low-priority
/// notification, per "App must survive background kill".
class BackgroundRelayService {
  static const _notificationChannelId = 'lettalk_relay_service';
  static const _notificationId = 9001;

  Future<void> initializeAndStart() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onServiceStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: _notificationChannelId,
        initialNotificationTitle: 'Lettalk is active',
        initialNotificationContent: 'Relaying nearby messages in the background',
        foregroundServiceNotificationId: _notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false, // MVP is Android-only per the brief
        onForeground: _onServiceStart,
        onBackground: (service) async => true,
      ),
    );

    await service.startService();
  }

  /// Entry point that runs inside the dedicated background isolate.
  /// Everything below executes independently of the main UI isolate.
  @pragma('vm:entry-point')
  static void _onServiceStart(ServiceInstance service) {
    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
    }

    final bleManager = BleManager.instance;
    final uranium = UraniumProtocolEngine.instance;
    final notifications = NotificationService.instance;
    final snapshotRepo = NetworkSnapshotRepository();
    final settingsRepo = SettingsRepository();

    // Everything Bluetooth — advertising, scanning, connecting,
    // reconnecting, handshaking, syncing — is owned by BleManager from
    // here on. It keeps running continuously rather than on a fixed
    // scan/sleep cycle, per the brief's "continue advertising / continue
    // scanning / reconnect automatically / process queued messages /
    // maintain synchronization" background-service spec.
    unawaited(bleManager.start());

    var stopped = false;
    service.on('stopService').listen((event) {
      stopped = true;
      bleManager.stop();
      service.stopSelf();
    });

    void scheduleNext() {
      if (stopped) return;
      Future(() async {
        if (service is AndroidServiceInstance) {
          final isForeground = await service.isForegroundService();
          if (!isForeground) return;
        }
        await _runMaintenanceCycle(bleManager, uranium, notifications, snapshotRepo);
        if (stopped) return;
        final minutes = await settingsRepo.getScanIntervalMinutes();
        Timer(Duration(minutes: minutes), scheduleNext);
      });
    }

    scheduleNext(); // runs the first cycle immediately, then keeps rescheduling
  }

  static Future<void> _runMaintenanceCycle(
    BleManager bleManager,
    UraniumProtocolEngine uranium,
    NotificationService notifications,
    NetworkSnapshotRepository snapshotRepo,
  ) async {
    try {
      final nearbyCount = bleManager.knownPeers.length;
      final previousSnapshot = await snapshotRepo.getLatest();
      final strengthPct = _estimateStrengthPercent(nearbyCount);

      // BleManager doesn't track RSSI over time (that lives on the
      // transient DiscoveredPeer at discovery time), so the snapshot's
      // avgRssi reflects the last-known signal quality bucket via the
      // strength estimate rather than a live re-read.
      await snapshotRepo.recordSnapshot(NetworkSnapshot(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        nearbyCount: nearbyCount,
        avgRssi: nearbyCount > 0 ? -60 : -100,
        strengthPct: strengthPct,
      ));

      if (previousSnapshot != null && strengthPct > previousSnapshot.strengthPct + 15) {
        await notifications.showNetworkImproved();
      }
      if (nearbyCount > 0) {
        await notifications.showNodeDiscovered(totalNearby: nearbyCount);
      }

      await uranium.purgeExpired();
    } catch (e) {
      // A failed cycle should never crash the persistent service —
      // it just tries again at the next interval.
      BleLogger.instance.log('Maintenance cycle error: $e');
    }
  }

  /// Rough heuristic for the "Network Strength %" gauge: scales with
  /// nearby device count, capped at 100. Tune against real-world
  /// device density once field-tested — this is a starting curve,
  /// not a calibrated formula.
  static int _estimateStrengthPercent(int nearbyCount) {
    if (nearbyCount <= 0) return 0;
    final pct = (nearbyCount * 12).clamp(0, 100);
    return pct;
  }

  Future<void> stop() async {
    final service = FlutterBackgroundService();
    service.invoke('stopService');
  }
}
