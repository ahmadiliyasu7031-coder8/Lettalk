import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/contact_repository.dart';
import '../database/message_repository.dart';
import '../database/outbox_repository.dart';
import '../models/contact.dart';
import '../models/thread_item.dart';
import '../services/uranium_protocol.dart';
import 'identity_provider.dart';

final contactRepositoryProvider = Provider<ContactRepository>((ref) => ContactRepository());
final messageRepositoryProvider = Provider<MessageRepository>((ref) => MessageRepository());
final outboxRepositoryProvider = Provider<OutboxRepository>((ref) => OutboxRepository());

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

/// Latest item (real message OR outbox draft) per conversation, for the
/// Chats home screen list. A conversation the user just started by
/// messaging an unknown ID shows up immediately via its outbox entry.
final conversationsProvider = AsyncNotifierProvider<ConversationsNotifier, List<ThreadItem>>(
  ConversationsNotifier.new,
);

class ConversationsNotifier extends AsyncNotifier<List<ThreadItem>> {
  @override
  Future<List<ThreadItem>> build() async {
    final identity = await ref.watch(identityProvider.future);
    if (identity == null) return [];
    final messageRepo = ref.read(messageRepositoryProvider);
    final outboxRepo = ref.read(outboxRepositoryProvider);

    final latestMessages = await messageRepo.getLatestPerConversation(identity.lettalkId);
    final latestOutbox = await outboxRepo.getLatestPerConversation(identity.lettalkId);

    // For any conversation that has BOTH a real message and an outbox
    // draft, keep only whichever is more recent so each thread shows
    // exactly one entry in the list.
    final byPartner = <String, ThreadItem>{};
    for (final m in latestMessages) {
      final partner = m.senderId == identity.lettalkId ? m.recipientId : m.senderId;
      byPartner[partner] = RealMessageItem(m);
    }
    for (final o in latestOutbox) {
      final partner = o.senderId == identity.lettalkId ? o.recipientId : o.senderId;
      final existing = byPartner[partner];
      if (existing == null || o.createdAt > existing.createdAt) {
        byPartner[partner] = OutboxItem(o);
      }
    }

    final items = byPartner.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
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

/// Full thread with one contact, merging real messages and outbox
/// drafts in chronological order, for the Chat screen.
final conversationThreadProvider =
    AsyncNotifierProvider.family<ConversationThreadNotifier, List<ThreadItem>, String>(
  ConversationThreadNotifier.new,
);

class ConversationThreadNotifier extends FamilyAsyncNotifier<List<ThreadItem>, String> {
  @override
  Future<List<ThreadItem>> build(String otherLettalkId) async {
    final identity = await ref.watch(identityProvider.future);
    if (identity == null) return [];
    final messageRepo = ref.read(messageRepositoryProvider);
    final outboxRepo = ref.read(outboxRepositoryProvider);

    final messages = await messageRepo.getConversation(identity.lettalkId, otherLettalkId);
    final outbox = await outboxRepo.getForConversation(identity.lettalkId, otherLettalkId);
    return mergeAndSort(messages, outbox);
  }

  Future<void> sendMessage(String plaintext) async {
    // Never throws on an unknown recipient — the engine queues to the
    // outbox automatically. The user always sees their message appear.
    await UraniumProtocolEngine.instance.sendMessage(
      recipientId: arg,
      plaintext: plaintext,
    );
    ref.invalidateSelf();
    await future;
    ref.invalidate(conversationsProvider);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}
