import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../database/settings_repository.dart';
import '../providers/identity_provider.dart';
import '../services/background_relay_service.dart';
import 'create_profile_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _settingsRepo = SettingsRepository();
  final _usernameController = TextEditingController();

  int _scanInterval = 2;
  bool _nodeDiscoveredEnabled = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final interval = await _settingsRepo.getScanIntervalMinutes();
    final nodeDiscovered = await _settingsRepo.getNodeDiscoveredEnabled();
    final identity = ref.read(identityProvider).value;
    if (identity != null) _usernameController.text = identity.username;
    setState(() {
      _scanInterval = interval;
      _nodeDiscoveredEnabled = nodeDiscovered;
      _loaded = true;
    });
  }

  Future<void> _saveUsername() async {
    final value = _usernameController.text.trim();
    if (value.isEmpty) return;
    await ref.read(identityProvider.notifier).updateUsername(value);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Username updated')));
    }
  }

  Future<void> _clearRelayedMessages() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Clear Relay Data'),
        content: const Text(
          'This removes messages this device is carrying purely as a relay (not addressed to or from you). It does not affect your own conversations.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear', style: TextStyle(color: AppColors.statusBad)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Relay data cleared')));
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Log Out'),
        content: const Text(
          'Logging out permanently deletes your Lettalk ID and keys from this device. There is no server backup — this cannot be undone, and you will need to create a brand-new identity.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log Out', style: TextStyle(color: AppColors.statusBad)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await BackgroundRelayService().stop();
    await ref.read(identityProvider.notifier).logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const CreateProfileScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
      );
    }

    final identity = ref.watch(identityProvider).value;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const _SectionLabel('Profile'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _usernameController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(hintText: 'Username'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: _saveUsername, child: const Text('Save')),
            ],
          ),
          const SizedBox(height: 12),
          if (identity != null)
            Row(
              children: [
                Expanded(
                  child: Text(identity.lettalkId,
                      style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, color: AppColors.textSecondary, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: identity.lettalkId));
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Lettalk ID copied')));
                  },
                ),
              ],
            ),
          const SizedBox(height: 28),
          const _SectionLabel('Notifications'),
          SwitchListTile(
            value: _nodeDiscoveredEnabled,
            onChanged: (v) async {
              setState(() => _nodeDiscoveredEnabled = v);
              await _settingsRepo.setNodeDiscoveredEnabled(v);
            },
            activeColor: AppColors.primaryGreen,
            title: const Text('Notify on Node Discovered', style: TextStyle(color: AppColors.textPrimary)),
            subtitle: const Text('Alert when a nearby Lettalk device is found',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('Network'),
          const Text('Auto-Scan Interval', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1 min')),
              ButtonSegment(value: 2, label: Text('2 min')),
              ButtonSegment(value: 5, label: Text('5 min')),
            ],
            selected: {_scanInterval},
            onSelectionChanged: (selection) async {
              final minutes = selection.first;
              setState(() => _scanInterval = minutes);
              await _settingsRepo.setScanIntervalMinutes(minutes);
            },
          ),
          const SizedBox(height: 28),
          const _SectionLabel('Privacy & Data'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cleaning_services_outlined, color: AppColors.textPrimary),
            title: const Text('Clear Relay Data', style: TextStyle(color: AppColors.textPrimary)),
            subtitle: const Text('Free up storage used by messages you are only relaying',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            onTap: _clearRelayedMessages,
          ),
          const SizedBox(height: 16),
          const _SectionLabel('Appearance'),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.dark_mode, color: AppColors.textPrimary),
            title: Text('Theme', style: TextStyle(color: AppColors.textPrimary)),
            trailing: Text('Dark (only)', style: TextStyle(color: AppColors.textSecondary)),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('About'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.primaryGreen, size: 20),
                    SizedBox(width: 8),
                    Text('Lettalk',
                        style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
                SizedBox(height: 4),
                Text('People Are The Network. Version 1.0 (MVP)',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                SizedBox(height: 16),
                Text('ABOUT THE CREATOR',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6)),
                SizedBox(height: 8),
                Text(
                  'Ahmad Iliyasu was born in Babura, Babura Local Government Area, '
                  'Jigawa State, Nigeria. He studies Software Engineering at the '
                  'Federal University of Technology, Babura.',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.4),
                ),
                SizedBox(height: 12),
                Text(
                  '"If the whole world is looking south, turn and look north — '
                  'you\'ll discover many things others have missed."',
                  style: TextStyle(
                      color: AppColors.primaryGreen,
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      height: 1.4),
                ),
                SizedBox(height: 4),
                Text('— a saying shared by his friend Zakiyu Abdulkarim',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                SizedBox(height: 12),
                Text('With thanks to his advisor, Mustapha Lawan.',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                SizedBox(height: 16),
                Text('Ahmadiliyasubabura@gmail.com',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                SizedBox(height: 2),
                Text('07083324469', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.statusBad),
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _logout,
              child: const Text('LOG OUT', style: TextStyle(color: AppColors.statusBad, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
            color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8),
      ),
    );
  }
} 
