import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../core/constants.dart';
import '../database/network_snapshot_repository.dart';
import '../database/settings_repository.dart';
import 'ble_peripheral_service.dart';
import 'ble_transport.dart';
import 'notification_service.dart';
import 'uranium_protocol.dart';

/// Implements the brief's background service spec exactly:
///   every [ProtocolConstants.scanInterval]:
///     1. BLE scan for [ProtocolConstants.scanDuration]
///     2. Sync relay tables with every discovered peer
///     3. Process incoming Kill Signals (handled inside the sync itself)
///     4. Purge expired messages
///     5. Sleep until next cycle
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

    final uranium = UraniumProtocolEngine.instance;
    final bleTransport = BleTransport.instance;
    final blePeripheral = BlePeripheralService.instance;
    final notifications = NotificationService.instance;
    final snapshotRepo = NetworkSnapshotRepository();
    final settingsRepo = SettingsRepository();

    // Peripheral role stays "on" continuously — advertising is cheap and
    // lets other devices find us between our own scan cycles too.
    blePeripheral.startAdvertising();
    uranium.startPeripheralListener();

    var stopped = false;
    service.on('stopService').listen((event) {
      stopped = true;
      service.stopSelf();
    });

    // Self-rescheduling loop (rather than Timer.periodic with a fixed
    // duration) so a change to the scan interval in Settings takes
    // effect on the very next cycle without needing to restart the
    // service.
    void scheduleNext() {
      if (stopped) return;
      Future(() async {
        if (service is AndroidServiceInstance) {
          final isForeground = await service.isForegroundService();
          if (!isForeground) return;
        }
        await _runOneCycle(uranium, bleTransport, notifications, snapshotRepo);
        if (stopped) return;
        final minutes = await settingsRepo.getScanIntervalMinutes();
        Timer(Duration(minutes: minutes), scheduleNext);
      });
    }

    scheduleNext(); // runs the first cycle immediately, then keeps rescheduling
  }

  static Future<void> _runOneCycle(
    UraniumProtocolEngine uranium,
    BleTransport bleTransport,
    NotificationService notifications,
    NetworkSnapshotRepository snapshotRepo,
  ) async {
    try {
      final peers = await bleTransport.scanForPeers();

      final previousSnapshot = await snapshotRepo.getLatest();
      final strengthPct = _estimateStrengthPercent(peers.length);

      for (final peer in peers) {
        await uranium.syncAsCentral(peer);
      }

      final avgRssi = peers.isEmpty
          ? -100
          : (peers.map((p) => p.rssi).reduce((a, b) => a + b) / peers.length).round();

      await snapshotRepo.recordSnapshot(NetworkSnapshot(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        nearbyCount: peers.length,
        avgRssi: avgRssi,
        strengthPct: strengthPct,
      ));

      if (previousSnapshot != null && strengthPct > previousSnapshot.strengthPct + 15) {
        await notifications.showNetworkImproved();
      }
      if (peers.isNotEmpty) {
        await notifications.showNodeDiscovered(totalNearby: peers.length);
      }

      await uranium.purgeExpired();
    } catch (_) {
      // A failed cycle should never crash the persistent service —
      // it just tries again at the next interval.
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
