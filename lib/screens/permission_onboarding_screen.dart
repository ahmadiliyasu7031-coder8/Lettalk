import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/constants.dart';
import 'create_profile_screen.dart';

/// First-launch permission walkthrough — steps through BT, nearby
/// devices, and notifications one at a time, then continues to
/// Create Profile. Each step is skippable; the app never forces
/// the user to grant anything.
class PermissionOnboardingScreen extends StatefulWidget {
  const PermissionOnboardingScreen({super.key});

  @override
  State<PermissionOnboardingScreen> createState() =>
      _PermissionOnboardingScreenState();
}

class _PermissionOnboardingScreenState
    extends State<PermissionOnboardingScreen> {
  int _step = 0;
  bool _requesting = false;

  static const _steps = [
    _PermissionStep(
      icon: Icons.bluetooth,
      title: 'Bluetooth Access',
      description:
          'Lettalk needs Bluetooth to discover nearby devices AND to let '
          'nearby devices discover it. This is how messages travel through '
          'the mesh — device to device, with no internet required.',
      permissions: [Permission.bluetoothScan, Permission.bluetoothAdvertise],
      buttonLabel: 'Allow Bluetooth',
    ),
    _PermissionStep(
      icon: Icons.devices_other,
      title: 'Nearby Devices',
      description:
          'Lettalk also needs the Nearby Devices permission to connect to '
          'other Lettalk users around you, and (on older Android versions) '
          'a Location permission — required by Android itself for Bluetooth '
          'scan results to come back at all. Lettalk does not track your location.',
      permissions: [Permission.bluetoothConnect, Permission.locationWhenInUse],
      buttonLabel: 'Allow Nearby Devices',
    ),
    _PermissionStep(
      icon: Icons.notifications_outlined,
      title: 'Notifications',
      description:
          'Allow notifications so Lettalk can alert you when a new message '
          'arrives — even when the app is in the background.',
      permissions: [Permission.notification],
      buttonLabel: 'Allow Notifications',
    ),
  ];

  Future<void> _requestCurrent() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      await _steps[_step].permissions.request();
    } catch (_) {}
    setState(() => _requesting = false);
    _next();
  }

  void _next() {
    if (_step < _steps.length - 1) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  void _finish() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CreateProfileScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];
    final isLast = _step == _steps.length - 1;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const SizedBox(height: 24),
              // Step indicator dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_steps.length, (i) {
                  return Container(
                    width: i == _step ? 20 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i == _step
                          ? AppColors.primaryGreen
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
              const Spacer(),
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(44),
                  border: Border.all(color: AppColors.primaryGreen, width: 2),
                ),
                child: Icon(step.icon, color: AppColors.primaryGreen, size: 44),
              ),
              const SizedBox(height: 32),
              Text(
                step.title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                step.description,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _requesting ? null : _requestCurrent,
                  child: _requesting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : Text(step.buttonLabel,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _requesting ? null : _next,
                child: Text(
                  isLast ? 'Skip & Continue' : 'Skip for now',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionStep {
  final IconData icon;
  final String title;
  final String description;
  final List<Permission> permissions;
  final String buttonLabel;

  const _PermissionStep({
    required this.icon,
    required this.title,
    required this.description,
    required this.permissions,
    required this.buttonLabel,
  });
}
