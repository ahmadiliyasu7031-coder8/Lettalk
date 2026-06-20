import '../models/message.dart';
import '../models/outbox_message.dart';

/// Unifies a real (encrypted, relayable) message and an outbox (plaintext,
/// local-only, waiting-for-key) draft into one sortable type for display
/// in chat lists/threads. The UI layer decides how to render each variant;
/// nothing about encryption or relay logic depends on this type.
sealed class ThreadItem {
  String get messageId;
  String get senderId;
  String get recipientId;
  int get createdAt;
}

class RealMessageItem implements ThreadItem {
  final LettalkMessage message;
  RealMessageItem(this.message);

  @override
  String get messageId => message.messageId;
  @override
  String get senderId => message.senderId;
  @override
  String get recipientId => message.recipientId;
  @override
  int get createdAt => message.createdAt;
}

class OutboxItem implements ThreadItem {
  final OutboxMessage outbox;
  OutboxItem(this.outbox);

  @override
  String get messageId => outbox.messageId;
  @override
  String get senderId => outbox.senderId;
  @override
  String get recipientId => outbox.recipientId;
  @override
  int get createdAt => outbox.createdAt;
}

List<ThreadItem> mergeAndSort(List<LettalkMessage> messages, List<OutboxMessage> outbox) {
  final items = <ThreadItem>[
    ...messages.map((m) => RealMessageItem(m)),
    ...outbox.map((o) => OutboxItem(o)),
  ];
  items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return items;
}
