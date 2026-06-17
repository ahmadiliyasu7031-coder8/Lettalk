import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/constants.dart';
import '../models/contact.dart';
import '../providers/chat_providers.dart';
import '../utils/id_generator.dart';
import '../utils/qr_payload.dart';
import 'chat_screen.dart';

class NewMessageScreen extends ConsumerStatefulWidget {
  const NewMessageScreen({super.key});

  @override
  ConsumerState<NewMessageScreen> createState() => _NewMessageScreenState();
}

class _NewMessageScreenState extends ConsumerState<NewMessageScreen> {
  final _idController = TextEditingController();
  final _messageController = TextEditingController();
  String? _error;
  bool _sending = false;

  Future<void> _scanQr() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScanScreen()),
    );
    if (scanned == null) return;

    final payload = QrPayload.tryDecode(scanned);
    if (payload != null) {
      await ref.read(contactsProvider.notifier).addOrUpdateContact(
            lettalkId: payload.lettalkId,
            username: payload.username,
            publicKey: payload.publicKey,
          );
      setState(() => _idController.text = payload.lettalkId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${payload.username} as a contact')),
        );
      }
    } else {
      // Fall back to treating it as a bare ID, for IDs shared by other
      // means (typed/copy-pasted) — only works if already a known contact.
      setState(() => _idController.text = scanned.trim().toUpperCase());
    }
  }

  Future<void> _send() async {
    final id = _idController.text.trim().toUpperCase();
    final text = _messageController.text.trim();

    if (!IdGenerator.isValidLettalkId(id)) {
      setState(() => _error = 'Enter a valid Lettalk ID (format LTK-XXXX-XXXX)');
      return;
    }
    if (text.isEmpty) {
      setState(() => _error = 'Message cannot be empty');
      return;
    }

    setState(() {
      _error = null;
      _sending = true;
    });

    try {
      final contactsRepo = ref.read(contactRepositoryProvider);
      var contact = await contactsRepo.getContact(id);
      if (contact == null) {
        setState(() {
          _sending = false;
          _error =
              'No contact on file for $id yet. Add them first (QR / manual exchange) so their public key is known.';
        });
        return;
      }

      final thread = ref.read(conversationThreadProvider(id).notifier);
      await thread.sendMessage(text);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ChatScreen(contact: contact!)),
      );
    } catch (e) {
      setState(() {
        _error = 'Could not send: $e';
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('New Message')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Recipient Lettalk ID', style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _idController,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(hintText: 'LTK-XXXX-XXXX'),
                    textCapitalization: TextCapitalization.characters,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner, color: AppColors.primaryGreen),
                  onPressed: _scanQr,
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('Message', style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            TextField(
              controller: _messageController,
              style: const TextStyle(color: AppColors.textPrimary),
              maxLines: 5,
              decoration: const InputDecoration(hintText: 'Type your message…'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.statusBad, fontSize: 13)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _sending ? null : _send,
                child: _sending
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Text('SEND', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QrScanScreen extends StatelessWidget {
  const _QrScanScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Scan Lettalk ID')),
      body: MobileScanner(
        onDetect: (capture) {
          final barcodes = capture.barcodes;
          if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
            Navigator.of(context).pop(barcodes.first.rawValue);
          }
        },
      ),
    );
  }
}
