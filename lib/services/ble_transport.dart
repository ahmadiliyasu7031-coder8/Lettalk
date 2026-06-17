import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../core/constants.dart';

/// Raw transport for the Uranium Protocol.
///
/// IMPORTANT IMPLEMENTATION NOTE (read before touching this file):
/// `flutter_blue_plus` only implements the BLE **Central** role (scanning +
/// connecting + GATT client). It does NOT support advertising or running a
/// local GATT server, so it cannot make this device discoverable as a
/// **Peripheral**. Since the brief requires every device to be both
/// Central and Peripheral simultaneously, peripheral mode (advertising +
/// GATT server) is implemented separately via the `bluetooth_low_energy`
/// plugin, which supports both roles on Android and iOS.
///
/// This is the single highest-risk integration point in the whole app —
/// BLE peripheral/GATT-server behavior varies a lot across Android OEM
/// skins (background advertising limits, MTU negotiation quirks, GATT
/// server stability on some chipsets). Budget real on-device testing
/// time for this file specifically before trusting it in the field.
class BleTransport {
  static final BleTransport instance = BleTransport._internal();
  BleTransport._internal();

  final StreamController<DiscoveredPeer> _discoveryController =
      StreamController.broadcast();
  Stream<DiscoveredPeer> get onPeerDiscovered => _discoveryController.stream;

  bool _scanning = false;
  bool get isScanning => _scanning;

  /// Central role: scan for nearby devices advertising the Lettalk
  /// service UUID. Runs for [ProtocolConstants.scanDuration] then stops.
  Future<List<DiscoveredPeer>> scanForPeers({Duration? duration}) async {
    if (_scanning) return [];
    _scanning = true;
    final found = <String, DiscoveredPeer>{};

    try {
      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) return [];

      final subscription = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final advertisesLettalk = r.advertisementData.serviceUuids
              .map((u) => u.toString().toUpperCase())
              .contains(ProtocolConstants.lettalkServiceUuid.toUpperCase());
          if (advertisesLettalk) {
            final peer = DiscoveredPeer(
              deviceId: r.device.remoteId.str,
              rssi: r.rssi,
              device: r.device,
            );
            found[peer.deviceId] = peer;
            _discoveryController.add(peer);
          }
        }
      });

      await FlutterBluePlus.startScan(
        withServices: [Guid(ProtocolConstants.lettalkServiceUuid)],
        timeout: duration ?? ProtocolConstants.scanDuration,
      );
      await Future.delayed(duration ?? ProtocolConstants.scanDuration);
      await FlutterBluePlus.stopScan();
      await subscription.cancel();
    } finally {
      _scanning = false;
    }

    return found.values.toList();
  }

  /// Connects to a discovered peer and exchanges raw framed payloads
  /// over the Lettalk characteristic. Returns the bytes received back
  /// from the peer in response to [outgoingPayload], or null on failure.
  Future<Uint8List?> exchangePayload(
    BluetoothDevice device,
    Uint8List outgoingPayload,
  ) async {
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      final services = await device.discoverServices();
      final service = services.firstWhere(
        (s) =>
            s.uuid.toString().toUpperCase() ==
            ProtocolConstants.lettalkServiceUuid.toUpperCase(),
        orElse: () => throw Exception('Lettalk service not found on peer'),
      );
      final characteristic = service.characteristics.firstWhere(
        (c) =>
            c.uuid.toString().toUpperCase() ==
            ProtocolConstants.lettalkCharacteristicUuid.toUpperCase(),
      );

      final responseCompleter = Completer<Uint8List>();
      final chunks = <int>[];

      await characteristic.setNotifyValue(true);
      final sub = characteristic.onValueReceived.listen((value) {
        chunks.addAll(value);
        // Framing: a zero-length notify marks end-of-message.
        if (value.isEmpty && !responseCompleter.isCompleted) {
          responseCompleter.complete(Uint8List.fromList(chunks));
        }
      });

      await _writeChunked(characteristic, outgoingPayload);

      final response = await responseCompleter.future
          .timeout(const Duration(seconds: 15), onTimeout: () => Uint8List(0));
      await sub.cancel();
      await device.disconnect();
      return response.isEmpty ? null : response;
    } catch (_) {
      try {
        await device.disconnect();
      } catch (_) {/* already disconnected */}
      return null;
    }
  }

  Future<void> _writeChunked(
    BluetoothCharacteristic characteristic,
    Uint8List payload,
  ) async {
    const chunkSize = 180; // conservative, under typical negotiated MTU
    for (var i = 0; i < payload.length; i += chunkSize) {
      final end = (i + chunkSize < payload.length) ? i + chunkSize : payload.length;
      await characteristic.write(payload.sublist(i, end), withoutResponse: false);
    }
    // Empty write signals end-of-message to the peer.
    await characteristic.write(Uint8List(0), withoutResponse: false);
  }

  void dispose() {
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
/// (message IDs + small encrypted blobs), not performance-critical.
class WireMessage {
  final String type; // 'relay_table' | 'message_request' | 'message_payload'
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
