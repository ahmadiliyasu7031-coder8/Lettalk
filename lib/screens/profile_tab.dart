import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/constants.dart';
import '../providers/chat_providers.dart';
import '../providers/identity_provider.dart';
import '../utils/qr_payload.dart';
import 'message_status_screen.dart';
import 'network_tab.dart';
import 'settings_screen.dart';

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identityAsync = ref.watch(identityProvider);
    final statsAsync = ref.watch(messageStatsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Profile')),
      body: identityAsync.when(
        data: (identity) {
          if (identity == null) {
            return const Center(
              child: Text('No identity found', style: TextStyle(color: AppColors.textSecondary)),
            );
          }
          final joined = DateFormat.yMMMd().format(
            DateTime.fromMillisecondsSinceEpoch(identity.createdAt),
          );
          final qrData = QrPayload(
            lettalkId: identity.lettalkId,
            username: identity.username,
            publicKey: identity.publicKey,
          ).encode();

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primaryGreen, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      identity.username.isNotEmpty ? identity.username[0].toUpperCase() : '?',
                      style: const TextStyle(
                          color: AppColors.primaryGreen, fontSize: 36, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(identity.username,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text('Joined $joined',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    QrImageView(
                      data: qrData,
                      size: 160,
                      backgroundColor: Colors.white,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            identity.lettalkId,
                            style: const TextStyle(
                                color: AppColors.primaryGreen,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, color: AppColors.textSecondary, size: 18),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: identity.lettalkId));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Lettalk ID copied')),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              statsAsync.when(
                data: (stats) => Row(
                  children: [
                    Expanded(child: _StatBox(label: 'Sent', value: '${stats.sent}')),
                    const SizedBox(width: 12),
                    Expanded(child: _StatBox(label: 'Received', value: '${stats.received}')),
                  ],
                ),
                loading: () => const SizedBox(
                  height: 70,
                  child: Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
                ),
                error: (e, _) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 28),
              _ProfileLinkTile(
                icon: Icons.wifi_tethering,
                label: 'Your Area Network',
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const NetworkTab())),
              ),
              _ProfileLinkTile(
                icon: Icons.info_outline,
                label: 'Message Status Explained',
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const MessageStatusScreen())),
              ),
              _ProfileLinkTile(
                icon: Icons.settings_outlined,
                label: 'Settings',
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
        error: (e, _) => const Center(
          child: Text('Failed to load profile', style: TextStyle(color: AppColors.statusBad)),
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;

  const _StatBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  color: AppColors.primaryGreen, fontWeight: FontWeight.bold, fontSize: 22)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ProfileLinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ProfileLinkTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.card,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primaryGreen),
        title: Text(label, style: const TextStyle(color: AppColors.textPrimary)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        onTap: onTap,
      ),
    );
  }
}
