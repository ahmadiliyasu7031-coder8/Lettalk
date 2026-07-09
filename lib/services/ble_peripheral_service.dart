import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

import '../core/constants.dart';
import 'ble_logger.dart';
import 'ble_message_queue.dart';
import 'ble_packet.dart';

/// One inbound application-level payload (a Uranium WireMessage's raw
/// bytes), together with a [reply] callback that sends a response back
/// to the exact central that sent it — reliably, fragmented, ACKed,
/// same as the request was.
class PeripheralExchange {
  final Uint8List payload;
  final String peerId;
  final Future<void> Function(Uint8List responseBytes) reply;

  PeripheralExchange({required this.payload, required this.peerId, required this.reply});
}

/// Peripheral role: advertises the Lettalk service UUID so nearby
/// devices can discover this one, and runs a minimal GATT server that
/// accepts writes (BlePacket-framed, see ble_packet.dart) and replies
/// via notify.
///
/// See the note in ble_transport.dart — this is the most
/// platform-fragile part of the app. In particular:
///   - Background/foreground advertising limits differ by Android OEM.
///   - Some chipsets cap simultaneous GATT server connections low (often 1-4),
///     which directly limits how many peers can sync with this device at once.
///   - iOS background BLE peripheral mode is heavily restricted by the OS;
///     this MVP targets Android only per the brief, which avoids that problem.
///
/// Handshake packets (brief item 4) are answered automatically at this
/// layer, without ever reaching the Uranium Protocol engine — a central
/// only gets to send application data after a central successfully
/// exchanges device id / protocol version / features.
///
/// Hardening notes:
///   - `startAdvertising` guards against both "already advertising" and
///     "an advertise call is already in flight", so a rapid double-call
///     (e.g. from both the app's own startup path and the watchdog
///     firing in the same tick) can never register the GATT service or
///     start advertising twice.
///   - Every call into the `bluetooth_low_energy` plugin is wrapped in
///     try/catch; a single malformed event or failed native call can
///     never crash the peripheral role or take down the rest of the app.
///   - Per-central channels are swept on a timer and disposed once idle
///     for [ProtocolConstants.channelIdleTimeout], so a central that
///     vanishes without a clean disconnect event can't leak its channel
///     (and reassembly buffer) forever.
class BlePeripheralService {
  static final BlePeripheralService instance = BlePeripheralService._internal();
  BlePeripheralService._internal();

  PeripheralManager? _manager;
  bool _advertising = false;
  bool _advertisingStartInProgress = false;
  bool get isAdvertising => _advertising;
  String? lastError;

  String? _localDeviceId;

  GATTCharacteristic? _characteristic;

  // One reliable channel per connected central, keyed by the central's
  // identifier string. A GATT server can legitimately be talking to
  // several centrals concurrently.
  final Map<String, ReliablePacketChannel> _channelsByCentral = {};
  final Map<String, StreamSubscription> _payloadSubsByCentral = {};
  final Map<String, StreamSubscription> _handshakeSubsByCentral = {};

  final StreamController<PeripheralExchange> _incomingExchanges = StreamController.broadcast();
  Stream<PeripheralExchange> get onIncomingPayload => _incomingExchanges.stream;

  StreamSubscription? _writeRequestSub;
  Timer? _idleSweepTimer;

