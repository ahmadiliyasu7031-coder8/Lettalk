import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

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
      final thread = ref.read(conversationThreadProvider(id).notifier);
      await thread.sendMessage(text);

      if (!mounted) return;
      final contactsRepo = ref.read(contactRepositoryProvider);
      final contact = await contactsRepo.getContact(id);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            contact: contact ?? Contact(lettalkId: id, username: id, lastSeen: 0),
          ),
        ),
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

/// Camera permission AND camera hardware readiness are checked
/// explicitly before the scanner widget is ever built — this is what
/// was missing before, which is why a denied/unready camera crashed
/// with a raw native null-reference error instead of showing a
/// friendly message.
class _QrScanScreen extends StatefulWidget {
  const _QrScanScreen();

  @override
  State<_QrScanScreen> createState() => _QrScanScreenState();
}

enum _ScanState { checking, ready, denied, cameraError }

class _QrScanScreenState extends State<_QrScanScreen> {
  _ScanState _state = _ScanState.checking;
  String? _cameraErrorMessage;
  MobileScannerController? _controller;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _checkPermission() async {
    setState(() => _state = _ScanState.checking);
    final status = await Permission.camera.request();
    if (!mounted) return;

    if (status.isGranted) {
      _controller = MobileScannerController();
      setState(() => _state = _ScanState.ready);
    } else {
      setState(() => _state = _ScanState.denied);
    }
  }

  void _onCameraError(BuildContext context, MobileScannerException error) {
    // mobile_scanner's own errorBuilder hook — this is what stops a
    // camera-init failure from crashing the whole app with a raw
    // native exception, and shows a retryable message instead.
    if (!mounted) return;
    setState(() {
      _state = _ScanState.cameraError;
      _cameraErrorMessage = error.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Scan Lettalk ID')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _ScanState.checking:
        return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));

      case _ScanState.denied:
        return _MessageWithAction(
          icon: Icons.camera_alt_outlined,
          title: 'Camera Permission Needed',
          message:
              'Lettalk needs camera access to scan a Lettalk ID QR code. '
              'You can still add contacts by typing their ID manually.',
          buttonLabel: 'Open App Settings',
          onPressed: () => AppSettings.openAppSettings(),
          secondaryLabel: 'Try Again',
          onSecondaryPressed: _checkPermission,
        );

      case _ScanState.cameraError:
        return _MessageWithAction(
          icon: Icons.error_outline,
          title: 'Camera Unavailable',
          message: 'The camera could not be started on this device.'
              '${_cameraErrorMessage != null ? '\n\n$_cameraErrorMessage' : ''}'
              '\n\nYou can still add contacts by typing their ID manually.',
          buttonLabel: 'Try Again',
          onPressed: _checkPermission,
        );

      case _ScanState.ready:
        return MobileScanner(
          controller: _controller,
          errorBuilder: (context, error) {
            // Defer the state change so we don't call setState during build.
            WidgetsBinding.instance.addPostFrameCallback((_) => _onCameraError(context, error));
            return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
          },
          onDetect: (capture) {
            final barcodes = capture.barcodes;
            if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
              Navigator.of(context).pop(barcodes.first.rawValue);
            }
          },
        );
    }
  }
}

class _MessageWithAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryPressed;

  const _MessageWithAction({
    required this.icon,
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
    this.secondaryLabel,
    this.onSecondaryPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.statusWeak, size: 48),
            const SizedBox(height: 20),
            Text(title,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(message,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                textAlign: TextAlign.center),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: onPressed, child: Text(buttonLabel)),
            ),
            if (secondaryLabel != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onSecondaryPressed,
                child: Text(secondaryLabel!, style: const TextStyle(color: AppColors.textSecondary)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
