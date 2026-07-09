import 'dart:async';
import 'dart:math';

import '../core/constants.dart';
import '../database/settings_repository.dart';
import 'ble_logger.dart';
import 'ble_peripheral_service.dart';
import 'ble_transport.dart';
import 'permission_service.dart';
import 'uranium_protocol.dart';

/// Single BLE Manager (brief item 1). Every Bluetooth operation in the
/// app passes through this class — nothing else starts advertising,
/// starts scanning, connects, disconnects, reconnects, or triggers a
/// Uranium sync on its own. It composes:
///
///   - BlePeripheralService  (Peripheral role: advertise + GATT server)
///   - BleTransport          (Central role: scan + connect + GATT client)
///   - UraniumProtocolEngine (application-level sync/gossip/relay logic)
///
/// and adds the cross-cutting behaviour none of those own individually:
/// connection lifecycle (auto-connect on discovery, dedupe, backoff
/// reconnect), a lightweight known/connected-peers table, Bluetooth
/// on/off awareness, and routing every operation through BleLogger.
///
/// Hardening notes:
///   - [start]/[stop] are idempotent and guarded against re-entrancy —
///     calling either while already in the target state is a no-op.
///   - [_onPeerFound] and [_connect]'s dedupe (`_connecting`,
///     `_connectedPeers`) is updated *synchronously*, before any
///     `await`, which is what actually makes it race-safe under Dart's
///     single-threaded event loop: two discovery events for the same
///     peer arriving back-to-back can never both slip past the check.
///   - A periodic Bluetooth-adapter-state poll pauses scanning/
///     advertising cleanly (rather than error-looping) when the user
///     disables Bluetooth, cancels any in-flight reconnect timers, and
///     resumes automatically once the radio is back on.
///   - A periodic idle-maintenance sweep asks the transport and
///     peripheral layers to abandon any stalled/interrupted reassembly
///     and force-release a wedged connection slot, independent of the
///     advertising/BT-state watchdogs.
class BleManager {
  static final BleManager instance = BleManager._internal();
  BleManager._internal();

  final BlePeripheralService _peripheral = BlePeripheralService.instance;
  final BleTransport _transport = BleTransport.instance;
  final UraniumProtocolEngine _uranium = UraniumProtocolEngine.instance;
  final SettingsRepository _settingsRepo = SettingsRepository();

  String? _localDeviceId;
  bool _running = false;
  bool _bluetoothCurrentlyOn = true;

  StreamSubscription? _discoverySub;
  Timer? _advertisingWatchdog;
  Timer? _bluetoothStateWatchdog;
  Timer? _idleMaintenanceTimer;

  // --- Mesh routing state (brief item 9) ---------------------------------
  // Known peers: every device id ever discovered, with last-seen time.
  // Connected peers: currently mid-sync.
  // These back the "known -> connected -> previously seen" priority the
  // brief describes; the actual store-and-forward relaying itself is
  // handled by UraniumProtocolEngine's flood-with-hop-limit design
  // (relay_log + hop count), which this table feeds peer ids into.
  final Map<String, DateTime> _knownPeers = {};
  final Map<String, DateTime> _connectedPeers = {};
  final Set<String> _connecting = {};
  final Map<String, int> _reconnectAttempts = {};
  final Map<String, Timer> _pendingReconnects = {};

  Map<String, DateTime> get knownPeers => Map.unmodifiable(_knownPeers);
  Map<String, DateTime> get connectedPeers => Map.unmodifiable(_connectedPeers);
  bool get isRunning => _running;

  /// Starts the whole engine: advertising, continuous scanning, and the
  /// peripheral-side listener that feeds incoming syncs into Uranium.
  /// Safe to call multiple times — a no-op if already running.
  Future<void> start() async {
    if (_running) {
      BleLogger.instance.log('BleManager.start() called while already running — ignoring');
      return;
    }
    _running = true;

    try {
      _localDeviceId = await _settingsRepo.getOrCreateLocalDeviceId();
    } catch (e) {
      // Fall back to a per-session-only id rather than failing to
      // start the whole engine over a settings-DB hiccup; this device
      // just won't have a *stable* id across restarts until the DB is
      // reachable again.
      _localDeviceId = 'session-${DateTime.now().millisecondsSinceEpoch}';
      BleLogger.instance.log('Falling back to a session-only device id: $e');
    }
    BleLogger.instance.log('BLE Manager starting (local device id: $_localDeviceId)');

    _bluetoothCurrentlyOn = await _checkBluetoothOn();
    _startBluetoothStateWatchdog();
    _startIdleMaintenance();

    if (_bluetoothCurrentlyOn) {
      await _enterActiveState();
    } else {
      BleLogger.instance.log('Bluetooth is off at startup — waiting for it to be enabled');
    }
  }

