import 'dart:async';

import '../core/constants.dart';
import '../database/contact_repository.dart';
import '../database/identity_repository.dart';
import '../database/message_repository.dart';
import '../database/outbox_repository.dart';
import '../database/relay_log_repository.dart';
import '../models/contact.dart';
import '../models/message.dart';
import '../models/outbox_message.dart';
import '../utils/id_generator.dart';
import 'ble_peripheral_service.dart';
import 'ble_transport.dart';
import 'ble_logger.dart';
import 'encryption_service.dart';
import 'notification_service.dart';

/// The Uranium Protocol — Delay-Tolerant Network design.
///
/// Core philosophy: the sender only ever needs the recipient's Lettalk
/// ID. Nothing else is required to hit Send. If the recipient's public
/// key isn't known yet, the message waits — in plaintext, locally only,
/// never relayed in that form — until the network learns that key
/// (either by directly meeting the recipient, or via identity gossip
/// relayed from another node that has). At that point it's encrypted
/// and handed to the mesh like any other message.
///
/// Hard rules enforced here:
///   - Never forward the same message_id twice to the same peer
///   - Max 20 hops, then drop silently
///   - 7 day TTL on regular messages and outbox drafts, 48h on Kill Signals
///   - Relay nodes never see plaintext — only message_id + recipient_id
///   - Kill Signals propagate with the same priority as real messages
class UraniumProtocolEngine {
  static final UraniumProtocolEngine instance = UraniumProtocolEngine._internal();
  UraniumProtocolEngine._internal();

  final _messageRepo = MessageRepository();
  final _outboxRepo = OutboxRepository();
  final _relayLogRepo = RelayLogRepository();
  final _contactRepo = ContactRepository();
  final _identityRepo = IdentityRepository();
  final _encryption = EncryptionService.instance;
  final _bleTransport = BleTransport.instance;
  final _blePeripheral = BlePeripheralService.instance;

  StreamSubscription? _peripheralSub;
  bool _peripheralListenerActive = false;

  // ---------------------------------------------------------------------
  // OUTGOING — user taps Send. NEVER blocks, NEVER requires a known
  // public key. Only a recipient Lettalk ID and a message are needed.
  // ---------------------------------------------------------------------

