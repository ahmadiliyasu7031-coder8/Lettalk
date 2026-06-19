import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../services/permission_service.dart';

/// Shown when Bluetooth HARDWARE is off (separate from the app's
/// Bluetooth PERMISSION, which may already be granted). The user can
/// either jump to system Bluetooth settings, or continue using the
/// app offline — they are NEVER forced to enable Bluetooth.
class BluetoothRequiredScreen extends StatefulWidget {
  final VoidCallback onContinueOffline;
  final VoidCallback onBluetoothEnabled;

  const BluetoothRequiredScreen({
    super.key,
    required this.onContinueOffline,
    required this.onBluetoothEnabled,
  });

  @override
  State<BluetoothRequiredScreen> createState() => _BluetoothRequiredScreenState();
}

class _BluetoothRequiredScreenState extends State<BluetoothRequiredScreen> {
  bool _checking = false;

  Future<void> _openBluetoothSettings() async {
    await AppSettings.openAppSettings(type: AppSettingsType.bluetooth);
  }

  Future<void> _openLocationSettings() async {
    await AppSettings.openAppSettings(type: AppSettingsType.location);
  }

  Future<void> _checkAgain() async {
    setState(() => _checking = true);
    final isOn = await PermissionService.isBluetoothOn();
    if (!mounted) return;
    setState(() => _checking = false);
    if (isOn) {
      widget.onBluetoothEnabled();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bluetooth still appears to be off')),
      );
    }
  }

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
                child: const Icon(Icons.bluetooth_disabled, color: AppColors.statusWeak, size: 40),
              ),
              const SizedBox(height: 28),
              const Text(
                'Bluetooth Required',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Lettalk uses Bluetooth to relay messages through nearby devices — '
                'no internet or SIM needed.\n\n'
                'Turning the permission ON in this app is not the same as turning '
                'the Bluetooth radio ON. Please switch Bluetooth (and Location, on '
                'older Android versions) on from your phone\'s quick settings or '
                'the buttons below.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.bluetooth),
                  label: const Text('Open Bluetooth Settings'),
                  onPressed: _openBluetoothSettings,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.location_on_outlined, color: AppColors.textSecondary),
                  label: const Text('Open Location Settings',
                      style: TextStyle(color: AppColors.textSecondary)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    side: const BorderSide(color: AppColors.textSecondary),
                  ),
                  onPressed: _openLocationSettings,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _checking ? null : _checkAgain,
                  child: _checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryGreen),
                        )
                      : const Text("I've turned it on — check again",
                          style: TextStyle(color: AppColors.primaryGreen)),
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
                  onPressed: widget.onContinueOffline,
                  child: const Text('Continue Offline', style: TextStyle(color: AppColors.textSecondary)),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'You can still read previous messages and compose new ones.\n'
                'They will be sent automatically once Bluetooth is on.',
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