  /// Stops all Bluetooth activity. Note: this does NOT call
  /// BleTransport.dispose()/BlePeripheralService.dispose() — those close
  /// their singletons' broadcast StreamControllers permanently, which
  /// would break a later start() call (a closed broadcast stream's
  /// `.stream` delivers onDone to any new listener instead of further
  /// events). BleManager.stop() is meant to be resumable, so it only
  /// tears down the *active radio use* (advertising, scanning,
  /// connections, reconnect timers); the underlying singletons and
  /// their streams stay alive for the process's lifetime, ready for
  /// another start(). Full .dispose() is reserved for actual process
  /// teardown, which in practice the OS handles by killing the process
  /// rather than this app calling it explicitly.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;

    _advertisingWatchdog?.cancel();
    _advertisingWatchdog = null;
    _bluetoothStateWatchdog?.cancel();
    _bluetoothStateWatchdog = null;
    _idleMaintenanceTimer?.cancel();
    _idleMaintenanceTimer = null;

    await _discoverySub?.cancel();
    _discoverySub = null;

    for (final timer in _pendingReconnects.values) {
      timer.cancel();
    }
    _pendingReconnects.clear();
    _reconnectAttempts.clear();
    _connecting.clear();
    _connectedPeers.clear();

    await _transport.stopContinuousScan();
    await _peripheral.stopAdvertising();