  Future<String> sendMessage({
    required String recipientId,
    required String plaintext,
  }) async {
    final identity = await _identityRepo.getIdentity();
    if (identity == null) {
      throw StateError('No local identity — cannot send before profile setup');
    }

    final contact = await _contactRepo.getContact(recipientId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final messageId = IdGenerator.generateMessageId();

    if (contact?.publicKey != null) {
      // Fast path: we already know how to encrypt for this recipient.
      await _encryptAndStore(
        messageId: messageId,
        senderId: identity.lettalkId,
        recipientId: recipientId,
        recipientPublicKey: contact!.publicKey!,
        plaintext: plaintext,
        createdAt: now,
      );
    } else {
      // DTN path: queue in the outbox immediately. The user sees this
      // as "sent" right away — the network figures out delivery later.
      await _outboxRepo.insert(OutboxMessage(
        messageId: messageId,
        senderId: identity.lettalkId,
        recipientId: recipientId,
        plaintextContent: plaintext,
        createdAt: now,
        expiresAt: now + ProtocolConstants.messageTtl.inMilliseconds,
        status: MessageStatus.waiting,
      ));

      // Ensure the recipient at least exists as a known ID (no key yet)
      // so the chat list/thread can show them even before any encounter.
      if (contact == null) {
        await _contactRepo.upsertContact(Contact(
          lettalkId: recipientId,
          username: recipientId, // shown as the bare ID until we learn a username
          publicKey: null,
          lastSeen: now,
        ));
      }
    }

    return messageId;
  }

  Future<void> _encryptAndStore({
    required String messageId,
    required String senderId,
    required String recipientId,
    required String recipientPublicKey,
    required String plaintext,
    required int createdAt,
  }) async {
    final identity = await _identityRepo.getIdentity();
    if (identity == null) return;

    final privateKeyPlain = await _encryption.decryptPrivateKey(identity.encryptedPrivateKey);
    final sharedSecret = await _encryption.deriveSharedSecret(
      myPrivateKeyPlainBase64: privateKeyPlain,
      theirPublicKeyBase64: recipientPublicKey,
    );
    final encryptedContent = await _encryption.encryptContent(
      plaintext: plaintext,
      sharedSecret: sharedSecret,
    );

    final message = LettalkMessage(
      messageId: messageId,
      senderId: senderId,
      recipientId: recipientId,
      content: encryptedContent,
      status: MessageStatus.sent,
      createdAt: createdAt,
      expiresAt: createdAt + ProtocolConstants.messageTtl.inMilliseconds,
      hopCount: 0,
    );

    await _messageRepo.insertMessage(message);
    await _relayLogRepo.markSeen(message.messageId);
  }

  /// Called after every successful sync — checks whether any outbox
  /// drafts can now be encrypted because we just learned (directly or
  /// via gossip) the recipient's public key.
  Future<void> flushOutbox() async {
    final identity = await _identityRepo.getIdentity();
    if (identity == null) return;

    final waiting = await _outboxRepo.getAllWaiting();
    for (final draft in waiting) {
      if (draft.isExpired) {
        await _outboxRepo.markExpired(draft.messageId);
        continue;
      }
      final contact = await _contactRepo.getContact(draft.recipientId);
      if (contact?.publicKey == null) continue;

      await _encryptAndStore(
        messageId: draft.messageId,
        senderId: draft.senderId,
        recipientId: draft.recipientId,
        recipientPublicKey: contact!.publicKey!,
        plaintext: draft.plaintextContent,
        createdAt: draft.createdAt,
      );
      await _outboxRepo.remove(draft.messageId);
    }
  }

  // ---------------------------------------------------------------------
  // RELAY TABLE — metadata-only, never plaintext
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
      final alreadyForwarded = await _relayLogRepo.hasForwardedToPeer(msg.messageId, peerDeviceId);
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
  // IDENTITY GOSSIP — exchanged on every sync, alongside the relay
  // table. This is how public keys propagate through the mesh even
  // between two devices that have never directly met, and how a
  // contact's username gets filled in automatically over time.
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>> _buildOutgoingIdentity() async {
    final identity = await _identityRepo.getIdentity();
    if (identity == null) return {};
    return {
      'lettalk_id': identity.lettalkId,
      'username': identity.username,
      'public_key': identity.publicKey,
      'last_seen': DateTime.now().millisecondsSinceEpoch,
    };
  }

  Future<void> _ingestIdentities(List<dynamic> rawIdentities) async {
    final identities = rawIdentities.cast<Map<String, dynamic>>();
    if (identities.isEmpty) return;
    await _contactRepo.mergeFromGossip(identities);
    await flushOutbox();
  }

  // ---------------------------------------------------------------------
  // CENTRAL ROLE
  // ---------------------------------------------------------------------

  Future<void> syncAsCentral(DiscoveredPeer peer) async {
    final myTable = await _buildLocalRelayTable();
    final myIdentity = await _buildOutgoingIdentity();
    final myGossip = await _contactRepo.exportForGossip();

    final request = WireMessage(type: 'sync_request', body: {
      'table': myTable,
      'identity': myIdentity,
      'gossip': myGossip,
    });

    final responseBytes = await _bleTransport.exchangePayload(peer.device, request.toBytes());
    if (responseBytes == null) return;

    final response = WireMessage.fromBytes(responseBytes);
    if (response.type != 'sync_response') return;

    final peerTable = (response.body['table'] as List).cast<Map<String, dynamic>>();
    final pushedRaw = (response.body['messages'] as List).cast<Map<String, dynamic>>();
    final peerIdentity = response.body['identity'] as Map<String, dynamic>?;
    final peerGossip = (response.body['gossip'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    if (peerIdentity != null && peerIdentity.isNotEmpty) {
      await _contactRepo.mergeFromGossip([peerIdentity]);
    }
    await _ingestIdentities(peerGossip);

    for (final raw in pushedRaw) {
      await _ingestIncomingMessage(LettalkMessage.fromMap(_normalizeIncoming(raw)));
    }

    final iCanGive = await _computeGivable(peerTable, peer.deviceId);
    if (iCanGive.isNotEmpty) {
      final pushPayload = WireMessage(
        type: 'push_messages',
        body: {'messages': iCanGive.map((m) => m.toMap()).toList()},
      );
      await _bleTransport.exchangePayload(peer.device, pushPayload.toBytes());
      await _markGivenAndBump(iCanGive, peer.deviceId);
    }

    // We may now know a public key we didn't a moment ago.
    await flushOutbox();
  }

  // ---------------------------------------------------------------------
  // PERIPHERAL ROLE
  // ---------------------------------------------------------------------

  void startPeripheralListener() {
    if (_peripheralListenerActive) return;
    _peripheralListenerActive = true;
    _peripheralSub = _blePeripheral.onIncomingPayload.listen(
      (exchange) async {
        try {
          await _handlePeripheralPayload(exchange);
        } catch (e, st) {
          // A single malformed/unexpected payload (bad JSON that still
          // passed the packet-layer CRC check, an unknown wire type,
          // etc.) must never kill this subscription — if it did, the
          // peripheral role would silently stop accepting syncs from
          // every future central until the app restarted.
          BleLogger.instance.log('Error handling peripheral payload: $e\n$st');
        }
      },
      onError: (e) => BleLogger.instance.log('Peripheral payload stream error: $e'),
    );
  }

  Future<void> _handlePeripheralPayload(PeripheralExchange exchange) async {
    final wire = WireMessage.fromBytes(exchange.payload);
    switch (wire.type) {
      case 'sync_request':
        final response = await _respondToSyncRequest(wire, exchange.peerId);
        await exchange.reply(response.toBytes());
        break;
      case 'push_messages':
        final pushedRaw = (wire.body['messages'] as List).cast<Map<String, dynamic>>();
        for (final raw in pushedRaw) {
          await _ingestIncomingMessage(LettalkMessage.fromMap(_normalizeIncoming(raw)));
        }
        // A short ack reply, purely so the sender's exchangePayload call
        // completes immediately instead of blocking for the full reply
        // timeout — push_messages has nothing meaningful to answer with.
        await exchange.reply(WireMessage(type: 'push_ack', body: const {}).toBytes());
        break;
    }
  }

  Future<WireMessage> _respondToSyncRequest(WireMessage request, String peerDeviceId) async {
    final peerTable = (request.body['table'] as List).cast<Map<String, dynamic>>();
    final peerIdentity = request.body['identity'] as Map<String, dynamic>?;
    final peerGossip = (request.body['gossip'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    if (peerIdentity != null && peerIdentity.isNotEmpty) {
      await _contactRepo.mergeFromGossip([peerIdentity]);
    }
    await _ingestIdentities(peerGossip);

    final myTable = await _buildLocalRelayTable();
    final myIdentity = await _buildOutgoingIdentity();
    final myGossip = await _contactRepo.exportForGossip();

    final givable = await _computeGivable(peerTable, peerDeviceId);
    await _markGivenAndBump(givable, peerDeviceId);

    await flushOutbox();

    return WireMessage(type: 'sync_response', body: {
      'table': myTable,
      'messages': givable.map((m) => m.toMap()).toList(),
      'identity': myIdentity,
      'gossip': myGossip,
    });
  }

  Map<String, dynamic> _normalizeIncoming(Map<String, dynamic> raw) {
    final normalized = Map<String, dynamic>.from(raw);
    final kill = normalized['is_kill_signal'];
    normalized['is_kill_signal'] = (kill == true || kill == 1) ? 1 : 0;
    return normalized;
  }

  // ---------------------------------------------------------------------
  // INGEST
  // ---------------------------------------------------------------------

  Future<void> _ingestIncomingMessage(LettalkMessage incoming) async {
    if (incoming.isExpired) return;

    final alreadySeen = await _relayLogRepo.hasSeen(incoming.messageId);
    if (alreadySeen) return;

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
      await _messageRepo.updateStatus(incoming.messageId, MessageStatus.relayed);
    }
  }

  Future<void> _deliverToSelf(LettalkMessage incoming, String myId) async {
    await _messageRepo.updateStatus(incoming.messageId, MessageStatus.delivered);

    final senderContact = await _contactRepo.getContact(incoming.senderId);
    await NotificationService.instance.showMessageReceived(
      senderName: senderContact?.username ?? incoming.senderId,
    );

    await _generateAndIngestKillSignal(targetMessageId: incoming.messageId, myId: myId);
  }

  Future<void> _generateAndIngestKillSignal({
    required String targetMessageId,
    required String myId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final kill = LettalkMessage(
      messageId: IdGenerator.generateMessageId(),
      senderId: myId,
      recipientId: '*',
      content: '',
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
    await _messageRepo.insertMessage(kill);
  }

  // ---------------------------------------------------------------------
  // MAINTENANCE
  // ---------------------------------------------------------------------

  Future<void> purgeExpired() async {
    await _messageRepo.purgeExpired();
    await _outboxRepo.purgeExpired();
  }
}
