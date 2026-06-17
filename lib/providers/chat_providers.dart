import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/contact_repository.dart';
import '../database/message_repository.dart';
import '../models/contact.dart';
import '../models/message.dart';
import '../services/uranium_protocol.dart';
import 'identity_provider.dart';

final contactRepositoryProvider = Provider<ContactRepository>((ref) => ContactRepository());
final messageRepositoryProvider = Provider<MessageRepository>((ref) => MessageRepository());

final contactsProvider = AsyncNotifierProvider<ContactsNotifier, List<Contact>>(
  ContactsNotifier.new,
);

class ContactsNotifier extends AsyncNotifier<List<Contact>> {
  @override
  Future<List<Contact>> build() async {
    final repo = ref.read(contactRepositoryProvider);
    return repo.getAllContacts();
  }

  Future<void> addOrUpdateContact({
    required String lettalkId,
    required String username,
    String? publicKey,
  }) async {
    final repo = ref.read(contactRepositoryProvider);
    await repo.upsertContact(Contact(
      lettalkId: lettalkId,
      username: username,
      publicKey: publicKey,
      lastSeen: DateTime.now().millisecondsSinceEpoch,
    ));
    ref.invalidateSelf();
    await future;
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

/// Latest message per conversation, for the Chats home screen list.
final conversationsProvider = AsyncNotifierProvider<ConversationsNotifier, List<LettalkMessage>>(
  ConversationsNotifier.new,
);

class ConversationsNotifier extends AsyncNotifier<List<LettalkMessage>> {
  @override
  Future<List<LettalkMessage>> build() async {
    final identity = await ref.watch(identityProvider.future);
    if (identity == null) return [];
    final repo = ref.read(messageRepositoryProvider);
    return repo.getLatestPerConversation(identity.lettalkId);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

/// Lifetime message stats for the Profile screen.
final messageStatsProvider = FutureProvider.autoDispose<({int sent, int received})>((ref) async {
  final identity = await ref.watch(identityProvider.future);
  if (identity == null) return (sent: 0, received: 0);
  final repo = ref.read(messageRepositoryProvider);
  final sent = await repo.countSent(identity.lettalkId);
  final received = await repo.countReceived(identity.lettalkId);
  return (sent: sent, received: received);
});

/// Full thread with one contact, for the Chat screen.
final conversationThreadProvider =
    AsyncNotifierProvider.family<ConversationThreadNotifier, List<LettalkMessage>, String>(
  ConversationThreadNotifier.new,
);

class ConversationThreadNotifier extends FamilyAsyncNotifier<List<LettalkMessage>, String> {
  @override
  Future<List<LettalkMessage>> build(String otherLettalkId) async {
    final identity = await ref.watch(identityProvider.future);
    if (identity == null) return [];
    final repo = ref.read(messageRepositoryProvider);
    return repo.getConversation(identity.lettalkId, otherLettalkId);
  }

  Future<void> sendMessage(String plaintext) async {
    await UraniumProtocolEngine.instance.sendMessage(
      recipientId: arg,
      plaintext: plaintext,
    );
    ref.invalidateSelf();
    await future;
    // Conversation list on Home also needs to reflect the new message.
    ref.invalidate(conversationsProvider);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}
