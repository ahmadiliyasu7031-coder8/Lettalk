import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../core/constants.dart';
import 'ble_logger.dart';
import 'ble_message_queue.dart';
import 'ble_packet.dart';

/// Raw transport for the Uranium Protocol — Central role.
///
/// IMPORTANT IMPLEMENTATION NOTE (read before touching this file):
/// `flutter_blue_plus` only implements the BLE **Central** role (scanning +
/// connecting + GATT client). It does NOT support advertising or running a
/// local GATT server, so it cannot make this device discoverable as a
/// **Peripheral**. Since the brief requires every device to be both
/// Central and Peripheral simultaneously, peripheral mode (advertising +
/// GATT server) is implemented separately via the `bluetooth_low_energy`
/// plugin in ble_peripheral_service.dart, which supports both roles on
/// Android and iOS. BleManager (ble_manager.dart) is what actually
/// coordinates the two — this class only ever speaks Central.
///
/// This is one of the highest-risk integration points in the whole app —
/// BLE central/GATT-client behavior varies a lot across Android OEM
/// skins (connection stability, MTU negotiation quirks, some chipsets
/// capping simultaneous connections). Budget real on-device testing
/// time for this file specifically before trusting it in the field.
///
/// Hardening notes:
///   - Every platform call that can hang (connect, discoverServices,
///     setNotifyValue, stopScan) is wrapped in an explicit Dart-level
///     timeout, in addition to whatever timeout the plugin itself
///     claims to honor — belt and suspenders, since a wedged native
///     BLE stack is exactly the kind of thing a plugin-level timeout
///     parameter sometimes fails to enforce.
///   - Every public entry point is wrapped in try/catch and never
///     leaves a connection half-open on failure.
///   - `stopContinuousScan`/`disconnect`/`dispose` are idempotent and
///     safe to call multiple times or on already-torn-down state.
class BleTransport {
  static final BleTransport instance = BleTransport._internal();
  BleTransport._internal();

  final StreamController<DiscoveredPeer> _discoveryController =
      StreamController.broadcast();
  Stream<DiscoveredPeer> get onPeerDiscovered => _discoveryController.stream;

  bool _scanning = false;
  bool get isScanning => _scanning;

  bool _continuousScanning = false;
  StreamSubscription? _scanResultsSub;
  DateTime _lastScanLoopIteration = DateTime.now();
  Timer? _scanStallWatchdog;

  // The single active reliable channel + device for whichever connection
  // is currently open. This app connects to one peer at a time (connect
  // -> handshake -> sync -> disconnect), so one slot is sufficient; if
  // that ever changes, key these by deviceId instead.
  ReliablePacketChannel? _activeChannel;
  BluetoothDevice? _activeDevice;
  StreamSubscription? _activeNotifySub;

  // Guards the single "active connection" slot for its *entire*
  // lifecycle — from the start of connectAndHandshake through to the
  // matching disconnect() call — not just the handshake itself. Without
  // this, a second peer discovered while the first is still mid-sync
  // (using exchangePayload against the active channel) could start a
  // second connectAndHandshake and silently overwrite _activeChannel /
  // _activeDevice out from under the in-progress sync. Released
  // exactly once per acquire, in disconnect(), which BleManager always
  // calls (success or failure) exactly once per connectAndHandshake.
  bool _slotBusy = false;
  String? _busyDeviceId;
  DateTime? _slotAcquiredAt;

  /// Central role: scan for nearby devices advertising the Lettalk
  /// service UUID, once, for [duration] (or the default). Retained for
  /// callers that want a single bounded scan; BleManager instead uses
  /// [startContinuousScan] for "scan continuously" behaviour.
  Future<List<DiscoveredPeer>> scanForPeers({Duration? duration}) async {
    if (_scanning) return [];
    _scanning = true;
    final found = <String, DiscoveredPeer>{};

    try {
      final isSupported = await _safeIsSupported();
      if (!isSupported) return [];

      final subscription = FlutterBluePlus.scanResults.listen((results) {
        for (final peer in _extractLettalkPeers(results)) {
          found[peer.deviceId] = peer;
          _discoveryController.add(peer);
        }
      }, onError: (e) {
        BleLogger.instance.log('scanResults stream error: $e');
      });

      await FlutterBluePlus.startScan(
        withServices: [Guid(ProtocolConstants.lettalkServiceUuid)],
        timeout: duration ?? ProtocolConstants.scanDuration,
      );
      await Future.delayed(duration ?? ProtocolConstants.scanDuration);
      await _safeStopScan();
      await subscription.cancel();
    } catch (e) {
      BleLogger.instance.log('scanForPeers error: $e');
    } finally {
      _scanning = false;
    }

    return found.values.toList();
  }

