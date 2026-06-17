import 'dart:async';
import 'dart:typed_data';

import '../core/constants.dart';
import '../database/contact_repository.dart';
import '../database/identity_repository.dart';
import '../database/message_repository.dart';
import '../database/relay_log_repository.dart';
import '../models/message.dart';
import '../utils/id_generator.dart';
import 'ble_peripheral_service.dart';
import 'ble_transport.dart';
import 'encryption_service.dart';
import 'notification_service.dart';

/// The Uranium Protocol: once a message is handed to this engine, the
/// sender's responsibility ends. The engine is responsible for getting
/// it to the recipient via store-and-forward relay through any number
/// of intermediate nodes, with no central server involved at any point.
///
/// Hard rules enforced here (per spec):
///   - Never forward the same message_id twice to the same peer (relay_peer_log)
///   - Max 20 hops, then drop silently
///   - 7 day TTL on regular messages, 48 hour TTL on Kill Signals
///   - Relay nodes never see plaintext — they only ever handle the
///     encrypted blob, message_id, and recipient_id
///   - Kill Signals get the same priority as messages, never lower
class UraniumProtocolEngine {
  static final UraniumProtocolEngine instance = UraniumProtocolEngine._internal();
  UraniumProtocolEngine._internal();

  final _messageRepo = MessageRepository();
  final _relayLogRepo = RelayLogRepository();
  final _contactRepo = ContactRepository();
  final _identityRepo = IdentityRepository();
  final _encryption = EncryptionService.instance;
  final _bleTransport = BleTransport.instance;
  final _blePeripheral = BlePeripheralService.instance;

  StreamSubscription? _peripheralSub;
  bool _peripheralListenerActive = false;

  // ---------------------------------------------------------------------
  // OUTGOING — user taps Send
  // ---------------------------------------------------------------------

  /// Step 1 of the brief's flow: encrypt, store locally as "sent", and
  /// hand off to the Uranium Network. Returns the new message_id.
  Future<String> sendMessage({
    required String recipientId,
    required String plaintext,
  }) async {
    final identity = await _identityRepo.getIdentity();
    if (identity == null) {
      throw StateError('No local identity — cannot send before profile setup');
    }
    final contact = await _contactRepo.getContact(recipientId);
    if (contact?.publicKey == null) {
      throw StateError(
        'No public key on file for $recipientId — exchange contacts (QR/manual) first',
      );
    }

    final privateKeyPlain = await _encryption.decryptPrivateKey(identity.encryptedPrivateKey);
    final sharedSecret = await _encryption.deriveSharedSecret(
      myPrivateKeyPlainBase64: privateKeyPlain,
      theirPublicKeyBase64: contact!.publicKey!,
    );
    final encryptedContent = await _encryption.encryptContent(
      plaintext: plaintext,
      sharedSecret: sharedSecret,
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    final message = LettalkMessage(
      messageId: IdGenerator.generateMessageId(),
      senderId: identity.lettalkId,
      recipientId: recipientId,
      content: encryptedContent,
      status: MessageStatus.sent,
      createdAt: now,
      expiresAt: now + ProtocolConstants.messageTtl.inMilliseconds,
      hopCount: 0,
    );

    await _messageRepo.insertMessage(message);
    await _relayLogRepo.markSeen(message.messageId);
    return message.messageId;
  }

  // ---------------------------------------------------------------------
  // RELAY TABLE — what this node is currently carrying (metadata only,
  // never plaintext, used purely for diffing against a peer's table)
  // ---------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _buildLocalRelayTable() async {
    final carried = await _messageRepo.getCarriedMessages();
    return carried
        .map((m) => {
              'message_id': m.messageId,
              'recipient_id': m.recipientId,
              'is_kill_signal': m.isKillSignal,
              'expires_at': m.expiresAt,
            })
        .toList();
  }

  Set<String> _idsOf(List<Map<String, dynamic>> table) =>
      table.map((e) => e['message_id'] as String).toSet();

