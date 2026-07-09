import '../core/constants.dart';

class LettalkMessage {
  final String messageId;
  final String senderId;
  final String recipientId;
  final String content; // encrypted blob, base64
  final String status; // sent | relayed | delivered | killed
  final int createdAt;
  final int expiresAt;
  final bool isKillSignal;
  final String? targetMessageId; // only set when isKillSignal == true
  final int hopCount;

  LettalkMessage({
    required this.messageId,
    required this.senderId,
    required this.recipientId,
    required this.content,
    this.status = MessageStatus.sent,
    required this.createdAt,
    required this.expiresAt,
    this.isKillSignal = false,
    this.targetMessageId,
    this.hopCount = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'message_id': messageId,
      'sender_id': senderId,
      'recipient_id': recipientId,
      'content': content,
      'status': status,
      'created_at': createdAt,
      'expires_at': expiresAt,
      'is_kill_signal': isKillSignal ? 1 : 0,
      'target_message_id': targetMessageId,
      'hop_count': hopCount,
    };
  }

  factory LettalkMessage.fromMap(Map<String, dynamic> map) {
    return LettalkMessage(
      messageId: map['message_id'] as String,
      senderId: map['sender_id'] as String,
      recipientId: map['recipient_id'] as String,
      content: map['content'] as String,
      status: map['status'] as String? ?? MessageStatus.sent,
      createdAt: map['created_at'] as int,
      expiresAt: map['expires_at'] as int,
      isKillSignal: (map['is_kill_signal'] as int? ?? 0) == 1,
      targetMessageId: map['target_message_id'] as String?,
      hopCount: map['hop_count'] as int? ?? 0,
    );
  }

  LettalkMessage copyWith({String? status, int? hopCount}) {
    return LettalkMessage(
      messageId: messageId,
      senderId: senderId,
      recipientId: recipientId,
      content: content,
      status: status ?? this.status,
      createdAt: createdAt,
      expiresAt: expiresAt,
      isKillSignal: isKillSignal,
      targetMessageId: targetMessageId,
      hopCount: hopCount ?? this.hopCount,
    );
  }

  bool get isExpired => DateTime.now().millisecondsSinceEpoch > expiresAt;
}