  Future<void> startAdvertising({String? localDeviceId}) async {
    if (_advertising || _advertisingStartInProgress) {
      BleLogger.instance.log('startAdvertising called while already advertising/starting — ignoring');
      return;
    }
    _advertisingStartInProgress = true;
    lastError = null;
    _localDeviceId = localDeviceId ?? _localDeviceId;

    try {
      _manager = PeripheralManager();

      final service = GATTService(
        uuid: UUID.fromString(ProtocolConstants.lettalkServiceUuid),
        isPrimary: true,
        includedServices: const [],
        characteristics: [
          GATTCharacteristic.mutable(
            uuid: UUID.fromString(ProtocolConstants.lettalkCharacteristicUuid),
            properties: [
              GATTCharacteristicProperty.write,
              GATTCharacteristicProperty.notify,
            ],
            permissions: [
              GATTCharacteristicPermission.write,
              GATTCharacteristicPermission.read,
            ],
            descriptors: const [],
          ),
        ],
      );

      await _manager!.addService(service);
      _characteristic = service.characteristics.first;

      await _writeRequestSub?.cancel();
      _writeRequestSub = _manager!.characteristicWriteRequested.listen(
        _onWriteRequestedSafely,
        onError: (e) => BleLogger.instance.log('characteristicWriteRequested stream error: $e'),
      );

      await _manager!.startAdvertising(
        Advertisement(
          name: 'LTK',
          serviceUUIDs: [UUID.fromString(ProtocolConstants.lettalkServiceUuid)],
        ),
      );
      _advertising = true;
      BleLogger.instance.log('Advertising started');
      _startIdleSweep();
    } catch (e) {
      // Captured rather than rethrown — the rest of the app (central
      // scanning, message sending, UI) must keep working even if
      // advertising itself fails on this particular device. The error
      // is surfaced in Network Details so it's debuggable without logcat.
      lastError = e.toString();
      _advertising = false;
      BleLogger.instance.log('Advertising failed: $e');
    } finally {
      _advertisingStartInProgress = false;
    }
  }

  /// Wraps the raw write-requested event handler so a single malformed
  /// event (unexpected shape, null field, plugin quirk) is logged and
  /// dropped rather than propagating as an uncaught error inside a
  /// stream listener, which would otherwise silently kill this
  /// subscription and stop the peripheral from ever receiving data
  /// again until the app restarts.
  void _onWriteRequestedSafely(dynamic event) {
    try {
      final central = event.central;
      final centralId = _centralKey(central);

      final channel = _channelsByCentral.putIfAbsent(centralId, () {
        final ch = createChannel(
          rawSend: (bytes) => _notify(central, bytes),
          localDeviceId: _localDeviceId ?? 'unknown-device',
          logTag: () => centralId,
        );
        _wireChannelCallbacks(centralId, ch);
        BleLogger.instance.log('New central connection', deviceId: centralId);
        return ch;
      });

      final rawValue = event.request.value;
      channel.onRawPacketReceived(Uint8List.fromList(List<int>.from(rawValue)));
    } catch (e, st) {
      BleLogger.instance.log('Error handling write-requested event: $e\n$st');
    }
  }

  void _wireChannelCallbacks(String centralId, ReliablePacketChannel channel) {
    _handshakeSubsByCentral[centralId] = channel.onHandshakePacket.listen((packet) async {
      if (packet.type != BlePacketType.handshake) return;
      try {
        BleLogger.instance.log('Handshake received', deviceId: centralId);
        final replyBody = utf8.encode(jsonEncode({
          'device_id': _localDeviceId,
          'protocol_version': ProtocolConstants.protocolVersion,
          'features': ProtocolConstants.supportedFeatures,
        }));
        final ok = await channel.sendReliable(
          type: BlePacketType.handshakeAck,
          receiverId: packet.senderId,
          payload: Uint8List.fromList(replyBody),
        );
        BleLogger.instance.log(
          ok ? 'Handshake success' : 'Handshake ack failed to send',
          deviceId: centralId,
        );
      } catch (e) {
        BleLogger.instance.log('Error responding to handshake: $e', deviceId: centralId);
      }
    }, onError: (e) {
      BleLogger.instance.log('Handshake stream error: $e', deviceId: centralId);
    });

    _payloadSubsByCentral[centralId] = channel.incomingPayloads.listen((bytes) {
      if (_incomingExchanges.isClosed) return;
      _incomingExchanges.add(PeripheralExchange(
        payload: bytes,
        peerId: centralId,
        reply: (response) => channel.sendReliable(
          type: BlePacketType.data,
          receiverId: centralId,
          payload: response,
        ),
      ));
    }, onError: (e) {
      BleLogger.instance.log('Incoming-payload stream error: $e', deviceId: centralId);
    });
  }

  String _centralKey(Central central) {
    // toString() is used rather than reaching for a specific identifier
    // field (e.g. an address or uuid property), since the exact field
    // name has shifted across bluetooth_low_energy versions — toString()
    // is guaranteed to exist and to be stable for the lifetime of one
    // connection, which is all this key needs.
    return central.toString();
  }

