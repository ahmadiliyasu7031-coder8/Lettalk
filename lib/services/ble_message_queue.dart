import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import '../core/constants.dart';
import 'ble_logger.dart';
import 'ble_packet.dart';

/// Never writes directly to BLE (brief item 6). Every outgoing logical
/// payload goes:
///
///   enqueue -> encode -> split into BLE-MTU packets -> send -> wait ACK
///   -> next packet (retrying with backoff on ACK failure)
///
/// One [ReliablePacketChannel] wraps a single open BLE link — the
/// central side of a connection, or one connected-central's slot on the
/// peripheral side. It is transport-agnostic: it only needs a [rawSend]
/// function (one BLE write or one BLE notify) and to be fed every raw
/// value the underlying transport receives via [onRawPacketReceived].
///
/// It is also where duplicate-packet protection (brief item 8) and
/// automatic handshake replies live, since both are transport-level
/// concerns rather than application (Uranium Protocol) concerns.
///
/// Hardening notes (see also the class-level docs in ble_manager.dart):
///   - [sendReliable] calls are serialized with an internal async lock,
///     so two concurrent callers on the same channel can never
///     interleave fragments of two different logical messages.
///   - Every raw send (data, ack, or handshake-ack) is wrapped in a
///     timeout, so a platform call that never completes can't hang the
///     retry loop forever.
///   - Reassembly validates fragment order and resets itself if a gap,
///     a stale idle period, or an out-of-order fragment is detected, so
///     an interrupted transfer can never corrupt the next one.
class ReliablePacketChannel {
  final Future<void> Function(Uint8List bytes) rawSend;
  final String localDeviceId;
  final int maxRetries;
  final Duration ackTimeout;
  final Duration sendTimeout;
  final int mtu;
  final String Function()? logTag;

  ReliablePacketChannel({
    required this.rawSend,
    required this.localDeviceId,
    this.maxRetries = 4,
    this.ackTimeout = const Duration(seconds: 5),
    this.sendTimeout = const Duration(seconds: 8),
    this.mtu = 180,
    this.logTag,
  });

  final Map<int, Completer<void>> _ackWaiters = {};

  // Bounded set of recently-seen packet ids — "if the same Packet ID
  // arrives again, ignore it" (brief item 8). Bounded so a long-lived
  // connection can't grow this unboundedly.
  final Set<int> _seenPacketIds = {};
  final Queue<int> _seenOrder = Queue<int>();
  static const int _maxSeenHistory = 1000;

  // Reassembly state. `_expectedFragmentIndex` is reset whenever a
  // message completes (isLastFragment) or is abandoned (gap/timeout),
  // so a corrupted or interrupted transfer can never bleed into the
  // next one.
  BytesBuilder _reassemblyBuffer = BytesBuilder();
  int _expectedFragmentIndex = 0;
  DateTime? _reassemblyStartedAt;
  DateTime _lastActivity = DateTime.now();

  // Serializes sendReliable calls on this channel so concurrent callers
  // (e.g. a future refactor that sends from two places at once) can
  // never interleave fragments of two different logical messages on
  // the same wire.
  Future<void> _sendLock = Future.value();

  final StreamController<Uint8List> _incomingPayloads = StreamController.broadcast();
  Stream<Uint8List> get incomingPayloads => _incomingPayloads.stream;

  final StreamController<BlePacket> _handshakePackets = StreamController.broadcast();
  Stream<BlePacket> get onHandshakePacket => _handshakePackets.stream;

  bool _closed = false;
  bool get isClosed => _closed;

  DateTime get lastActivity => _lastActivity;

  String get _tag => logTag?.call() ?? localDeviceId;

  void _touch() => _lastActivity = DateTime.now();

