import 'dart:async';
import 'dart:collection';

/// Structured log entry for a single BLE-layer operation.
class BleLogEntry {
  final DateTime timestamp;
  final String message;
  final String? deviceId;

  BleLogEntry({required this.timestamp, required this.message, this.deviceId});

  @override
  String toString() {
    final ts = timestamp.toIso8601String().substring(11, 23); // HH:mm:ss.SSS
    final tag = deviceId != null ? ' [$deviceId]' : '';
    return '[$ts]$tag $message';
  }
}

/// Central logging sink for every BLE Manager operation (item 11 of the
/// brief): advertising, scanning, discovery, connection, handshake, sync,
/// packet send/receive/ack/retry, disconnects and reconnects all funnel
/// through here.
///
/// Kept intentionally dependency-free (no UI, no DB) so it can be called
/// from anywhere in the BLE stack, including the background-service
/// isolate. A bounded in-memory ring buffer is retained so a debug/log
/// screen can show recent history without needing its own storage.
class BleLogger {
  static final BleLogger instance = BleLogger._internal();
  BleLogger._internal();

  static const int _maxHistory = 500;

  final Queue<BleLogEntry> _history = Queue<BleLogEntry>();
  final StreamController<BleLogEntry> _controller = StreamController.broadcast();

  Stream<BleLogEntry> get stream => _controller.stream;
  List<BleLogEntry> get history => List.unmodifiable(_history);

  void log(String message, {String? deviceId}) {
    final entry = BleLogEntry(timestamp: DateTime.now(), message: message, deviceId: deviceId);
    _history.addLast(entry);
    if (_history.length > _maxHistory) {
      _history.removeFirst();
    }
    // ignore: avoid_print
    print('[Lettalk-BLE] $entry');
    if (!_controller.isClosed) {
      _controller.add(entry);
    }
  }

  void dispose() {
    _controller.close();
  }
}