  Future<void> _notify(Central central, Uint8List bytes) async {
    final characteristic = _characteristic;
    final manager = _manager;
    if (characteristic == null || manager == null) {
      throw StateError('Cannot notify — peripheral is not currently advertising');
    }
    await manager.notifyCharacteristic(central, characteristic, value: bytes);
  }

  Future<void> stopAdvertising() async {
    try {
      await _manager?.stopAdvertising();
    } catch (e) {
      BleLogger.instance.log('stopAdvertising failed (ignored): $e');
    }
    _advertising = false;
    _idleSweepTimer?.cancel();
    _idleSweepTimer = null;

    // Every connected central is about to drop anyway once the GATT
    // server stops advertising/serving, so their channels (and any
    // partial reassembly state) are no longer meaningful — clear them
    // now rather than waiting for the idle sweep, and rely on
    // startAdvertising() to build fresh ones for whatever reconnects.
    // Note: this intentionally does NOT close _incomingExchanges itself
    // — that broadcast controller and its one long-lived subscriber
    // (UraniumProtocolEngine.startPeripheralListener) are meant to
    // outlive individual advertise/stop cycles for this singleton's
    // whole process lifetime.
    for (final ch in _channelsByCentral.values) {
      ch.dispose();
    }
    _channelsByCentral.clear();
    for (final sub in _payloadSubsByCentral.values) {
      sub.cancel();
    }
    _payloadSubsByCentral.clear();
    for (final sub in _handshakeSubsByCentral.values) {
      sub.cancel();
    }
    _handshakeSubsByCentral.clear();

    BleLogger.instance.log('Advertising stopped');
  }

  void _startIdleSweep() {
    _idleSweepTimer?.cancel();
    _idleSweepTimer = Timer.periodic(ProtocolConstants.idleChannelSweepInterval, (_) {
      _sweepIdleChannels();
    });
  }

  /// Disposes any per-central channel that's been idle for longer than
  /// [ProtocolConstants.channelIdleTimeout] and abandons any reassembly
  /// still stuck mid-transfer on the channels that remain — this is
  /// the peripheral-side equivalent of BleTransport.performIdleMaintenance,
  /// and the only cleanup path available since this plugin version
  /// doesn't expose a confirmed central-disconnected event to hook into
  /// directly (see the class-level hardening notes).
  void _sweepIdleChannels() {
    final now = DateTime.now();
    final staleIds = <String>[];
    for (final entry in _channelsByCentral.entries) {
      entry.value.checkForStalledReassembly();
      if (now.difference(entry.value.lastActivity) > ProtocolConstants.channelIdleTimeout) {
        staleIds.add(entry.key);
      }
    }
    for (final id in staleIds) {
      BleLogger.instance.log('Idle central connection swept', deviceId: id);
      _channelsByCentral.remove(id)?.dispose();
      _payloadSubsByCentral.remove(id)?.cancel();
      _handshakeSubsByCentral.remove(id)?.cancel();
    }
  }

  /// Drops all per-central reliable-channel state for centrals that are
  /// no longer connected, so the map doesn't grow unboundedly across a
  /// long-running background service. Safe to call at any time; kept
  /// as a public entry point in case a confirmed disconnect signal
  /// becomes available in a future plugin version to call this
  /// eagerly instead of waiting for the idle sweep.
  void pruneDisconnected(Set<String> stillConnectedIds) {
    final stale = _channelsByCentral.keys.where((id) => !stillConnectedIds.contains(id)).toList();
    for (final id in stale) {
      _channelsByCentral.remove(id)?.dispose();
      _payloadSubsByCentral.remove(id)?.cancel();
      _handshakeSubsByCentral.remove(id)?.cancel();
    }
  }

  void dispose() {
    _idleSweepTimer?.cancel();
    _idleSweepTimer = null;
    _writeRequestSub?.cancel();
    _writeRequestSub = null;

    if (!_incomingExchanges.isClosed) _incomingExchanges.close();

    for (final ch in _channelsByCentral.values) {
      ch.dispose();
    }
    _channelsByCentral.clear();

    for (final sub in _payloadSubsByCentral.values) {
      sub.cancel();
    }
    _payloadSubsByCentral.clear();

    for (final sub in _handshakeSubsByCentral.values) {
      sub.cancel();
    }
    _handshakeSubsByCentral.clear();
  }
}