  /// "Scan continuously" (brief item 3). Android and flutter_blue_plus
  /// don't reliably sustain one indefinite scan call, so this runs
  /// back-to-back bounded scan windows with no gap between them and
  /// keeps restarting until [stopContinuousScan] is called — from the
  /// outside this behaves as continuous discovery. A stall watchdog
  /// force-restarts the whole loop if it ever stops making progress
  /// (some OEM Bluetooth stacks silently wedge the scanner).
  Future<void> startContinuousScan() async {
    if (_continuousScanning) {
      BleLogger.instance.log('startContinuousScan called while already scanning — ignoring');
      return;
    }
    _continuousScanning = true;
    _lastScanLoopIteration = DateTime.now();
    BleLogger.instance.log('Scanning started (continuous)');

    _scanStallWatchdog?.cancel();
    _scanStallWatchdog = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_continuousScanning) return;
      final stalledFor = DateTime.now().difference(_lastScanLoopIteration);
      if (stalledFor > ProtocolConstants.scanStallThreshold) {
        BleLogger.instance.log(
          'Scan loop appears stalled (no progress for ${stalledFor.inSeconds}s) — forcing restart',
        );
        unawaited(_forceRestartScanLoop());
      }
    });

    unawaited(_scanLoop());
  }

  Future<void> _forceRestartScanLoop() async {
    try {
      await _scanResultsSub?.cancel();
      _scanResultsSub = null;
      await _safeStopScan();
    } catch (e) {
      BleLogger.instance.log('Error forcing scan restart: $e');
    }
    // The while loop in _scanLoop will naturally pick back up on its
    // next iteration since _continuousScanning is still true; nothing
    // further to do here beyond clearing the wedged subscription/scan.
  }

  Future<void> _scanLoop() async {
    while (_continuousScanning) {
      _lastScanLoopIteration = DateTime.now();
      try {
        final isSupported = await _safeIsSupported();
        if (!isSupported) {
          BleLogger.instance.log('Bluetooth not supported/unavailable — pausing scan retry');
          await Future.delayed(const Duration(seconds: 5));
          continue;
        }

        await _scanResultsSub?.cancel();
        _scanResultsSub = FlutterBluePlus.scanResults.listen((results) {
          _lastScanLoopIteration = DateTime.now();
          // Filter: only devices advertising our Service UUID make it
          // out of _extractLettalkPeers — everything else (brief item 3:
          // "ignore unknown BLE devices") never reaches onPeerDiscovered.
          for (final peer in _extractLettalkPeers(results)) {
            _discoveryController.add(peer);
          }
        }, onError: (e) {
          BleLogger.instance.log('scanResults stream error: $e');
        });

        await FlutterBluePlus.startScan(
          withServices: [Guid(ProtocolConstants.lettalkServiceUuid)],
          timeout: ProtocolConstants.continuousScanWindow,
        ).timeout(
          ProtocolConstants.continuousScanWindow + const Duration(seconds: 5),
          onTimeout: () => BleLogger.instance.log('startScan call itself timed out'),
        );
        await Future.delayed(ProtocolConstants.continuousScanWindow);
        await _safeStopScan();
      } catch (e) {
        BleLogger.instance.log('Scan cycle error, retrying: $e');
        await Future.delayed(const Duration(seconds: 3));
      }
    }
  }

  Future<void> stopContinuousScan() async {
    _continuousScanning = false;
    _scanStallWatchdog?.cancel();
    _scanStallWatchdog = null;
    await _scanResultsSub?.cancel();
    _scanResultsSub = null;
    await _safeStopScan();
    BleLogger.instance.log('Scanning stopped');
  }

  Future<bool> _safeIsSupported() async {
    try {
      return await FlutterBluePlus.isSupported;
    } catch (e) {
      BleLogger.instance.log('isSupported check failed: $e');
      return false;
    }
  }

  Future<void> _safeStopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      // Already stopped, adapter off, or platform quirk — never let
      // this bubble up and break the caller's control flow.
      BleLogger.instance.log('stopScan failed (likely already stopped): $e');
    }
  }

  List<DiscoveredPeer> _extractLettalkPeers(List<ScanResult> results) {
    final peers = <DiscoveredPeer>[];
    for (final r in results) {
      try {
        final advertisesLettalk = r.advertisementData.serviceUuids
            .map((u) => u.toString().toUpperCase())
            .contains(ProtocolConstants.lettalkServiceUuid.toUpperCase());
        if (!advertisesLettalk) continue; // ignore unknown BLE devices
        peers.add(DiscoveredPeer(
          deviceId: r.device.remoteId.str,
          rssi: r.rssi,
          device: r.device,
        ));
      } catch (e) {
        // A single malformed scan result must never take down the
        // whole scan cycle.
        BleLogger.instance.log('Skipped malformed scan result: $e');
      }
    }
    return peers;
  }

  /// Connects to [peer], verifies the service UUID, and exchanges
  /// handshake information (device id, protocol version, supported
  /// features — brief item 4) before returning. Returns true only if
  /// the handshake completed successfully; the caller (BleManager)
  /// should only proceed to Uranium sync in that case.
  ///
  /// Every platform call in this method is wrapped with an explicit
  /// timeout independent of whatever the plugin itself claims to
  /// enforce, and any failure tears down whatever was partially
  /// established rather than leaving a half-open connection/channel.
  Future<bool> connectAndHandshake(DiscoveredPeer peer, {required String localDeviceId}) async {
    if (_slotBusy) {
      BleLogger.instance.log(
        'connectAndHandshake called while the single connection slot is busy — refusing to avoid a duplicate/overlapping connection',
        deviceId: peer.deviceId,
      );
      return false;
    }
    _slotBusy = true; // released exactly once, in disconnect()
    _busyDeviceId = peer.deviceId;
    _slotAcquiredAt = DateTime.now();

    StreamSubscription? notifySub;
    ReliablePacketChannel? channel;

    try {
      await peer.device
          .connect(timeout: ProtocolConstants.connectTimeout)
          .timeout(ProtocolConstants.connectTimeout + const Duration(seconds: 3));

      final services = await peer.device
          .discoverServices()
          .timeout(const Duration(seconds: 10));
      final service = services.firstWhere(
        (s) =>
            s.uuid.toString().toUpperCase() ==
            ProtocolConstants.lettalkServiceUuid.toUpperCase(),
        orElse: () => throw Exception('Lettalk service UUID not found on peer'),
      );
      final characteristic = service.characteristics.firstWhere(
        (c) =>
            c.uuid.toString().toUpperCase() ==
            ProtocolConstants.lettalkCharacteristicUuid.toUpperCase(),
      );

      channel = createChannel(
        rawSend: (bytes) => characteristic.write(bytes, withoutResponse: false),
        localDeviceId: localDeviceId,
        logTag: () => peer.deviceId,
      );

      await characteristic.setNotifyValue(true).timeout(const Duration(seconds: 8));
      notifySub = characteristic.onValueReceived.listen(
        (value) {
          try {
            channel?.onRawPacketReceived(Uint8List.fromList(value));
          } catch (e) {
            BleLogger.instance.log('Error routing notify value: $e', deviceId: peer.deviceId);
          }
        },
        onError: (e) => BleLogger.instance.log('Notify stream error: $e', deviceId: peer.deviceId),
      );

      final handshakePayload = utf8.encode(jsonEncode({
        'device_id': localDeviceId,
        'protocol_version': ProtocolConstants.protocolVersion,
        'features': ProtocolConstants.supportedFeatures,
      }));

      final handshakeCompleter = Completer<BlePacket>();
      final handshakeSub = channel.onHandshakePacket.listen((p) {
        if (!handshakeCompleter.isCompleted) handshakeCompleter.complete(p);
      });

      bool handshakeOk;
      try {
        final sent = await channel.sendReliable(
          type: BlePacketType.handshake,
          receiverId: peer.deviceId,
          payload: Uint8List.fromList(handshakePayload),
        );
        if (!sent) {
          handshakeOk = false;
        } else {
          try {
            final ack = await handshakeCompleter.future.timeout(ProtocolConstants.handshakeTimeout);
            handshakeOk = _validateHandshakeAck(ack, peer.deviceId);
          } on TimeoutException {
            BleLogger.instance.log('Handshake timed out', deviceId: peer.deviceId);
            handshakeOk = false;
          }
        }
      } finally {
        await handshakeSub.cancel();
      }

      if (!handshakeOk) {
        await notifySub.cancel();
        channel.dispose();
        return false;
      }

      // Only now, with a fully-handshaken channel, publish it as the
      // active connection state that exchangePayload() will use.
      _activeChannel = channel;
      _activeDevice = peer.device;
      _activeNotifySub = notifySub;
      return true;
    } catch (e) {
      BleLogger.instance.log('Connect/handshake failed: $e', deviceId: peer.deviceId);
      await notifySub?.cancel();
      channel?.dispose();
      return false;
    }
    // Note: _slotBusy is intentionally NOT released here on any path —
    // BleManager always calls disconnect(peer.device) exactly once per
    // connectAndHandshake attempt (success, handshake failure, or
    // exception), and that is the single place the slot is freed. This
    // keeps the slot held for the whole connect->sync->disconnect
    // lifecycle, not just the handshake — see the field doc above.
  }

  bool _validateHandshakeAck(BlePacket ack, String peerDeviceId) {
    try {
      final body = jsonDecode(utf8.decode(ack.payload)) as Map<String, dynamic>;
      final version = body['protocol_version'] as int?;
      if (version != ProtocolConstants.protocolVersion) {
        BleLogger.instance.log(
          'Protocol version mismatch (peer=$version, local=${ProtocolConstants.protocolVersion})',
          deviceId: peerDeviceId,
        );
        return false;
      }
      return true;
    } catch (e) {
      BleLogger.instance.log('Malformed handshake ack: $e', deviceId: peerDeviceId);
      return false;
    }
  }

  /// Exchanges one application-level payload (a Uranium WireMessage,
  /// as raw bytes) over the already-connected + already-handshaken
  /// channel for [device], reliably (brief item 6: fragmented, ACKed,
  /// retried). Returns the peer's reply payload, or null on failure.
  ///
  /// Must be called only after [connectAndHandshake] returned true for
  /// this device — it reuses that connection's channel rather than
  /// reconnecting, since GATT connect/discover/handshake is by far the
  /// most expensive part of a sync cycle. Wrapped in an overall
  /// safety-net timeout so a wedged send can never hang the calling
  /// sync cycle forever, on top of the per-fragment timeouts already
  /// inside ReliablePacketChannel.
  Future<Uint8List?> exchangePayload(
    BluetoothDevice device,
    Uint8List outgoingPayload,
  ) async {
    final channel = _activeChannel;
    if (channel == null || channel.isClosed || _activeDevice?.remoteId != device.remoteId) {
      BleLogger.instance.log('exchangePayload called without an active handshaken channel');
      return null;
    }

    return _exchangePayloadInner(channel, device, outgoingPayload).timeout(
      ProtocolConstants.syncReplyTimeout + const Duration(seconds: 10),
      onTimeout: () {
        BleLogger.instance.log('exchangePayload hit its outer safety-net timeout', deviceId: device.remoteId.str);
        return null;
      },
    );
  }

  Future<Uint8List?> _exchangePayloadInner(
    ReliablePacketChannel channel,
    BluetoothDevice device,
    Uint8List outgoingPayload,
  ) async {
    final replyCompleter = Completer<Uint8List>();
    final sub = channel.incomingPayloads.listen((bytes) {
      if (!replyCompleter.isCompleted) replyCompleter.complete(bytes);
    });

    try {
      final sent = await channel.sendReliable(
        type: BlePacketType.data,
        receiverId: device.remoteId.str,
        payload: outgoingPayload,
      );
      if (!sent) return null;

      final reply = await replyCompleter.future.timeout(
        ProtocolConstants.syncReplyTimeout,
        onTimeout: () => Uint8List(0),
      );
      return reply.isEmpty ? null : reply;
    } catch (e) {
      BleLogger.instance.log('exchangePayload failed: $e', deviceId: device.remoteId.str);
      return null;
    } finally {
      await sub.cancel();
    }
  }

  /// Periodic maintenance hook (called by BleManager's watchdog):
  /// abandons a stalled/interrupted reassembly on the active channel,
  /// and force-releases the single-connection slot if it's been held
  /// far longer than any legitimate connect+sync cycle should take —
  /// a last-resort guard against the slot being wedged forever by a
  /// code path that failed to reach disconnect() (should not happen
  /// given the try/catch/finally coverage above, but a hung native
  /// platform call is exactly the kind of thing worth a second safety
  /// net for).
  void performIdleMaintenance() {
    _activeChannel?.checkForStalledReassembly();

    final acquiredAt = _slotAcquiredAt;
    if (_slotBusy && acquiredAt != null) {
      final heldFor = DateTime.now().difference(acquiredAt);
      final maxReasonable = ProtocolConstants.connectTimeout +
          ProtocolConstants.handshakeTimeout +
          ProtocolConstants.syncReplyTimeout * 2 +
          const Duration(seconds: 30);
      if (heldFor > maxReasonable) {
        BleLogger.instance.log(
          'Connection slot held for ${heldFor.inSeconds}s (device=$_busyDeviceId) — force-releasing as a stuck-slot safety net',
        );
        _activeNotifySub?.cancel();
        _activeChannel?.dispose();
        _activeChannel = null;
        _activeDevice = null;
        _activeNotifySub = null;
        _slotBusy = false;
        _busyDeviceId = null;
        _slotAcquiredAt = null;
      }
    }
  }

  /// Tears down the currently-active connection (if [device] matches),
  /// disconnecting and releasing its channel. Called once a sync cycle
  /// completes, successfully or not. Idempotent and safe to call even
  /// if nothing is currently connected.
  Future<void> disconnect(BluetoothDevice device) async {
    try {
      if (_activeDevice?.remoteId == device.remoteId) {
        await _activeNotifySub?.cancel();
        _activeNotifySub = null;
        _activeChannel?.dispose();
        _activeChannel = null;
        _activeDevice = null;
      }
      await device.disconnect().timeout(const Duration(seconds: 8));
    } catch (e) {
      BleLogger.instance.log('disconnect() best-effort failure (ignored): $e', deviceId: device.remoteId.str);
    } finally {
      // Release the single-connection slot regardless of which path
      // got us here (successful sync, failed handshake, or an
      // exception) — this is the one guaranteed call-site per attempt.
      if (_busyDeviceId == device.remoteId.str) {
        _slotBusy = false;
        _busyDeviceId = null;
        _slotAcquiredAt = null;
      }
    }
  }

  void dispose() {
    _scanStallWatchdog?.cancel();
    _scanStallWatchdog = null;
    _scanResultsSub?.cancel();
    _activeNotifySub?.cancel();
    _activeChannel?.dispose();
    _activeChannel = null;
    _activeDevice = null;
    _slotBusy = false;
    _busyDeviceId = null;
    _slotAcquiredAt = null;
    _discoveryController.close();
  }
}

class DiscoveredPeer {
  final String deviceId;
  final int rssi;
  final BluetoothDevice device;

  DiscoveredPeer({required this.deviceId, required this.rssi, required this.device});
}

/// Wire format for relay-table and payload exchange between two nodes.
/// Kept intentionally simple (JSON) since payload sizes are tiny
/// (message IDs + small encrypted blobs), not performance-critical. This
/// sits one layer above BlePacket: a WireMessage's bytes are what gets
/// fragmented into BlePackets by ReliablePacketChannel.sendReliable.
class WireMessage {
  final String type; // 'sync_request' | 'sync_response' | 'push_messages' | 'push_ack'
  final Map<String, dynamic> body;

  WireMessage({required this.type, required this.body});

  Uint8List toBytes() => Uint8List.fromList(utf8.encode(jsonEncode({
        'type': type,
        'body': body,
      })));

  static WireMessage fromBytes(Uint8List bytes) {
    final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return WireMessage(
      type: decoded['type'] as String,
      body: decoded['body'] as Map<String, dynamic>,
    );
  }
}
