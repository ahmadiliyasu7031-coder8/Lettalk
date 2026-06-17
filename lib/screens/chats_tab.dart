import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../models/contact.dart';
import '../providers/chat_providers.dart';
import '../providers/identity_provider.dart';
import '../widgets/conversation_tile.dart';
import 'chat_screen.dart';
import 'message_status_screen.dart';
import 'new_message_screen.dart';

class ChatsTab extends ConsumerWidget {
  const ChatsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identityAsync = ref.watch(identityProvider);
    final conversationsAsync = ref.watch(conversationsProvider);
    final contactsAsync = ref.watch(contactsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Message status legend',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MessageStatusScreen()),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.black,
        child: const Icon(Icons.add_comment),
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NewMessageScreen()),
          );
        },
      ),
      body: identityAsync.when(
        data: (identity) {
          if (identity == null) {
            return const Center(
              child: Text('No identity found.', style: TextStyle(color: AppColors.textSecondary)),
            );
          }
          return conversationsAsync.when(
            data: (messages) {
              if (messages.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No chats yet. Tap the button below to message someone using their Lettalk ID.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                );
              }
              final contacts = contactsAsync.value ?? <Contact>[];
              return ListView.separated(
                itemCount: messages.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: AppColors.surface),
                itemBuilder: (context, index) {
                  final message = messages[index];
                  final isOutgoing = message.senderId == identity.lettalkId;
                  final otherId = isOutgoing ? message.recipientId : message.senderId;
                  final contact = contacts.firstWhere(
                    (c) => c.lettalkId == otherId,
                    orElse: () => Contact(
                      lettalkId: otherId,
                      username: otherId,
                      lastSeen: 0,
                    ),
                  );
                  return ConversationTile(
                    contact: contact,
                    lastMessage: message,
                    isOutgoing: isOutgoing,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(contact: contact),
                        ),
                      );
                    },
                  );
                },
              );
            },
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primaryGreen),
            ),
            error: (e, _) => Center(
              child: Text('Failed to load chats', style: const TextStyle(color: AppColors.statusBad)),
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primaryGreen),
        ),
        error: (e, _) => const Center(
          child: Text('Failed to load identity', style: TextStyle(color: AppColors.statusBad)),
        ),
      ),
    );
  }
}
