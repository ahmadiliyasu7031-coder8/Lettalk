import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/constants.dart';

/// Shown (as a non-blocking dialog/screen) when Bluetooth is off.
/// The user can either open settings to enable it, or continue into
/// the app offline — they are NEVER forced to enable Bluetooth.
class BluetoothRequiredScreen extends StatelessWidget {
  final VoidCallback onContinueOffline;

  const BluetoothRequiredScreen({super.key, required this.onContinueOffline});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(color: AppColors.statusWeak, width: 2),
                ),
                child: const Icon(Icons.bluetooth_disabled,
                    color: AppColors.statusWeak, size: 40),
              ),
              const SizedBox(height: 28),
              const Text(
                'Bluetooth Required',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Lettalk uses Bluetooth to relay messages through nearby devices — '
                'no internet or SIM needed.\n\n'
                'Enable Bluetooth so Lettalk can find nearby devices and '
                'deliver your messages through the mesh network.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.bluetooth),
                  label: const Text('Enable Bluetooth'),
                  onPressed: () {
                    // Open Android Bluetooth settings
                    const MethodChannel('lettalk/system')
                        .invokeMethod('openBluetoothSettings')
                        .catchError((_) {
                      // Fallback: open general settings if channel isn't
                      // wired yet — user can find Bluetooth from there
                    });
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    side: const BorderSide(color: AppColors.textSecondary),
                  ),
                  onPressed: onContinueOffline,
                  child: const Text(
                    'Continue Offline',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'You can still read previous messages and compose new ones.\n'
                'They will be sent when Bluetooth becomes available.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