  /// Feed this every raw value the transport receives (a GATT
  /// characteristic write-request value on the peripheral side, or a
  /// notify value on the central side). Never throws — any failure here
  /// is logged and the packet is dropped, since a malformed/corrupt
  /// packet must never crash the BLE stack or wedge the channel.
  Future<void> onRawPacketReceived(Uint8List bytes) async {
    if (_closed) return;
    _touch();

    BlePacket? packet;
    try {
      packet = BlePacket.decode(bytes);
    } catch (e) {
      BleLogger.instance.log('Packet decode threw: $e', deviceId: _tag);
      return;
    }

    if (packet == null) {
      BleLogger.instance.log('Dropped corrupt packet (CRC/format check failed)', deviceId: _tag);
      return;
    }

    try {
      if (packet.type == BlePacketType.ack) {
        final waiter = _ackWaiters.remove(packet.packetId);
        if (waiter != null && !waiter.isCompleted) {
          waiter.complete();
        }
        // A duplicate/late ACK for an id we no longer track (already
        // completed, already timed out, or never sent) is expected and
        // harmless — nothing further to do.
        return;
      }

      if (_isDuplicate(packet.packetId)) {
        BleLogger.instance.log('Duplicate packet ${packet.packetId} ignored', deviceId: _tag);
        // Still ack it — the sender is retrying because our first ack
        // was lost, not because it wants us to reprocess the payload.
        await _sendAck(packet);
        return;
      }
      _markSeen(packet.packetId);
      await _sendAck(packet);

      if (packet.type == BlePacketType.handshake || packet.type == BlePacketType.handshakeAck) {
        if (!_handshakePackets.isClosed) _handshakePackets.add(packet);
        return;
      }

      if (packet.type == BlePacketType.keepalive) return;

      // packet.type == data — validate ordering before appending, so an
      // out-of-order or gapped fragment (a corrupted/interrupted
      // transfer, or a stray retransmit that slipped past dedupe due to
      // an id collision) can never silently produce a garbled payload.
      _appendDataFragment(packet);
    } catch (e, st) {
      BleLogger.instance.log('Error handling packet ${packet.packetId}: $e', deviceId: _tag);
      _resetReassembly(reason: 'exception while handling packet: $e\n$st');
    }
  }

  void _appendDataFragment(BlePacket packet) {
    if (packet.fragmentIndex == 0) {
      // Fragment 0 always (re)starts a message. If we had a
      // still-in-progress reassembly from a previous, never-completed
      // transfer, drop it rather than silently prepending stale bytes.
      if (_reassemblyBuffer.length > 0) {
        BleLogger.instance.log(
          'New message started before previous one completed — discarding ${_reassemblyBuffer.length} stale bytes',
          deviceId: _tag,
        );
      }
      _reassemblyBuffer = BytesBuilder();
      _expectedFragmentIndex = 0;
      _reassemblyStartedAt = DateTime.now();
    }

    if (packet.fragmentIndex != _expectedFragmentIndex) {
      BleLogger.instance.log(
        'Out-of-order fragment (got ${packet.fragmentIndex}, expected $_expectedFragmentIndex) — discarding in-progress message',
        deviceId: _tag,
      );
      _resetReassembly(reason: 'out-of-order fragment');
      return;
    }

    _reassemblyBuffer.add(packet.payload);
    _expectedFragmentIndex++;

    if (packet.isLastFragment) {
      final complete = _reassemblyBuffer.takeBytes();
      BleLogger.instance.log('Packet received (${complete.length} bytes reassembled)', deviceId: _tag);
      _reassemblyBuffer = BytesBuilder();
      _expectedFragmentIndex = 0;
      _reassemblyStartedAt = null;
      if (!_incomingPayloads.isClosed) _incomingPayloads.add(complete);
    }
  }

  void _resetReassembly({required String reason}) {
    if (_reassemblyBuffer.length > 0) {
      BleLogger.instance.log('Resetting reassembly buffer: $reason', deviceId: _tag);
    }
    _reassemblyBuffer = BytesBuilder();
    _expectedFragmentIndex = 0;
    _reassemblyStartedAt = null;
  }

  /// Called periodically by the owner (BleManager or the peripheral
  /// service) to abandon a reassembly that's been stuck mid-transfer
  /// for too long — an interrupted transfer (brief item: "interrupted
  /// transfers") that never sent a last fragment, or never will.
  void checkForStalledReassembly() {
    final startedAt = _reassemblyStartedAt;
    if (startedAt == null) return;
    if (DateTime.now().difference(startedAt) > ProtocolConstants.channelIdleTimeout) {
      _resetReassembly(reason: 'transfer stalled/interrupted (no last-fragment within timeout)');
    }
  }

  Future<void> _sendAck(BlePacket packet) async {
    final ack = BlePacket(
      type: BlePacketType.ack,
      packetId: packet.packetId,
      senderId: localDeviceId,
      receiverId: packet.senderId,
      fragmentIndex: 0,
      isLastFragment: true,
      payload: Uint8List(0),
    );
    try {
      await _guardedRawSend(ack.encode());
      BleLogger.instance.log('ACK sent for packet ${packet.packetId}', deviceId: _tag);
    } catch (e) {
      // Losing an ACK is recoverable (the sender will retry and we'll
      // just resend the ack via the duplicate-packet path), so this is
      // logged, not rethrown.
      BleLogger.instance.log('Failed to send ACK for packet ${packet.packetId}: $e', deviceId: _tag);
    }
  }