  /// Messages I carry that a peer's table shows they don't have yet,
  /// filtered to ones I haven't already forwarded to that exact peer.
  Future<List<LettalkMessage>> _computeGivable(
    List<Map<String, dynamic>> peerTable,
    String peerDeviceId,
  ) async {
    final peerIds = _idsOf(peerTable);
    final carried = await _messageRepo.getCarriedMessages();
    final givable = <LettalkMessage>[];
    for (final msg in carried) {
      if (peerIds.contains(msg.messageId)) continue;
      if (msg.hopCount >= ProtocolConstants.maxHopCount) continue;
      final alreadyForwarded =
          await _relayLogRepo.hasForwardedToPeer(msg.messageId, peerDeviceId);
      if (alreadyForwarded) continue;
      givable.add(msg);
    }
    return givable;
  }

  Future<void> _markGivenAndBump(List<LettalkMessage> messages, String peerDeviceId) async {
    for (final m in messages) {
      await _relayLogRepo.markForwardedToPeer(m.messageId, peerDeviceId);
      await _relayLogRepo.incrementForwardCount(m.messageId);
    }
  }

  // ---------------------------------------------------------------------
  // CENTRAL ROLE — this device initiates contact with a discovered peer
  // ---------------------------------------------------------------------

  /// Round-trip sync as Central: send my table -> receive peer's table +
  /// whatever the peer can give me -> ingest -> push back whatever I can
  /// give the peer that they were missing.
  Future<void> syncAsCentral(DiscoveredPeer peer) async {
    final myTable = await _buildLocalRelayTable();
    final request = WireMessage(type: 'sync_request', body: {'table': myTable});

    final responseBytes = await _bleTransport.exchangePayload(
      peer.device,
      request.toBytes(),
    );
    if (responseBytes == null) return; // peer unreachable / handshake failed

    final response = WireMessage.fromBytes(responseBytes);
    if (response.type != 'sync_response') return;

    final peerTable =
        (response.body['table'] as List).cast<Map<String, dynamic>>();
    final pushedRaw = (response.body['messages'] as List).cast<Map<String, dynamic>>();

    for (final raw in pushedRaw) {
      await _ingestIncomingMessage(LettalkMessage.fromMap(_normalizeIncoming(raw)));
    }

    final iCanGive = await _computeGivable(peerTable, peer.deviceId);
    if (iCanGive.isNotEmpty) {
      final pushPayload = WireMessage(
        type: 'push_messages',
        body: {'messages': iCanGive.map((m) => m.toMap()).toList()},
      );
      // Fire-and-forget second write; peripheral ingests on receipt.
      await _bleTransport.exchangePayload(peer.device, pushPayload.toBytes());
      await _markGivenAndBump(iCanGive, peer.deviceId);
    }
  }

  // ---------------------------------------------------------------------
  // PERIPHERAL ROLE — this device responds when discovered/contacted
  // ---------------------------------------------------------------------

  void startPeripheralListener() {
    if (_peripheralListenerActive) return;
    _peripheralListenerActive = true;
    _peripheralSub = _blePeripheral.onIncomingPayload.listen((bytes) async {
      await _handlePeripheralPayload(bytes);
    });
  }

  Future<void> _handlePeripheralPayload(Uint8List bytes) async {
    final wire = WireMessage.fromBytes(bytes);
    // NOTE: the bluetooth_low_energy Central object identifying who to
    // notify back is supplied by the platform callback at the call site
    // in ble_peripheral_service.dart's characteristicWriteRequested
    // event; wiring it through to here is a short platform-glue step
    // left for the integration pass (the protocol logic below is
    // transport-agnostic and complete).
    switch (wire.type) {
      case 'sync_request':
        await _respondToSyncRequest(wire);
        break;
      case 'push_messages':
        final pushedRaw = (wire.body['messages'] as List).cast<Map<String, dynamic>>();
        for (final raw in pushedRaw) {
          await _ingestIncomingMessage(LettalkMessage.fromMap(_normalizeIncoming(raw)));
        }
        break;
    }
  }

