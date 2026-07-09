/// A message composed before the recipient's public key was known.
/// Stored in PLAINTEXT, locally, on the sender's device only — it is
/// never relayed in this form (relay nodes must never see plaintext).
/// Once the Uranium engine learns the recipient's public key (via direct
/// encounter or identity gossip from another node), this gets encrypted
/// and "promoted" into a real message in the main `messages` table,
/// at which point it becomes relayable like any other message.
class OutboxMessage {
  final String messageId;
  final String senderId;
  final String recipientId;
  final String plaintextContent;
  final int createdAt;
  final int expiresAt;
  final String status; // waiting | expired

  OutboxMessage({
    required this.messageId,
    required this.senderId,
    required this.recipientId,
    required this.plaintextContent,
    required this.createdAt,
    required this.expiresAt,
    this.status = 'waiting',
  });

  Map<String, dynamic> toMap() => {
        'message_id': messageId,
        'sender_id': senderId,
        'recipient_id': recipientId,
        'plaintext_content': plaintextContent,
        'created_at': createdAt,
        'expires_at': expiresAt,
        'status': status,
      };

  factory OutboxMessage.fromMap(Map<String, dynamic> map) => OutboxMessage(
        messageId: map['message_id'] as String,
        senderId: map['sender_id'] as String,
        recipientId: map['recipient_id'] as String,
        plaintextContent: map['plaintext_content'] as String,
        createdAt: map['created_at'] as int,
        expiresAt: map['expires_at'] as int,
        status: map['status'] as String? ?? 'waiting',
      );

  bool get isExpired => DateTime.now().millisecondsSinceEpoch > expiresAt;
}
