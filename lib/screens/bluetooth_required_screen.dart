import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../services/permission_service.dart';

/// Shown when Bluetooth HARDWARE is off (separate from the app's
/// Bluetooth PERMISSION, which may already be granted). The user can
/// either jump to system Bluetooth settings, or continue using the
/// app offline — they are NEVER forced to enable Bluetooth.
///
/// Auto-resume: when the user comes back from the system Settings app
/// (where they presumably just flipped the Bluetooth/Location switch),
/// this screen notices the app resuming and re-checks automatically —
/// no need to tap "check again" by hand.
///
/// Back button: pressing back here behaves the same as "Continue
/// Offline" rather than abruptly exiting the app.
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

class _BluetoothRequiredScreenState extends State<BluetoothRequiredScreen>
    with WidgetsBindingObserver {
  bool _checking = false;
  bool _leftAppForSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only auto-recheck if the user actually left to go to Settings
    // from one of our buttons — otherwise every app switch would
    // trigger a check for no reason.
    if (state == AppLifecycleState.resumed && _leftAppForSettings) {
      _leftAppForSettings = false;
      _checkAgain(silent: true);
    }
  }

  Future<void> _openBluetoothSettings() async {
    _leftAppForSettings = true;
    await AppSettings.openAppSettings(type: AppSettingsType.bluetooth);
  }

  Future<void> _openLocationSettings() async {
    _leftAppForSettings = true;
    await AppSettings.openAppSettings(type: AppSettingsType.location);
  }

  Future<void> _checkAgain({bool silent = false}) async {
    if (!silent) setState(() => _checking = true);
    final isOn = await PermissionService.isBluetoothOn();
    if (!mounted) return;
    if (!silent) setState(() => _checking = false);
    if (isOn) {
      widget.onBluetoothEnabled();
    } else if (!silent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bluetooth still appears to be off')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) widget.onContinueOffline();
      },
      child: Scaffold(
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
                  'the Bluetooth radio ON. Switch Bluetooth (and Location, on older '
                  'Android versions) on using the buttons below, then come back — '
                  'Lettalk will notice automatically.',
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
      ),
    );
  }
}
