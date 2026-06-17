import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../database/identity_repository.dart';
import '../database/message_repository.dart';
import '../models/contact.dart';
import '../models/message.dart';
import '../providers/chat_providers.dart';
import '../providers/identity_provider.dart';
import '../services/encryption_service.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final Contact contact;

  const ChatScreen({super.key, required this.contact});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  bool _muted = false;

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(conversationThreadProvider(widget.contact.lettalkId).notifier).sendMessage(text);
      _inputController.clear();
      await Future.delayed(const Duration(milliseconds: 100));
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _openOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => _ChatOptionsSheet(
        contact: widget.contact,
        muted: _muted,
        onToggleMute: () {
          setState(() => _muted = !_muted);
          Navigator.of(sheetContext).pop();
        },
        onClearChat: () async {
          Navigator.of(sheetContext).pop();
          await _confirmAndClearChat();
        },
        onDeleteChat: () async {
          Navigator.of(sheetContext).pop();
          await _confirmAndClearChat(isDelete: true);
        },
      ),
    );
  }

  Future<void> _confirmAndClearChat({bool isDelete = false}) async {
    final identity = ref.read(identityProvider).value;
    if (identity == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(isDelete ? 'Delete Chat' : 'Clear Chat'),
        content: Text(
          isDelete
              ? 'This removes the entire conversation with ${widget.contact.username} from this device. This cannot be undone.'
              : 'This clears all messages in this chat from this device. This cannot be undone.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm', style: TextStyle(color: AppColors.statusBad)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final messages = await MessageRepository().getConversation(identity.lettalkId, widget.contact.lettalkId);
    for (final m in messages) {
      await MessageRepository().deleteMessage(m.messageId);
    }
    ref.invalidate(conversationThreadProvider(widget.contact.lettalkId));
    ref.invalidate(conversationsProvider);
    if (isDelete && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final threadAsync = ref.watch(conversationThreadProvider(widget.contact.lettalkId));
    final identityAsync = ref.watch(identityProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.contact.username),
        actions: [
          IconButton(icon: const Icon(Icons.more_vert), onPressed: _openOptions),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: identityAsync.when(
              data: (identity) {
                if (identity == null) return const SizedBox.shrink();
                return threadAsync.when(
                  data: (messages) => _DecryptedThread(
                    messages: messages,
                    myId: identity.lettalkId,
                    contact: widget.contact,
                    scrollController: _scrollController,
                  ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
                  error: (e, _) =>
                      const Center(child: Text('Failed to load thread', style: TextStyle(color: AppColors.statusBad))),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
              error: (e, _) => const SizedBox.shrink(),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(hintText: 'Message…'),
                      minLines: 1,
                      maxLines: 4,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryGreen),
                          )
                        : const Icon(Icons.send, color: AppColors.primaryGreen),
                    onPressed: _sending ? null : _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Decrypts each message in the thread for display. Both directions use
/// the same shared secret — ECDH(myPrivateKey, theirPublicKey) — since
/// X25519 key agreement is symmetric, so this works for sent and
/// received messages alike.
class _DecryptedThread extends StatefulWidget {
  final List<LettalkMessage> messages;
  final String myId;
  final Contact contact;
  final ScrollController scrollController;

  const _DecryptedThread({
    required this.messages,
    required this.myId,
    required this.contact,
    required this.scrollController,
  });

  @override
  State<_DecryptedThread> createState() => _DecryptedThreadState();
}

class _DecryptedThreadState extends State<_DecryptedThread> {
  Map<String, String> _decrypted = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _decryptAll();
  }

  @override
  void didUpdateWidget(covariant _DecryptedThread oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messages.length != widget.messages.length) {
      _decryptAll();
    }
  }

  Future<void> _decryptAll() async {
    if (widget.contact.publicKey == null) {
      setState(() => _loading = false);
      return;
    }
    // Looked up directly rather than via Riverpod since this widget is a
    // plain State (decryption is a one-shot side effect, not something
    // that needs to rebuild reactively on identity changes mid-thread).
    final identityRepo = IdentityRepository();
    final identity = await identityRepo.getIdentity();
    if (identity == null) {
      setState(() => _loading = false);
      return;
    }
    final encryption = EncryptionService.instance;
    final privateKeyPlain = await encryption.decryptPrivateKey(identity.encryptedPrivateKey);
    final sharedSecret = await encryption.deriveSharedSecret(
      myPrivateKeyPlainBase64: privateKeyPlain,
      theirPublicKeyBase64: widget.contact.publicKey!,
    );

    final results = <String, String>{};
    for (final m in widget.messages) {
      if (m.content.isEmpty) continue;
      try {
        results[m.messageId] =
            await encryption.decryptContent(encryptedBase64: m.content, sharedSecret: sharedSecret);
      } catch (_) {
        results[m.messageId] = '[unable to decrypt]';
      }
    }
    if (mounted) {
      setState(() {
        _decrypted = results;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.scrollController.hasClients) {
          widget.scrollController.jumpTo(widget.scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
    }
    if (widget.messages.isEmpty) {
      return const Center(
        child: Text('Say hello — your message goes out over the mesh.',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: widget.messages.length,
      itemBuilder: (context, index) {
        final m = widget.messages[index];
        final isOutgoing = m.senderId == widget.myId;
        return MessageBubble(
          message: m,
          isOutgoing: isOutgoing,
          displayText: _decrypted[m.messageId] ?? '[unable to decrypt]',
        );
      },
    );
  }
}

class _ChatOptionsSheet extends StatelessWidget {
  final Contact contact;
  final bool muted;
  final VoidCallback onToggleMute;
  final VoidCallback onClearChat;
  final VoidCallback onDeleteChat;

  const _ChatOptionsSheet({
    required this.contact,
    required this.muted,
    required this.onToggleMute,
    required this.onClearChat,
    required this.onDeleteChat,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline, color: AppColors.textPrimary),
            title: const Text('View Contact', style: TextStyle(color: AppColors.textPrimary)),
            subtitle: Text(contact.lettalkId, style: const TextStyle(color: AppColors.textSecondary)),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.search, color: AppColors.textPrimary),
            title: const Text('Search Chat', style: TextStyle(color: AppColors.textPrimary)),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined, color: AppColors.textPrimary),
            title: const Text('Clear Chat', style: TextStyle(color: AppColors.textPrimary)),
            onTap: onClearChat,
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppColors.statusBad),
            title: const Text('Delete Chat', style: TextStyle(color: AppColors.statusBad)),
            onTap: onDeleteChat,
          ),
          ListTile(
            leading: const Icon(Icons.ios_share, color: AppColors.textPrimary),
            title: const Text('Export Chat', style: TextStyle(color: AppColors.textPrimary)),
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Export is coming in a future update')),
              );
            },
          ),
          ListTile(
            leading: Icon(
              muted ? Icons.notifications_off_outlined : Icons.notifications_active_outlined,
              color: AppColors.textPrimary,
            ),
            title: Text(muted ? 'Unmute Notifications' : 'Mute Notifications',
                style: const TextStyle(color: AppColors.textPrimary)),
            onTap: onToggleMute,
          ),
        ],
      ),
    );
  }
}
