import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../database/database_helper.dart';
import '../providers/identity_provider.dart';
import '../providers/uranium_status_provider.dart';
import '../services/background_relay_service.dart';
import '../services/permission_service.dart';
import 'bluetooth_required_screen.dart';
import 'home_screen.dart';
import 'permission_onboarding_screen.dart';

/// Splash screen — MAXIMUM ~3 seconds, then moves on regardless of
/// Bluetooth state, permissions, or Uranium readiness.
///
/// Architecture rule: the user is NEVER blocked here. All heavy init
/// (Uranium engine, BLE advertising) runs in the background AFTER
/// the user is already in the app.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeIn);
    _anim.forward();
    _startup();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _startup() async {
    try {
      await DatabaseHelper.instance.database.timeout(const Duration(seconds: 4));
    } catch (_) {}

    bool hasIdentity = false;
    try {
      hasIdentity = await ref
          .read(identityProvider.notifier)
          .hasIdentity()
          .timeout(const Duration(seconds: 4));
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;

    if (hasIdentity) {
      await _goToHomeOrBluetoothCheck();
    } else {
      Navigator.of(context).pushReplacement(_fade_(const PermissionOnboardingScreen()));
    }
  }

  /// Returning users: check whether the Bluetooth radio is actually on
  /// (separate from the permission being granted). If it's off, show the
  /// Bluetooth Required screen as an interstitial — but "Continue Offline"
  /// always gets them into Home regardless.
  Future<void> _goToHomeOrBluetoothCheck() async {
    // Returning users skip the onboarding screens entirely, so this is
    // the only place that (re)requests anything still missing — e.g.
    // bluetoothAdvertise, which an existing install from before this
    // fix would never have been asked to grant.
    try {
      await PermissionService.ensureAllGranted().timeout(const Duration(seconds: 8));
    } catch (_) {}

    bool btOn = false;
    try {
      btOn = await PermissionService.isBluetoothOn().timeout(const Duration(seconds: 3));
    } catch (_) {}

    if (!mounted) return;

    if (btOn) {
      _startUraniumInBackground();
      Navigator.of(context).pushReplacement(_fade_(const HomeScreen()));
    } else {
      Navigator.of(context).pushReplacement(
        _fade_(BluetoothRequiredScreen(
          onBluetoothEnabled: () {
            _startUraniumInBackground();
            Navigator.of(context).pushReplacement(_fade_(const HomeScreen()));
          },
          onContinueOffline: () {
            ref.read(uraniumStatusProvider.notifier).state = UraniumStatus.offline;
            Navigator.of(context).pushReplacement(_fade_(const HomeScreen()));
          },
        )),
      );
    }
  }

  void _startUraniumInBackground() {
    ref.read(uraniumStatusProvider.notifier).state = UraniumStatus.starting;

    BackgroundRelayService()
        .initializeAndStart()
        .timeout(const Duration(seconds: 10))
        .then((_) {
      if (mounted) {
        ref.read(uraniumStatusProvider.notifier).state = UraniumStatus.active;
      }
    }).catchError((_) {
      if (mounted) {
        ref.read(uraniumStatusProvider.notifier).state = UraniumStatus.offline;
      }
    });
  }

  PageRouteBuilder _fade_(Widget page) {
    return PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: FadeTransition(
        opacity: _fade,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: const BoxDecoration(color: AppColors.primaryGreen, shape: BoxShape.circle),
                child: const Center(
                  child: Text('L',
                      style: TextStyle(fontSize: 58, fontWeight: FontWeight.bold, color: Colors.black)),
                ),
              ),
              const SizedBox(height: 24),
              const Text('LETTALK',
                  style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.0,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              const Text('People Are The Network',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 6),
              const Text('by Ahmad Iliyasu Babura',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              const SizedBox(height: 56),
              SizedBox(
                width: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const LinearProgressIndicator(
                    minHeight: 4,
                    backgroundColor: AppColors.surface,
                    color: AppColors.primaryGreen,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
