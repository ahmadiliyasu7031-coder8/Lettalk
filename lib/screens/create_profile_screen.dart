import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../providers/identity_provider.dart';
import '../services/background_relay_service.dart';
import '../utils/id_generator.dart';
import 'home_screen.dart';

class CreateProfileScreen extends ConsumerStatefulWidget {
  const CreateProfileScreen({super.key});

  @override
  ConsumerState<CreateProfileScreen> createState() => _CreateProfileScreenState();
}

class _CreateProfileScreenState extends ConsumerState<CreateProfileScreen> {
  final _usernameController = TextEditingController();
  late final String _previewLettalkId;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    // Generate the ID up front so the user sees their permanent
    // identity before confirming — the brief shows it on this screen.
    _previewLettalkId = IdGenerator.generateLettalkId();
  }

  Future<void> _continue() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      await ref
          .read(identityProvider.notifier)
          .createIdentity(_usernameController.text, lettalkId: _previewLettalkId);
      await BackgroundRelayService().initializeAndStart();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              const Text(
                'Create Your Profile',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose a username for your identity',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 40),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primaryGreen, width: 2),
                  ),
                  child: const Icon(Icons.person, size: 44, color: AppColors.primaryGreen),
                ),
              ),
              const SizedBox(height: 32),
              const Text('Username', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: _usernameController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(hintText: 'Ahmad'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 24),
              const Text('Your Lettalk ID (Generated)',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _previewLettalkId,
                        style: const TextStyle(
                          color: AppColors.primaryGreen,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, color: AppColors.textSecondary, size: 18),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _previewLettalkId));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Lettalk ID copied')),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'This ID is unique to you. Share it with others to chat.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _creating ? null : _continue,
                  child: _creating
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Text('CONTINUE', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