    BleLogger.instance.log('BLE Manager stopped');
  }

  // ---------------------------------------------------------------------
  // Bluetooth on/off awareness. Reconnection must be robust across a
  // real toggle-off/toggle-on cycle: scanning/advertising should stop
  // cleanly (not error-loop) while BT is off, all in-flight reconnect
  // timers should be cancelled (retrying against a dead radio is just
  // wasted battery), and everything should resume automatically once
  // the radio comes back.
  // ---------------------------------------------------------------------

  Future<bool> _checkBluetoothOn() async {
    try {
      return await PermissionService.isBluetoothOn();
    } catch (e) {
      BleLogger.instance.log('Bluetooth state check failed, assuming off: $e');
      return false;
    }
  }

  void _startBluetoothStateWatchdog() {
    _bluetoothStateWatchdog?.cancel();
    _bluetoothStateWatchdog = Timer.periodic(ProtocolConstants.bluetoothStatePollInterval, (_) async {
      if (!_running) return;
      final isOnNow = await _checkBluetoothOn();
      if (isOnNow == _bluetoothCurrentlyOn) return;

      _bluetoothCurrentlyOn = isOnNow;
      if (isOnNow) {
        BleLogger.instance.log('Bluetooth turned back on — resuming');
        await _enterActiveState();
      } else {
        BleLogger.instance.log('Bluetooth turned off — pausing and cancelling reconnect attempts');
        await _enterPausedState();
      }
    });
  }

  Future<void> _enterActiveState() async {
    if (!_running) return;
    await _startAdvertisingWithWatchdog();
    _uranium.startPeripheralListener();
    _startContinuousScanning();
  }

  /// Stops all active radio use without tearing down BleManager itself,
  /// so it can cleanly resume the moment Bluetooth is re-enabled. All
  /// pending reconnect timers are cancelled here — reconnecting against
  /// a radio that's known to be off would just spin through backoff
  /// attempts for no reason, and a fresh discovery once BT is back on
  /// gives every peer a clean-slate reconnect anyway.
  Future<void> _enterPausedState() async {
    _advertisingWatchdog?.cancel();
    _advertisingWatchdog = null;

    await _discoverySub?.cancel();
    _discoverySub = null;

    for (final timer in _pendingReconnects.values) {
      timer.cancel();
    }
    _pendingReconnects.clear();
    _reconnectAttempts.clear();
    _connecting.clear();
    _connectedPeers.clear();

    await _transport.stopContinuousScan();
    await _peripheral.stopAdvertising();
  }

  // ---------------------------------------------------------------------
  // Advertising, with a watchdog to restart it if Android silently stops
  // it (brief item 2: "Restart advertising automatically if Android
  // stops it").
  // ---------------------------------------------------------------------

  Future<void> _startAdvertisingWithWatchdog() async {
    await _peripheral.startAdvertising(localDeviceId: _localDeviceId);

    _advertisingWatchdog?.cancel();
    _advertisingWatchdog = Timer.periodic(ProtocolConstants.advertisingWatchdogInterval, (_) async {
      if (!_running || !_bluetoothCurrentlyOn) return;
      if (!_peripheral.isAdvertising) {
        BleLogger.instance.log('Advertising is down — restarting');
        await _peripheral.startAdvertising(localDeviceId: _localDeviceId);
      }
    });
  }

  // ---------------------------------------------------------------------
  // Idle maintenance: independent of the advertising/BT watchdogs, asks
  // the transport layer to abandon stalled reassemblies and release a
  // wedged connection slot if one is ever found.
  // ---------------------------------------------------------------------

  void _startIdleMaintenance() {
    _idleMaintenanceTimer?.cancel();
    _idleMaintenanceTimer = Timer.periodic(ProtocolConstants.idleChannelSweepInterval, (_) {
      if (!_running) return;
      try {
        _transport.performIdleMaintenance();
      } catch (e) {
        BleLogger.instance.log('Idle maintenance sweep error: $e');
      }
    });
  }

  // ---------------------------------------------------------------------
  // Scanning + auto-connect (brief item 3).
  // ---------------------------------------------------------------------

  void _startContinuousScanning() {
    _discoverySub?.cancel();
    _discoverySub = _transport.onPeerDiscovered.listen(
      _onPeerFound,
      onError: (e) => BleLogger.instance.log('Discovery stream error: $e'),
    );
    unawaited(_transport.startContinuousScan());
  }

  Future<void> _onPeerFound(DiscoveredPeer peer) async {
    _knownPeers[peer.deviceId] = DateTime.now();

    // Stop duplicate processing: ignore a peer we're already connected
    // to or already in the middle of connecting to. This check-and-act
    // happens synchronously (no await before it), which is what makes
    // it safe against two discovery events for the same peer arriving
    // back-to-back — see the class-level hardening notes.
    if (_connectedPeers.containsKey(peer.deviceId) || _connecting.contains(peer.deviceId)) {
      return;
    }

    if (!_running || !_bluetoothCurrentlyOn) return;

    BleLogger.instance.log('Device found (rssi ${peer.rssi})', deviceId: peer.deviceId);
    await _connect(peer);
  }

  // ---------------------------------------------------------------------
  // Connection Manager (brief item 4) + Uranium sync trigger (item 5) +
  // reconnect with exponential backoff.
  // ---------------------------------------------------------------------

  Future<void> _connect(DiscoveredPeer peer) async {
    final localDeviceId = _localDeviceId;
    if (localDeviceId == null) {
      BleLogger.instance.log(
        'Connect attempted before a local device id was assigned — skipping this discovery',
        deviceId: peer.deviceId,
      );
      return;
    }

    _connecting.add(peer.deviceId); // synchronous — see hardening notes
    try {
      final handshakeOk = await _transport.connectAndHandshake(
        peer,
        localDeviceId: localDeviceId,
      );

      if (!handshakeOk) {
        BleLogger.instance.log('Connection/handshake failed', deviceId: peer.deviceId);
        _scheduleReconnect(peer);
        return; // the finally block below still runs disconnect() + cleanup
      }

      BleLogger.instance.log('Connection success', deviceId: peer.deviceId);
      BleLogger.instance.log('Handshake success', deviceId: peer.deviceId);
      _connectedPeers[peer.deviceId] = DateTime.now();
      _reconnectAttempts.remove(peer.deviceId);

      BleLogger.instance.log('Sync started', deviceId: peer.deviceId);
      await _uranium.syncAsCentral(peer);
      BleLogger.instance.log('Sync complete', deviceId: peer.deviceId);
    } catch (e) {
      BleLogger.instance.log('Sync error: $e', deviceId: peer.deviceId);
      _scheduleReconnect(peer);
    } finally {
      try {
        await _transport.disconnect(peer.device);
      } catch (e) {
        BleLogger.instance.log('Disconnect threw (ignored): $e', deviceId: peer.deviceId);
      }
      _connectedPeers.remove(peer.deviceId);
      _connecting.remove(peer.deviceId);
      BleLogger.instance.log('Disconnected', deviceId: peer.deviceId);
    }
  }

  /// Retries automatically with exponential backoff (brief item 4's
  /// failure path), capped and eventually abandoned until the peer is
  /// rediscovered by a fresh scan (at which point _onPeerFound tries
  /// again with a clean slate). Never schedules a reconnect while
  /// stopped or while Bluetooth is known to be off.
  void _scheduleReconnect(DiscoveredPeer peer) {
    if (!_running || !_bluetoothCurrentlyOn) return;

    final attempt = (_reconnectAttempts[peer.deviceId] ?? 0) + 1;
    _reconnectAttempts[peer.deviceId] = attempt;

    if (attempt > ProtocolConstants.maxReconnectAttempts) {
      BleLogger.instance.log(
        'Giving up after $attempt failed attempts — will retry if rediscovered',
        deviceId: peer.deviceId,
      );
      _reconnectAttempts.remove(peer.deviceId);
      return;
    }

    final delaySeconds = min(
      pow(2, attempt).toInt(),
      ProtocolConstants.maxReconnectBackoffSeconds,
    );
    BleLogger.instance.log('Reconnecting in ${delaySeconds}s (attempt $attempt)', deviceId: peer.deviceId);

    _pendingReconnects[peer.deviceId]?.cancel();
    _pendingReconnects[peer.deviceId] = Timer(Duration(seconds: delaySeconds), () {
      _pendingReconnects.remove(peer.deviceId);
      if (!_running || !_bluetoothCurrentlyOn) return;
      unawaited(_connect(peer));
    });
  }

  /// Convenience for a manual/forced sync pass (e.g. a "Sync now" button)
  /// without waiting for the next discovery event — reuses the same
  /// connect+handshake+sync path so behaviour stays identical.
  Future<void> forceSyncWith(DiscoveredPeer peer) => _onPeerFound(peer);
}
