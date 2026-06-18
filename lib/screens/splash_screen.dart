import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../providers/identity_provider.dart';
import '../services/background_relay_service.dart';
import '../services/permission_service.dart';
import 'create_profile_screen.dart';
import 'home_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  double _progress = 0.0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _errorMessage = null);
    try {
      final progressTimer = Stream.periodic(const Duration(milliseconds: 60), (i) => i)
          .take(20)
          .listen((i) {
        if (mounted) setState(() => _progress = (i + 1) / 20);
      });

      final hasIdentity = await ref
          .read(identityProvider.notifier)
          .hasIdentity()
          .timeout(const Duration(seconds: 20));

      await PermissionService.requestAll().timeout(const Duration(seconds: 20));

      if (hasIdentity) {
        await BackgroundRelayService().initializeAndStart().timeout(const Duration(seconds: 20));
      }

      await Future.delayed(const Duration(milliseconds: 1200));
      await progressTimer.asFuture<void>().catchError((_) {});

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => hasIdentity ? const HomeScreen() : const CreateProfileScreen(),
        ),
      );
    } catch (e, stack) {
      // ignore: avoid_print
      print('Lettalk startup error: $e\n$stack');
      if (mounted) {
        setState(() => _errorMessage = e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  color: AppColors.primaryGreen,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text(
                    'L',
                    style: TextStyle(
                      fontSize: 52,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'LETTALK',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'When the Internet dies,\ncommunication lives.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 8),
              const Text(
                'by Ahmad Iliyasu Babura',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 48),
              if (_errorMessage == null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _progress,
                    minHeight: 6,
                    backgroundColor: AppColors.surface,
                    color: AppColors.primaryGreen,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Initializing Uranium Network…',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ] else ...[
                const Icon(Icons.error_outline, color: AppColors.statusBad, size: 32),
                const SizedBox(height: 12),
                const Text(
                  'Startup failed',
                  style: TextStyle(color: AppColors.statusBad, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _progress = 0.0);
                    _initialize();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
} 