  /// Wraps every raw platform call with a hard timeout so a wedged BLE
  /// stack (write/notify call that never completes) can never hang a
  /// retry loop or the whole sync forever.
  Future<void> _guardedRawSend(Uint8List bytes) {
    return rawSend(bytes).timeout(
      sendTimeout,
      onTimeout: () => throw TimeoutException('raw BLE send timed out after $sendTimeout'),
    );
  }

  bool _isDuplicate(int packetId) => _seenPacketIds.contains(packetId);

  void _markSeen(int packetId) {
    _seenPacketIds.add(packetId);
    _seenOrder.addLast(packetId);
    if (_seenOrder.length > _maxSeenHistory) {
      _seenPacketIds.remove(_seenOrder.removeFirst());
    }
  }

  /// Sends a full logical payload reliably, fragment by fragment,
  /// retrying each fragment with backoff until it's ACKed. Returns
  /// false (without partial re-send of already-ACKed fragments) if a
  /// fragment exhausts its retries. Calls are serialized per-channel —
  /// see [_sendLock] — so concurrent invocations queue rather than
  /// interleaving fragments on the wire.
  Future<bool> sendReliable({
    required BlePacketType type,
    required String receiverId,
    required Uint8List payload,
  }) async {
    if (_closed) {
      BleLogger.instance.log('sendReliable called on a disposed channel — ignoring', deviceId: _tag);
      return false;
    }

    // Chain onto the existing lock so this call only starts once every
    // previously-queued send on this channel has finished, regardless
    // of whether that one succeeded, failed, or threw.
    final previous = _sendLock;
    final completer = Completer<void>();
    _sendLock = completer.future;
    await previous;

    try {
      return await _sendReliableUnlocked(type: type, receiverId: receiverId, payload: payload);
    } finally {
      completer.complete();
    }
  }

  Future<bool> _sendReliableUnlocked({
    required BlePacketType type,
    required String receiverId,
    required Uint8List payload,
  }) async {
    final fragments = fragmentPayload(
      type: type,
      senderId: localDeviceId,
      receiverId: receiverId,
      payload: payload,
      mtu: mtu,
    );

    for (final fragment in fragments) {
      if (_closed) return false;

      var attempt = 0;
      var acked = false;
      while (attempt < maxRetries && !acked) {
        attempt++;
        final completer = Completer<void>();
        _ackWaiters[fragment.packetId] = completer;
        try {
          _touch();
          await _guardedRawSend(fragment.encode());
          BleLogger.instance.log(
            'Packet sent (${fragment.packetId}, fragment ${fragment.fragmentIndex}${fragment.isLastFragment ? ", last" : ""})',
            deviceId: _tag,
          );
          await completer.future.timeout(ackTimeout);
          acked = true;
          _touch();
          BleLogger.instance.log('ACK received for packet ${fragment.packetId}', deviceId: _tag);
        } catch (e) {
          _ackWaiters.remove(fragment.packetId);
          if (attempt < maxRetries) {
            BleLogger.instance.log(
              'Retry $attempt/$maxRetries for packet ${fragment.packetId} ($e)',
              deviceId: _tag,
            );
            await Future.delayed(Duration(milliseconds: 200 * attempt));
          }
        }
      }
      if (!acked) {
        BleLogger.instance.log(
          'Packet ${fragment.packetId} failed after $maxRetries retries — aborting send',
          deviceId: _tag,
        );
        return false;
      }
    }
    return true;
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    for (final waiter in _ackWaiters.values) {
      if (!waiter.isCompleted) waiter.completeError(StateError('channel disposed'));
    }
    _ackWaiters.clear();
    _resetReassembly(reason: 'channel disposed');
    if (!_incomingPayloads.isClosed) _incomingPayloads.close();
    if (!_handshakePackets.isClosed) _handshakePackets.close();
    BleLogger.instance.log('Channel disposed', deviceId: _tag);
  }
}

/// Convenience factory using the shared protocol constants, so callers
/// don't have to repeat the same call-sites' worth of values.
ReliablePacketChannel createChannel({
  required Future<void> Function(Uint8List bytes) rawSend,
  required String localDeviceId,
  String Function()? logTag,
}) {
  return ReliablePacketChannel(
    rawSend: rawSend,
    localDeviceId: localDeviceId,
    maxRetries: ProtocolConstants.packetMaxRetries,
    ackTimeout: ProtocolConstants.packetAckTimeout,
    sendTimeout: ProtocolConstants.rawSendTimeout,
    mtu: ProtocolConstants.blePacketMtu,
    logTag: logTag,
  );
}