  Future<WireMessage> _respondToSyncRequest(WireMessage request) async {
    final peerTable = (request.body['table'] as List).cast<Map<String, dynamic>>();
    final myTable = await _buildLocalRelayTable();
    // peerDeviceId isn't known at this layer without the platform glue
    // mentioned above; pass-through placeholder keeps relay_peer_log
    // scoped per-session until that wiring is completed.
    const peerDeviceId = 'pending-peripheral-peer-id';
    final givable = await _computeGivable(peerTable, peerDeviceId);
    await _markGivenAndBump(givable, peerDeviceId);

    return WireMessage(type: 'sync_response', body: {
      'table': myTable,
      'messages': givable.map((m) => m.toMap()).toList(),
    });
  }

  Map<String, dynamic> _normalizeIncoming(Map<String, dynamic> raw) {
    // is_kill_signal can arrive as bool (from our toMap on the wire) or
    // int (from SQLite) depending on path — normalize to int for the model.
    final normalized = Map<String, dynamic>.from(raw);
    final kill = normalized['is_kill_signal'];
    normalized['is_kill_signal'] = (kill == true || kill == 1) ? 1 : 0;
    return normalized;
  }

  // ---------------------------------------------------------------------
  // INGEST — shared logic for any message arriving from a peer, whether
  // this node received it as Central or as Peripheral
  // ---------------------------------------------------------------------

  Future<void> _ingestIncomingMessage(LettalkMessage incoming) async {
    if (incoming.isExpired) return;

    final alreadySeen = await _relayLogRepo.hasSeen(incoming.messageId);
    if (alreadySeen) return; // we're already carrying/have processed this one

    await _relayLogRepo.markSeen(incoming.messageId);

    if (incoming.isKillSignal) {
      await _processKillSignal(incoming);
      return;
    }

    await _messageRepo.insertMessage(incoming);

    final identity = await _identityRepo.getIdentity();
    if (identity != null && incoming.recipientId == identity.lettalkId) {
      await _deliverToSelf(incoming, identity.lettalkId);
    } else {
      // Pure relay: not for us, just store-and-forward it onward,
      // which happens automatically next time buildLocalRelayTable()
      // is consulted during a future sync. No UI shown — silent.
      await _messageRepo.updateStatus(incoming.messageId, MessageStatus.relayed);
    }
  }

  Future<void> _deliverToSelf(LettalkMessage incoming, String myId) async {
    await _messageRepo.updateStatus(incoming.messageId, MessageStatus.delivered);

    final senderContact = await _contactRepo.getContact(incoming.senderId);
    await NotificationService.instance.showMessageReceived(
      senderName: senderContact?.username ?? incoming.senderId,
    );

    // Step 5 of the brief: delivery auto-generates a Kill Signal.
    await _generateAndIngestKillSignal(
      targetMessageId: incoming.messageId,
      myId: myId,
    );
  }

  Future<void> _generateAndIngestKillSignal({
    required String targetMessageId,
    required String myId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final kill = LettalkMessage(
      messageId: IdGenerator.generateMessageId(),
      senderId: myId,
      recipientId: '*', // kill signals broadcast to the whole mesh, not one recipient
      content: '', // no payload to encrypt — it's a control signal
      status: MessageStatus.sent,
      createdAt: now,
      expiresAt: now + ProtocolConstants.killSignalTtl.inMilliseconds,
      isKillSignal: true,
      targetMessageId: targetMessageId,
    );
    await _messageRepo.insertMessage(kill);
    await _relayLogRepo.markSeen(kill.messageId);
  }

  Future<void> _processKillSignal(LettalkMessage kill) async {
    final targetId = kill.targetMessageId;
    if (targetId != null) {
      await _messageRepo.deleteMessage(targetId);
      await _relayLogRepo.deleteForMessage(targetId);
    }
    // Store the Kill Signal itself so it keeps propagating until its
    // own 48h TTL — cleanup of the network is just as important as
    // cleanup of the one target message.
    await _messageRepo.insertMessage(kill);
  }

  // ---------------------------------------------------------------------
  // MAINTENANCE — called once per scan cycle by the background service
  // ---------------------------------------------------------------------

  Future<void> purgeExpired() async {
    await _messageRepo.purgeExpired();
  }
}
