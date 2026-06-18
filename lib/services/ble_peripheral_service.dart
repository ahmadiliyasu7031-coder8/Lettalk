import 'dart:async';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

import '../core/constants.dart';

class BlePeripheralService {
  static final BlePeripheralService instance = BlePeripheralService._internal();
  BlePeripheralService._internal();

  PeripheralManager? _manager;
  bool _advertising = false;
  bool get isAdvertising => _advertising;

  final _incomingBuffer = <int>[];
  final StreamController<Uint8List> _incomingPayloads = StreamController.broadcast();
  Stream<Uint8List> get onIncomingPayload => _incomingPayloads.stream;

  GATTCharacteristic? _characteristic;

  Future<void> startAdvertising() async {
    if (_advertising) return;
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

    _manager!.characteristicWriteRequested.listen((event) {
      final value = event.request.value;
      if (value.isEmpty) {
        if (_incomingBuffer.isNotEmpty) {
          _incomingPayloads.add(Uint8List.fromList(_incomingBuffer));
          _incomingBuffer.clear();
        }
      } else {
        _incomingBuffer.addAll(value);
      }
    });

    await _manager!.startAdvertising(
      Advertisement(
        name: 'Lettalk',
        serviceUUIDs: [UUID.fromString(ProtocolConstants.lettalkServiceUuid)],
      ),
    );
    _advertising = true;
  }

  Future<void> sendResponse(Central central, Uint8List payload) async {
    final characteristic = _characteristic;
    final manager = _manager;
    if (characteristic == null || manager == null) return;

    const chunkSize = 180;
    for (var i = 0; i < payload.length; i += chunkSize) {
      final end = (i + chunkSize < payload.length) ? i + chunkSize : payload.length;
      await manager.notifyCharacteristic(
        central,
        characteristic,
        value: payload.sublist(i, end),
      );
    }
    await manager.notifyCharacteristic(
      central,
      characteristic,
      value: Uint8List(0),
    );
  }

  Future<void> stopAdvertising() async {
    await _manager?.stopAdvertising();
    _advertising = false;
  }

  void dispose() {
    _incomingPayloads.close();
  }
}
